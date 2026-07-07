import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';
import 'engine.dart';
import 'dart_http_engine.dart';
import 'persistence.dart';

/// Simple, resilient file upload queue.
///
/// Usage:
/// ```dart
/// final queue = UploadQueue(
///   config: UploadConfig(
///     initUploadEndpoint: '$baseUrl/course/module/lesson/upload',
///     tokenProvider: () => myToken,
///     buildCallback: (task) => CallbackRequest(
///       url: '$baseUrl/course/module/lesson',
///       body: {'videoUrl': task.fileUrl, 'title': task.title},
///     ),
///   ),
/// );
///
/// // Add a file
/// final task = await queue.add(file: myFile, title: 'Lesson 1');
///
/// // Listen to updates
/// queue.onUpdate.listen((_) => setState(() {}));
/// queue.tasks; // current state
/// ```
class UploadQueue {
  final UploadConfig config;
  final Persistence _persistence;
  late final UploadEngine _engine;

  final _controller = StreamController<List<UploadTask>>.broadcast();
  List<UploadTask> _tasks = [];
  final _processingLock = Lock();
  Timer? _pumpTimer;
  bool _disposed = false;
  final Set<int> _activeProcessingIds = {};

  /// Current snapshot of all active (non-terminal) tasks.
  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  /// Broadcast stream — emits on every task state change.
  Stream<List<UploadTask>> get onUpdate => _controller.stream;

  UploadQueue({required this.config, UploadEngine? engine, Persistence? persistence})
      : _engine = engine ?? DartHttpEngine(config),
        _persistence = persistence ?? Persistence() {
    _init();
  }

  Future<void> _init() async {
    try {
      // One-time legacy DB migration
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final legacyPath = p.join(docsDir.path, 'upload_queue.db');
        final migrated = await _persistence.migrateFromLegacy(legacyPath);
        if (migrated > 0) {
          _log('[UploadQueue] migrated $migrated tasks from legacy DB');
        }
      } catch (_) {}

      await _persistence.deleteOldItems();
      _tasks = await _persistence.getAll();

      // Resume any in-flight uploads — but STRICTLY FIFO. We do not fire all
      // resumes concurrently; instead we hand them to the single serial
      // processor (_processNext), which claims the oldest task first and
      // runs one video at a time. This guarantees first-in-first-out ordering
      // across videos even after an app kill with multiple in-flight uploads.
      final uploading = await _persistence.getUploading();
      if (uploading.isNotEmpty) {
        _log('[UploadQueue] ${uploading.length} in-flight task(s) to resume (FIFO)');
      }

      _startPump();
      _emit();

      // Kick the serial processor. It will resume/continue tasks one by one
      // in id (FIFO) order.
      unawaited(_processNext());
    } catch (e) {
      _log('[UploadQueue] init error: $e');
    }
  }

  void _startPump() {
    _pumpTimer?.cancel();
    _pumpTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        if (_disposed) return;
        final all = await _persistence.getActive();
        final now = DateTime.now();
        for (final item in all) {
          if (item.state == UploadState.uploading &&
              !_activeProcessingIds.contains(item.id) &&
              now.difference(item.updatedAt) > const Duration(minutes: 10)) {
            _log('[UploadQueue] stale task #${item.id} — resetting');
            if (item.s3UploadId != null && item.s3UploadId!.isNotEmpty) {
              await _engine.abortMultipart(
                item.s3UploadId!,
                endpoint: config.buildAbortEndpoint?.call(item) ??
                    config.buildCompleteEndpoint?.call(item) ??
                    item.metadata?['initEndpoint'] as String?,
                s3Key: item.s3Key,
              );
            }
            await _persistence.clearMultipartState(item.id);
            await _persistence.markFailed(item.id, 'Timed out');
            _tasks = await _persistence.getAll();
            _emit();
          }
        }

        if (!_processingLock.isLocked) {
          unawaited(_processNext());
        }

        // Periodic DB maintenance (every 15s pump tick)
        unawaited(_persistence.optimize());
      } catch (_) {}
    });
  }

  /// Add a file to the upload queue.
  Future<UploadTask> add({
    required File file,
    required String title,
    Map<String, dynamic>? metadata,
  }) async {
    if (_disposed) throw StateError('UploadQueue is disposed');

    // Enforce queue depth limit
    if (config.maxQueueSize > 0) {
      final count = await _persistence.countActive();
      if (count >= config.maxQueueSize) {
        await _evictOldestFailed();
        final newCount = await _persistence.countActive();
        if (newCount >= config.maxQueueSize) {
          throw StateError('Upload queue is full (max $count)');
        }
      }
    }

    final id = await _persistence.insert(
      filePath: file.path,
      title: title,
      metadata: metadata,
    );
    _tasks = await _persistence.getAll();
    _emit();
    unawaited(_processNext());
    return _tasks.firstWhere((t) => t.id == id);
  }

  /// Evict the oldest failed/timed-out tasks when the queue is full.
  Future<void> _evictOldestFailed() async {
    final all = await _persistence.getAll();
    final terminal = all.where((t) =>
        t.state == UploadState.failed ||
        t.state == UploadState.completed ||
        t.state == UploadState.cancelled).toList();
    terminal.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final toRemove = terminal.take((terminal.length * 0.25).ceil());
    for (final task in toRemove) {
      await _persistence.deleteItem(task.id);
    }
  }

  /// Remove a pending/failed task from the queue.
  Future<void> remove(int id) async {
    await _persistence.deleteItem(id);
    _tasks = await _persistence.getAll();
    _emit();
  }

  /// Cancel an active upload (aborts multipart if applicable).
  Future<void> cancel(int id) async {
    var task = _tasks.where((t) => t.id == id).firstOrNull;
    task ??= await _persistence.getById(id);
    if (task == null) return;

    // Cancel the native background workers first so no new parts start.
    unawaited(_engine.cancelUpload(id));

    // Abort the S3 multipart session if one exists (frees S3 storage).
    if (task.s3UploadId != null && task.s3UploadId!.isNotEmpty) {
      unawaited(_engine.abortMultipart(
        task.s3UploadId!,
        endpoint: config.buildAbortEndpoint?.call(task) ??
            config.buildCompleteEndpoint?.call(task) ??
            task.metadata?['initEndpoint'] as String?,
        s3Key: task.s3Key,
      ));
    }

    await _persistence.markCancelled(id);
    _tasks = await _persistence.getAll();
    _emit();
  }

  Future<void> retry(int id) async {
    await _persistence.clearMultipartState(id);
    await _persistence.markPending(id);
    _tasks = await _persistence.getAll();
    _emit();
    unawaited(_processNext());
  }

  Future<void> _processNext() async {
    if (_disposed) return;
    if (!await _processingLock.acquire()) return;
    // dispose() may have been called while we yielded on acquire()
    if (_disposed) {
      _processingLock.release();
      return;
    }

    // ── Strict FIFO across videos ──
    // Priority 1: resume the oldest in-flight (uploading) task that isn't
    // already being processed. This ensures a video interrupted by an app
    // kill finishes before any newer queued video starts.
    if (_disposed) {
      _processingLock.release();
      return;
    }
    final resumable = await _persistence.getUploading();
    resumable.sort((a, b) => a.id.compareTo(b.id));
    final toResume = resumable
        .where((t) => !_activeProcessingIds.contains(t.id))
        .firstOrNull;
    if (toResume != null) {
      _activeProcessingIds.add(toResume.id);
      var waitingOnNative = false;
      try {
        waitingOnNative = await _resume(toResume);
      } catch (e, s) {
        _log('[UploadQueue] resume error for task #${toResume.id}: $e\n$s');
        try {
          await _persistence.markFailed(toResume.id, 'Resume error: ${e.runtimeType}');
        } catch (_) {}
      } finally {
        _activeProcessingIds.remove(toResume.id);
        _processingLock.release();
        _tasks = await _persistence.getAll();
        _emit();
        // Only chain to the next task if we're NOT waiting on a native
        // background chain to finish this one. If we are waiting, the 15s
        // pump re-checks later — re-triggering now would spin a tight loop
        // re-selecting the same still-running task.
        if (!_disposed && !waitingOnNative) unawaited(_processNext());
      }
      return;
    }

    // Priority 2: claim the oldest pending task (FIFO by id ASC).
    final task = await _persistence.claimNextPending();
    if (task == null) {
      _processingLock.release();
      return;
    }

    try {
      // Verify file still exists
      if (!File(task.filePath).existsSync()) {
        await _persistence.markFailed(task.id, 'File not found');
        _log('[UploadQueue] task #${task.id}: file not found');
        return;
      }

      _activeProcessingIds.add(task.id);
      _updateInList(task.copyWith(state: UploadState.uploading));

      _log('[UploadQueue] processing task #${task.id}: ${task.title}');

      // Phase 1: Init upload
      final initResult = await _engine.initUpload(
        filePath: task.filePath,
        extraFields: task.metadata,
      );

      if (initResult == null) {
        await _persistence.markFailed(task.id, 'Init upload failed');
        _log('[UploadQueue] task #${task.id}: init failed');
        return;
      }

      // Save fileUrl immediately (returned in both responses)
      if (initResult.fileUrl.isNotEmpty) {
        await _persistence.updateFileUrl(
          id: task.id,
          fileUrl: initResult.fileUrl,
        );
      }

      if (initResult.isMultipart) {
        await _processMultipart(task, initResult);
      } else {
        await _processDirect(task, initResult);
      }

      // Both _processMultipart and _processDirect mark completed/failed
      // internally; re-read from DB to confirm final state.
      final finalTask = await _persistence.getById(task.id);
      if (finalTask != null && finalTask.state == UploadState.completed) {
        _log('[UploadQueue] task #${task.id} completed');
      }
    } catch (e, s) {
      _log('[UploadQueue] error processing task #${task.id}: $e\n$s');
      try {
        await _persistence.markFailed(task.id, 'Error: ${e.runtimeType}');
      } catch (_) {}
    } finally {
      _activeProcessingIds.remove(task.id);
      _processingLock.release();
      _tasks = await _persistence.getAll();
      _emit();
      if (!_disposed) unawaited(_processNext());
    }
  }

  Future<void> _processMultipart(
    UploadTask task,
    InitUploadResponse initResult,
  ) async {
    final fileSize = await File(task.filePath).length();
    final partSize =
        UploadEngine.computePartSize(fileSize, initResult.totalParts);

    await _persistence.updateMultipartState(
      id: task.id,
      s3UploadId: initResult.s3UploadId ?? '',
      totalParts: initResult.totalParts,
      partSize: partSize,
      s3Key: initResult.key,
    );

    // Upload parts
    final results = await _engine.uploadParts(
      filePath: task.filePath,
      parts: initResult.parts,
      partSize: partSize,
      dbTaskId: task.id,
      onProgress: (completed, total) {
        _persistence.updateProgress(
          id: task.id,
          progress: total > 0 ? completed / total : 0,
        );
        _updateInList(task.copyWith(
          state: UploadState.uploading,
          progress: total > 0 ? completed / total : 0,
          partsCompleted: completed,
          totalParts: total,
        ));
      },
    );

    // Persist ETags
    for (final r in results) {
      if (r.success && r.eTag != null) {
        await _persistence.recordPartCompletion(
          id: task.id,
          partNumber: r.partNumber,
          eTag: r.eTag!,
        );
      }
    }

    final endpoint = task.metadata?['initEndpoint'] as String?;
    final completeEndpoint =
        config.buildCompleteEndpoint?.call(task) ?? endpoint;
    // The S3 object key is required in the complete/abort bodies. Merge it into
    // the completion extras so it lands as a top-level `key` field.
    final s3Key = initResult.key;
    final completeExtras = <String, dynamic>{
      ...?config.buildCompleteExtraFields?.call(task),
      if (s3Key != null && s3Key.isNotEmpty) 'key': s3Key,
    };

    final failed = results.where((r) => !r.success).toList();
    if (failed.isNotEmpty) {
      final expired = failed.where((r) => r.isUrlExpired).toList();
      if (expired.isNotEmpty) {
        _log('[UploadQueue] task #${task.id}: ${expired.length} part(s) expired — re-initing');
        // URLs expired — re-init to get fresh presigned URLs
        final fresh = await _engine.initUpload(
          filePath: task.filePath,
          extraFields: task.metadata,
        );
        if (fresh != null && fresh.isMultipart) {
          final remainingParts = fresh.parts
              .where((p) => expired.any((e) => e.partNumber == p.partNumber))
              .toList();
          if (remainingParts.isNotEmpty) {
            final retries = await _engine.uploadParts(
              filePath: task.filePath,
              parts: remainingParts,
              partSize: partSize,
              dbTaskId: task.id,
              onProgress: null,
            );
            for (final r in retries) {
              if (r.success && r.eTag != null) {
                await _persistence.recordPartCompletion(
                  id: task.id,
                  partNumber: r.partNumber,
                  eTag: r.eTag!,
                );
              }
            }
            // Re-check after retry
            final allFailed = retries.where((r) => !r.success).toList();
            if (allFailed.isNotEmpty) {
              await _engine.abortMultipart(
                initResult.s3UploadId ?? '',
                endpoint: config.buildAbortEndpoint?.call(task) ?? completeEndpoint,
                s3Key: s3Key,
              );
              await _persistence.clearMultipartState(task.id);
              await _persistence.markFailed(
                task.id,
                '${allFailed.length} part(s) failed after URL refresh',
              );
              return;
            }
          }
        } else {
          await _persistence.markFailed(task.id, 'Failed to refresh upload URLs');
          return;
        }
      } else {
        await _engine.abortMultipart(
          initResult.s3UploadId ?? '',
          endpoint: config.buildAbortEndpoint?.call(task) ?? completeEndpoint,
          s3Key: s3Key,
        );
        await _persistence.clearMultipartState(task.id);
        await _persistence.markFailed(
          task.id,
          '${failed.length} part(s) failed',
        );
        return;
      }
    }

    // Complete multipart and send callback — uses native WorkManager chain
    // when available (survives app kill), falls back to Dart HTTP otherwise.
    final etags = await _persistence.getPartETags(task.id);

    final callback = config.buildCallback?.call(task.copyWith(fileUrl: initResult.fileUrl));
    if (callback != null) {
      final fileUrl = await _engine.completeMultipartAndCallback(
        s3UploadId: initResult.s3UploadId ?? '',
        parts: etags,
        callback: callback,
        endpoint: completeEndpoint,
        dbTaskId: task.id,
        completeExtraFields: completeExtras,
      );

      if (fileUrl != null && fileUrl.isNotEmpty) {
        await _persistence.updateFileUrl(id: task.id, fileUrl: fileUrl);
        _updateInList(task.copyWith(fileUrl: fileUrl, progress: 1.0));
        await _completeTask(task.id);
        _log('[UploadQueue] task #${task.id}: chain completed (fileUrl=$fileUrl)');
        return;
      }

      // Fallback: try separate complete + callback (Dart)
      _log('[UploadQueue] task #${task.id}: chain failed, falling back to Dart');
    }

    // Dart fallback for completeMultipart
    String? fileUrl = await _engine.completeMultipart(
      s3UploadId: initResult.s3UploadId ?? '',
      parts: etags,
      endpoint: completeEndpoint,
      extraFields: completeExtras,
    );

    // Some backends don't expose a separate complete-multipart endpoint;
    // they return fileUrl directly in the init response and expect the
    // callback to trigger server-side completion.
    if (fileUrl == null || fileUrl.isEmpty) {
      fileUrl = initResult.fileUrl.isNotEmpty ? initResult.fileUrl : null;
      if (fileUrl != null) {
        _log('[UploadQueue] task #${task.id}: server has no complete endpoint — using init fileUrl');
      }
    }

    if (fileUrl == null || fileUrl.isEmpty) {
      await _engine.abortMultipart(
        initResult.s3UploadId ?? '',
        endpoint: config.buildAbortEndpoint?.call(task) ?? completeEndpoint,
        s3Key: s3Key,
      );
      await _persistence.clearMultipartState(task.id);
      await _persistence.markFailed(task.id, 'Complete multipart failed');
      return;
    }
    await _persistence.updateFileUrl(id: task.id, fileUrl: fileUrl);
    _updateInList(task.copyWith(fileUrl: fileUrl, progress: 1.0));

    // Callback — if it fails, task is still marked failed (retryable)
    final callbackOk = await _sendCallback(task.copyWith(fileUrl: fileUrl));
    if (!callbackOk) {
      await _persistence.markFailed(task.id, 'Server callback failed');
      return;
    }
  }

  Future<void> _processDirect(
    UploadTask task,
    InitUploadResponse initResult,
  ) async {
    final uploadUrl = initResult.uploadUrl;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      await _persistence.markFailed(task.id, 'Upload URL missing');
      return;
    }

    // Persist fileUrl immediately so _resume can use it if the app is
    // killed during the native upload (which completes in WorkManager).
    if (initResult.fileUrl.isNotEmpty) {
      await _persistence.updateFileUrl(id: task.id, fileUrl: initResult.fileUrl);
      _updateInList(task.copyWith(fileUrl: initResult.fileUrl));
    }

    final success = await _engine.directUpload(
      filePath: task.filePath,
      uploadUrl: uploadUrl,
      dbTaskId: task.id,
      onProgress: (progress) {
        _persistence.updateProgress(id: task.id, progress: progress);
        _updateInList(task.copyWith(
          state: UploadState.uploading,
          progress: progress,
        ));
      },
    );

    if (!success) {
      await _persistence.markFailed(task.id, 'Direct upload failed');
      return;
    }

    _updateInList(task.copyWith(progress: 1.0));

    // Callback — if it fails, task is still marked failed (retryable)
    final callbackOk = await _sendCallback(
      task.copyWith(fileUrl: initResult.fileUrl),
    );
    if (!callbackOk) {
      await _persistence.markFailed(task.id, 'Server callback failed');
      return;
    }
  }

  /// Resume a single in-flight task. Returns `true` when the task is now
  /// waiting on a native background chain to finish (caller should NOT
  /// immediately chain to the next task — the periodic pump re-checks).
  /// Returns `false` when the task reached a terminal state or was re-driven
  /// to completion/failure synchronously.
  Future<bool> _resume(UploadTask task) async {
    try {
      _log('[UploadQueue] resuming task #${task.id}');

      // ── Fast path 1: check the native complete+callback chain first.
      // If it already succeeded in the background (WorkManager finished the
      // CompleteWorker → CallbackWorker after the app was killed), we're done.
      final chain = await _engine.getChainStatus(task.id);
      if (chain != null) {
        final state = chain['state'] as String?;
        if (state == 'success') {
          final chainFileUrl = chain['fileUrl'] as String?;
          if (chainFileUrl != null && chainFileUrl.isNotEmpty) {
            await _persistence.updateFileUrl(
              id: task.id,
              fileUrl: chainFileUrl,
            );
          }
          await _completeTask(task.id);
          _log('[UploadQueue] task #${task.id}: chain finished while killed');
          _updateFromDb();
          return false;
        }
        if (state == 'running') {
          // Chain is still running natively — reflect state and back off.
          // The chain observer will eventually update the DB; leave
          // task uploading so periodic pump re-checks.
          _log('[UploadQueue] task #${task.id}: native chain still running');
          _updateFromDb();
          return true; // waiting on native — do not chain immediately
        }
        // 'failed' or 'unknown' → fall through and try to re-drive.
      }

      // File might be direct upload (no multipart state) — check if
      // the native WorkManager upload already completed while killed.
      final hasMultipartState =
          task.totalParts > 0 && task.s3UploadId != null;
      if (!hasMultipartState) {
        final completed = await _engine.checkUploadCompleted(task.id);
        if (completed == true) {
          _log('[UploadQueue] task #${task.id}: native upload already done — finishing');
          if (task.fileUrl == null || task.fileUrl!.isEmpty) {
            await _persistence.markFailed(task.id, 'Resume failed: fileUrl missing');
            _updateFromDb();
            return false;
          }
          final callbackOk = await _sendCallback(task);
          if (callbackOk) {
            await _completeTask(task.id);
          } else {
            await _persistence.markFailed(task.id, 'Server callback failed');
          }
          _updateFromDb();
          return false;
        }

        // Cancel any stale WorkManager tasks to avoid duplicate workers
        await _engine.cancelUpload(task.id);

        _log('[UploadQueue] task #${task.id}: no multipart state — re-queuing');
        await _persistence.markPending(task.id);
        _updateFromDb();
        return false;
      }

      // ── Fast path 2: parts may have finished natively while killed.
      // Query the native side; if all parts succeeded, jump straight to
      // complete+callback without re-uploading any bytes.
      final partsAllDone = await _engine.checkUploadCompleted(task.id);
      if (partsAllDone == true) {
        _log(
          '[UploadQueue] task #${task.id}: parts already uploaded in background — going straight to complete',
        );
        // Build a synthetic InitUploadResponse just to carry through
        // the existing fileUrl and s3UploadId into _completeAndFinish.
        final synthetic = InitUploadResponse(
          isMultipart: true,
          fileUrl: task.fileUrl ?? '',
          s3UploadId: task.s3UploadId,
          totalParts: task.totalParts,
          parts: const [],
        );
        await _completeAndFinish(task, synthetic);
        return false;
      }

      // Re-init to get fresh presigned URLs for remaining parts
      final initResult = await _engine.refreshPresignedUrls(
        filePath: task.filePath,
        s3UploadId: task.s3UploadId!,
        partNumbers: [
          for (int i = task.partsCompleted + 1; i <= task.totalParts; i++) i,
        ],
        extraFields: task.metadata,
      );
      if (initResult == null || !initResult.isMultipart) {
        await _persistence.markFailed(task.id, 'Resume failed — re-init failed');
        _updateFromDb();
        return false;
      }

      final remaining = initResult.parts
          .where((p) => p.partNumber > task.partsCompleted)
          .toList();

      if (remaining.isEmpty) {
        // All parts already uploaded — try complete
        await _completeAndFinish(task, initResult);
        return false;
      }

      final fileSize = await File(task.filePath).length();
      final partSize =
          UploadEngine.computePartSize(fileSize, initResult.totalParts);

      final results = await _engine.uploadParts(
        filePath: task.filePath,
        parts: remaining,
        partSize: partSize,
        dbTaskId: task.id,
        onProgress: (completed, total) {
          final overallProgress =
              task.totalParts > 0
                  ? (task.partsCompleted + completed) / task.totalParts
                  : 0.0;
          _updateInList(task.copyWith(progress: overallProgress));
        },
      );

      for (final r in results) {
        if (r.success && r.eTag != null) {
          await _persistence.recordPartCompletion(
            id: task.id,
            partNumber: r.partNumber,
            eTag: r.eTag!,
          );
        }
      }

      final failed = results.where((r) => !r.success).toList();
      if (failed.isNotEmpty) {
        await _persistence.markFailed(
          task.id,
          '${failed.length} part(s) failed on resume',
        );
        _updateFromDb();
        return false;
      }

      await _completeAndFinish(task, initResult);
      return false;
    } catch (e, s) {
      _log('[UploadQueue] resume error for task #${task.id}: $e\n$s');
      try {
        await _persistence.markFailed(task.id, 'Resume error: ${e.runtimeType}');
      } catch (_) {}
      _updateFromDb();
      return false;
    }
  }

  Future<void> _completeAndFinish(
    UploadTask task,
    InitUploadResponse initResult,
  ) async {
    final endpoint = task.metadata?['initEndpoint'] as String?;
    final completeEndpoint =
        config.buildCompleteEndpoint?.call(task) ?? endpoint;
    // On resume, the S3 key comes from the persisted task (survives app-kill),
    // falling back to the fresh init response if present.
    final s3Key = task.s3Key ?? initResult.key;
    final completeExtras = <String, dynamic>{
      ...?config.buildCompleteExtraFields?.call(task),
      if (s3Key != null && s3Key.isNotEmpty) 'key': s3Key,
    };
    final etags = await _persistence.getPartETags(task.id);
    // Use original s3UploadId from task (DB persisted), not from fresh init
    final uploadId = task.s3UploadId ?? initResult.s3UploadId ?? '';

    final callback = config.buildCallback?.call(task.copyWith(fileUrl: initResult.fileUrl));
    if (callback != null) {
      final fileUrl = await _engine.completeMultipartAndCallback(
        s3UploadId: uploadId,
        parts: etags,
        callback: callback,
        endpoint: completeEndpoint,
        dbTaskId: task.id,
        completeExtraFields: completeExtras,
      );

      if (fileUrl != null && fileUrl.isNotEmpty) {
        await _persistence.updateFileUrl(id: task.id, fileUrl: fileUrl);
        await _completeTask(task.id);
        _log('[UploadQueue] task #${task.id}: resume chain completed (fileUrl=$fileUrl)');
        _updateFromDb();
        return;
      }
    }

    // Fallback: separate complete + callback
    final fileUrl = await _engine.completeMultipart(
      s3UploadId: uploadId,
      parts: etags,
      endpoint: completeEndpoint,
      extraFields: completeExtras,
    );

    if (fileUrl == null || fileUrl.isEmpty) {
      await _persistence.markFailed(task.id, 'Complete failed on resume');
      _updateFromDb();
      return;
    }

    await _persistence.updateFileUrl(id: task.id, fileUrl: fileUrl);
    final callbackOk = await _sendCallback(task.copyWith(fileUrl: fileUrl));
    if (callbackOk) {
      await _completeTask(task.id);
    } else {
      await _persistence.markFailed(task.id, 'Server callback failed on resume');
    }
    _updateFromDb();
  }

  Future<bool> _sendCallback(UploadTask task) async {
    try {
      final callback = config.buildCallback?.call(task);
      if (callback == null) return true; // no callback configured
      final sent = await _engine.sendCallback(callback, dbTaskId: task.id);
      if (!sent) {
        _log('[UploadQueue] callback failed for task #${task.id}');
      }
      return sent;
    } catch (e) {
      _log('[UploadQueue] callback threw for task #${task.id}: $e');
      return false;
    }
  }

  /// Mark a task completed AND, if configured, delete its source file.
  /// Centralizes completion so every success path frees disk promptly —
  /// essential when uploading multiple 300 MB – 2 GB videos.
  Future<void> _completeTask(int id) async {
    await _persistence.markCompleted(id);
    try {
      final predicate = config.shouldDeleteSourceOnComplete;
      if (predicate == null) return;
      final task = await _persistence.getById(id);
      if (task == null) return;
      if (!predicate(task)) return;
      final file = File(task.filePath);
      if (await file.exists()) {
        await file.delete();
        _log('[UploadQueue] task #$id: deleted source file after upload');
      }
    } catch (e) {
      // Never let cleanup failure surface as an upload failure.
      _log('[UploadQueue] task #$id: source cleanup skipped: $e');
    }
  }

  void _updateInList(UploadTask updated) {
    final index = _tasks.indexWhere((t) => t.id == updated.id);
    if (index >= 0) {
      _tasks[index] = updated;
    } else {
      _tasks.add(updated);
    }
    _emit();
  }

  Future<void> _updateFromDb() async {
    _tasks = await _persistence.getAll();
    _emit();
  }

  void _emit() {
    if (!_disposed && !_controller.isClosed) {
      _controller.add(List.unmodifiable(_tasks));
    }
  }

  void _log(String msg) => config.logger?.call(msg);

  /// Dispose the queue — cancel timers, drain in-flight processing, close DB.
  Future<void> dispose() async {
    _disposed = true;
    _pumpTimer?.cancel();
    _pumpTimer = null;

    // Wait for any in-flight _processNext to finish before closing the DB,
    // otherwise a pending query races against database_closed. Bounded wait
    // so a stuck upload can't block disposal forever.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_processingLock.isLocked && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 25));
    }

    _engine.dispose();
    if (!_controller.isClosed) await _controller.close();
    await _persistence.close();
  }
}

/// Simple async lock to prevent concurrent _processNext execution.
class Lock {
  bool _locked = false;

  bool get isLocked => _locked;

  /// Returns true if the lock was acquired, false if already locked.
  Future<bool> acquire() async {
    if (_locked) return false;
    _locked = true;
    return true;
  }

  void release() {
    _locked = false;
  }
}
