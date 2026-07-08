import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/global/core/services/logger_service.dart';

import '../data/api/s3_upload_api.dart';
import '../data/job_store.dart';
import '../data/models/s3_init_response.dart';
import '../data/models/upload_enums.dart';
import '../data/models/upload_job.dart';
import '../engine/background_upload_engine.dart';
import '../engine/native_upload_bridge.dart';
import '../engine/upload_task_factory.dart';
import 'upload_routes.dart';

/// Orchestrates the full S3 upload flow for every asset type:
///
///   1. init      → ask backend for presigned URL(s) (direct or multipart)
///   2. transfer  → binary PUT bytes to S3 via [BackgroundUploadEngine]
///   3. complete  → (multipart only) send ETags, get final fileUrl
///   4. callback  → notify backend the asset is ready
///
/// The 15 MiB rule is enforced by the backend (it returns `isMultipart`); we
/// simply follow whichever shape it returns. On any post-init failure of a
/// multipart upload we abort the S3 session so no orphan parts are left.
///
/// Jobs live in memory here and are mirrored by background_downloader's own
/// persistent DB (which survives app kill). [resume] rebuilds in-flight jobs.
class UploadService {
  UploadService({
    S3UploadApi api = const S3UploadApi(),
    UploadRoutes routes = const UploadRoutes(),
    BackgroundUploadEngine? engine,
    JobStore? store,
  })  : _api = api,
        _routes = routes,
        _engine = engine ?? BackgroundUploadEngine(),
        _store = store ?? JobStore() {
    _engine.onJobProgress = _onEngineProgress;
    // Wire up before ensureStarted so background completions that fire
    // during native engine init are captured (not silently dropped).
    _engine.onTaskFinal = _onRecoveredTaskFinal;
  }

  final S3UploadApi _api;
  final UploadRoutes _routes;
  final BackgroundUploadEngine _engine;
  final JobStore _store;
  final _factory = const UploadTaskFactory();

  final Map<String, UploadJob> _jobs = {};
  final Set<String> _jobQueue = {};
  bool _isProcessing = false;
  final _controller = StreamController<UploadJob>.broadcast();

  /// Polls the Android native pipeline for completed/failed results.
  Timer? _nativePollTimer;

  /// Set of job IDs recovered on restart that still have in-flight tasks.
  final Set<String> _recovering = {};

  /// Count of completed tasks per recovering job.
  final Map<String, int> _recoveryDone = {};

  /// Total tasks expected per recovering job (direct=1, multipart=N).
  final Map<String, int> _recoveryTotal = {};

  bool _recoveryAttempted = false;

  /// Set to true after [_recoverJobs] finishes replaying buffered completions.
  /// Events arriving afterwards for jobs outside [_recovering] are dropped.
  bool _recoveryReady = false;

  /// Buffers [TaskFinal] completions that arrive before [_recovering] is
  /// populated by [_recoverJobs]. Replayed once recovery state is ready.
  final List<_PendingRecoveryEvent> _pendingRecoveryEvents = [];

  /// Emits a job whenever its state or progress changes.
  Stream<UploadJob> get updates => _controller.stream;

  List<UploadJob> get jobs => _jobs.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  UploadJob? job(String id) => _jobs[id];

  Future<void> ensureStarted() async {
    await _engine.ensureStarted();
    if (!_recoveryAttempted) {
      _recoveryAttempted = true;
      await _recoverJobs();
    }
  }

  /// Scan persisted jobs and reconcile with background_downloader tasks after
  /// an app restart. Jobs whose S3 upload completed while we were dead proceed
  /// to the callback phase. Jobs with running tasks are tracked via
  /// [BackgroundUploadEngine.onTaskFinal].
  Future<void> _recoverJobs() async {
    final jobs = await _store.loadAll();
    if (jobs.isEmpty) return;

    AppLogger.i('UploadService._recoverJobs: ${jobs.length} job(s) to recover');

    // ---- Android: the native WorkManager pipeline owns in-flight jobs ----
    // Reconcile any terminal results the worker wrote while we were dead, then
    // re-attach polling for jobs still running natively. WorkManager keeps
    // uploading queued jobs even while the app is killed, so here we only need
    // to reflect their state back into the UI.
    if (NativeUploadBridge.isSupported) {
      bool hasNativeInFlight = false;
      final nativeResults = await NativeUploadBridge.getCompletedJobs();
      final resultById = {
        for (final r in nativeResults)
          if (r['jobId'] is String) r['jobId'] as String: r,
      };
      for (final job in jobs) {
        if (job.state.isTerminal) continue;
        if (job.metadata['nativeBridge'] != true) continue;
        _jobs[job.id] = job;
        final result = resultById[job.id];
        if (result != null) {
          _reconcileNativeResult(job, result);
        } else {
          // Still uploading (or queued) natively — keep showing progress.
          hasNativeInFlight = true;
          _emit(job);
        }
      }
      if (hasNativeInFlight) _startNativePolling();
      // Fall through so any non-native jobs (shouldn't exist on Android, but be
      // safe) are handled by the background_downloader recovery below.
    }

    final db = FileDownloader().database;

    for (final job in jobs) {
      if (job.state.isTerminal) continue;
      if (_jobs.containsKey(job.id) && job.metadata['nativeBridge'] == true) {
        // Already handled by the native reconciliation above.
        continue;
      }
      _jobs[job.id] = job;

      // Fetch all background_downloader task records for this job.
      final group = UploadTaskFactory.groupFor(job.id);
      final records = await db.allRecords(group: group);

      if (records.isEmpty) {
        // No engine tasks — either never started, or already finished and the
        // terminal state save didn't persist before kill.
        if (job.state == UploadJobState.callback) {
          // Upload + complete steps already ran; just re-run idempotent callback.
          AppLogger.i('UploadService._recoverJobs: ${job.id} has no tasks but state=callback, re-running callback');
          _recoverRunCallback(job);
          continue;
        }
        if (!File(job.filePath).existsSync()) {
          AppLogger.w('UploadService._recoverJobs: ${job.id} source file missing');
          _fail(job, 'Source file not found');
          continue;
        }
        // Never got to the transfer phase — start from scratch.
        AppLogger.i('UploadService._recoverJobs: ${job.id} has no tasks, re-enqueueing');
        _jobQueue.add(job.id);
        _dequeue();
        continue;
      }

      // Separate into transfer (UploadTask) and API (DownloadTask) records.
      final apiRecords =
          records.where((r) => r.task is DataTask).toList();
      final transferRecords =
          records.where((r) => r.task is UploadTask).toList();

      // ---- Transfer phase ----
      if (transferRecords.isNotEmpty) {
        final transferAllComplete =
            transferRecords.every((r) => r.status == TaskStatus.complete);

        if (!transferAllComplete) {
          final transferAnyFailed =
              transferRecords.any((r) => r.status == TaskStatus.failed);

          if (transferAnyFailed) {
            // Check whether all failures are expired presigned URLs (HTTP 403).
            final failed =
                transferRecords.where((r) => r.status == TaskStatus.failed);
            final allExpired = failed.isNotEmpty &&
                failed.every((r) =>
                    r.exception is TaskHttpException &&
                    (r.exception as TaskHttpException).httpResponseCode == 403);
            if (allExpired) {
              AppLogger.w('UploadService._recoverJobs: ${job.id} tasks expired, re-initing');
              await _engine.cancelGroup(group);
              _jobQueue.add(job.id);
              _dequeue();
            } else {
              // Non-HTTP failure (process killed, cancellation, etc.).
              AppLogger.w('UploadService._recoverJobs: ${job.id} transfer tasks failed, re-initing');
              await _engine.cancelGroup(group);
              _jobQueue.add(job.id);
              _dequeue();
            }
          } else {
            // Tasks still pending/running — native service (Android/iOS) is
            // actively working on them.  Track via _recovering so that
            // _onRecoveredTaskFinal (now wired in the constructor) picks up
            // completion events and drives the job forward.
            final allPendingTasks = transferRecords.length + apiRecords.length;
            AppLogger.i('UploadService._recoverJobs: ${job.id} has $allPendingTasks pending task(s), tracking for recovery');
            _recovering.add(job.id);
            _recoveryTotal[job.id] = allPendingTasks;
            _recoveryDone[job.id] = records
                .where((r) => r.status.isFinalState)
                .length;
            _emit(job);
          }
          continue;
        }
        // Transfer is all complete. Fall through to API phase.
      }

      // ---- API phase ----
      if (apiRecords.isEmpty) {
        // Transfer done but API tasks never created — create them now.
        AppLogger.i('UploadService._recoverJobs: ${job.id} transfer done, creating API tasks');
        if (job.isMultipart) {
          final ok = await _recoverComplete(job);
          if (!ok) {
            AppLogger.w('UploadService._recoverJobs: ${job.id} complete failed during recovery, re-initing');
            await _engine.cancelGroup(group);
            _jobQueue.add(job.id);
            _dequeue();
            continue;
          }
        }
        _recoverRunCallback(job);
        continue;
      }

      // API records exist.
      final apiAllComplete =
          apiRecords.every((r) => r.status == TaskStatus.complete);
      final apiAnyFailed =
          apiRecords.any((r) => r.status == TaskStatus.failed);

      if (apiAllComplete) {
        // All phases complete — job is done.
        AppLogger.i('UploadService._recoverJobs: ${job.id} all API tasks complete');
        _setState(job, UploadJobState.completed);
        continue;
      }

      if (apiAnyFailed) {
        final failed = apiRecords.where((r) => r.status == TaskStatus.failed);
        final all401 = failed.isNotEmpty &&
            failed.every((r) =>
                r.exception is TaskHttpException &&
                (r.exception as TaskHttpException).httpResponseCode == 401);
        if (all401) {
          // Token expired. Recreate API tasks.
          AppLogger.w('UploadService._recoverJobs: ${job.id} API tasks expired (401), re-creating');
          await _engine.cancelGroup(group);
          if (job.isMultipart) {
            final ok = await _recoverComplete(job);
            if (!ok) {
              _setState(job, UploadJobState.failed);
              continue;
            }
          }
          _recoverRunCallback(job);
        } else {
          AppLogger.w('UploadService._recoverJobs: ${job.id} API tasks failed');
          _setState(job, UploadJobState.failed);
        }
        continue;
      }

      // API tasks still pending — re-attach.
      AppLogger.i('UploadService._recoverJobs: ${job.id} ${apiRecords.length} API task(s) pending, re-attaching');
      _recovering.add(job.id);
      _recoveryTotal[job.id] = apiRecords.length;
      _recoveryDone[job.id] =
          apiRecords.where((r) => r.status.isFinalState).length;
      _emit(job);
    }

    // Replay any completions that the engine fired before _recovering was ready.
    _replayPendingRecoveryEvents();
    _recoveryReady = true;

    // Purge stale terminal records from the store.
    unawaited(_purgeTerminalStoreRecords());
  }

  /// Complete the multipart S3 session during recovery using a native API task.
  Future<bool> _recoverComplete(UploadJob job) async {
    if (!job.isMultipart) return true;
    if (job.key == null || job.s3UploadId == null) {
      AppLogger.e('UploadService._recoverComplete ${job.id}: missing key/uploadId');
      return false;
    }
    try {
      final route = _routes.forJob(job);
      final body = jsonEncode({
        'key': job.key,
        'uploadId': job.s3UploadId,
        'parts': job.etagPayload,
      });
      final task = _factory.completeTask(
        job: job,
        url: route.completeEndpoint,
        body: body,
        token: AuthController.accessToken ?? '',
      );
      final result = await _engine.enqueueApiCall(task);
      if (!result.success) {
        AppLogger.e('UploadService._recoverComplete ${job.id}: ${result.error}');
        return false;
      }
      job.fileUrl = result.fileUrl;
      unawaited(_store.save(job));
      return true;
    } catch (e) {
      AppLogger.e('UploadService._recoverComplete ${job.id} error: $e');
      return false;
    }
  }

  /// Called by [BackgroundUploadEngine] when any task from a recovered job
  /// reaches a final state (complete or failed).
  /// Replays any [TaskFinal] events that arrived while [_recovering] was
  /// empty so they are not silently lost.
  void _replayPendingRecoveryEvents() {
    if (_pendingRecoveryEvents.isEmpty) return;
    final events = List<_PendingRecoveryEvent>.of(_pendingRecoveryEvents);
    _pendingRecoveryEvents.clear();
    for (final e in events) {
      if (!_recovering.contains(e.jobId)) continue;
      _onRecoveredTaskFinal(
        e.jobId,
        e.success,
        e.eTag,
        e.urlExpired,
        e.fileUrl,
        e.isApi,
        e.responseBody,
        e.statusCode,
      );
    }
  }

  void _onRecoveredTaskFinal(
    String jobId,
    bool success,
    String? eTag,
    bool urlExpired,
    String? fileUrl,
    bool isApi,
    String? responseBody,
    int? statusCode,
  ) {
    if (!_recovering.contains(jobId)) {
      if (_recoveryReady) return; // recovery finished, job has already been handled
      // Background task fired before _recoverJobs populated the set
      // (e.g. during _engine.ensureStarted). Buffer for replay.
      _pendingRecoveryEvents.add(_PendingRecoveryEvent(
        jobId: jobId,
        success: success,
        eTag: eTag,
        urlExpired: urlExpired,
        fileUrl: fileUrl,
        isApi: isApi,
        responseBody: responseBody,
        statusCode: statusCode,
      ));
      return;
    }

    if (!success && urlExpired) {
      if (isApi) {
        // API task token expired (401) — recreate the API tasks.
        _recovering.remove(jobId);
        _recoveryDone.remove(jobId);
        _recoveryTotal.remove(jobId);
        final job = _jobs[jobId];
        if (job != null) {
          AppLogger.w('UploadService._onRecoveredTaskFinal: ${job.id} API token expired, recreating tasks');
          unawaited(_recoverAndRequeue(job));
        }
      } else {
        // Transfer presigned URL expired — re-init with fresh URLs.
        _recovering.remove(jobId);
        _recoveryDone.remove(jobId);
        _recoveryTotal.remove(jobId);
        final job = _jobs[jobId];
        if (job != null) {
          AppLogger.w('UploadService._onRecoveredTaskFinal: ${job.id} URL expired, re-initing');
          unawaited(_recoverAndRequeue(job));
        }
      }
      return;
    }

    final done = (_recoveryDone[jobId] ?? 0) + 1;
    _recoveryDone[jobId] = done;
    final total = _recoveryTotal[jobId] ?? 0;

    if (!success) {
      // A genuine task failed → whole job fails.
      _recovering.remove(jobId);
      _recoveryDone.remove(jobId);
      _recoveryTotal.remove(jobId);
      // For HTTP 409 (callback idempotency), treat as success.
      if (statusCode == 409) {
        final job = _jobs[jobId];
        if (job != null) _setState(job, UploadJobState.completed);
      } else {
        final job = _jobs[jobId];
        if (job != null) _setState(job, UploadJobState.failed);
      }
      return;
    }

    // Store fileUrl when a complete API task succeeds.
    if (isApi && fileUrl != null) {
      _jobs[jobId]?.fileUrl = fileUrl;
    }

    if (done >= total) {
      // All tracked tasks completed. Run complete (if multipart) and callback.
      // Both are idempotent — safe to re-run even if already done.
      _recovering.remove(jobId);
      _recoveryDone.remove(jobId);
      _recoveryTotal.remove(jobId);
      final job = _jobs[jobId];
      if (job != null) {
        if (job.isMultipart) {
          unawaited(_recoverAndCallback(job));
        } else {
          unawaited(_runCallback(job));
        }
      }
    }
  }

  /// Re-init and re-enqueue a job whose presigned URLs expired during recovery.
  Future<void> _recoverAndRequeue(UploadJob job) async {
    try {
      await _engine.cancelGroup(UploadTaskFactory.groupFor(job.id));
    } catch (_) {}
    _jobQueue.add(job.id);
    _dequeue();
  }

  /// Run the callback step for a recovered job whose upload has completed.
  void _recoverRunCallback(UploadJob job) {
    _setState(job, UploadJobState.callback);
    unawaited(_runCallback(job));
  }

  /// Run complete (if multipart) then callback for a recovered job where
  /// all transfer tasks finished. Both steps are idempotent so re-running
  /// them when already done is harmless.
  Future<void> _recoverAndCallback(UploadJob job) async {
    if (job.isMultipart) {
      final ok = await _recoverComplete(job);
      if (!ok) {
        _setState(job, UploadJobState.failed);
        return;
      }
    }
    await _runCallback(job);
  }

  Future<void> _runCallback(UploadJob job) async {
    try {
      final route = _routes.forJob(job);
      final body = jsonEncode(route.callbackBody(job));
      final task = _factory.callbackTask(
        job: job,
        url: route.callbackEndpoint,
        body: body,
        token: AuthController.accessToken ?? '',
        method: route.callbackMethod,
      );
      final result = await _engine.enqueueApiCall(task);
      // HTTP 409 (idempotent replay) is treated as success.
      if (!result.success && result.statusCode != 409) {
        AppLogger.e(
            'UploadService._runCallback ${job.id} failed: ${result.error}');
        _setState(job, UploadJobState.failed);
      } else {
        _setState(job, UploadJobState.completed);
      }
    } catch (e) {
      AppLogger.e('UploadService._runCallback error: $e');
      _setState(job, UploadJobState.failed);
    }
  }

  /// Combined course creation flow — single init call for thumbnail + optional
  /// intro video, uploads both, completes multipart if needed, then creates
  /// the course via a single POST to `/course`.
  ///
  /// Returns the thumbnail job (which carries the final state). On failure,
  /// returns the failed job with `job.error` set.
  Future<UploadJob> createCourse({
    required String id,
    required String thumbnailPath,
    String? videoPath,
    required int thumbnailFileSize,
    int? videoFileSize,
    required String title,
    required String shortDescription,
    required String description,
    required String requirements,
    required String language,
    required String level,
    required String type,
    required double price,
    Map<String, dynamic> extraMetadata = const {},
  }) async {
    await ensureStarted();

    final thumbName = _fileName(thumbnailPath);
    final thumbType = _imageType(thumbName);

    // ── Step 1: combined init ─────────────────────────────────────────
    final initBody = <String, dynamic>{
      'thumbnailFilename': thumbName,
      'thumbnailContentType': thumbType,
      'thumbnailFileSize': thumbnailFileSize,
    };
    if (videoPath != null && videoFileSize != null) {
      final vidName = _fileName(videoPath);
      initBody.addAll({
        'videoFilename': vidName,
        'videoContentType': _videoType(vidName),
        'videoFileSize': videoFileSize,
      });
    }

    AppLogger.i('UploadService.createCourse init body=$initBody');
    final init = await _api.initCourseAssets(body: initBody);
    if (init == null) {
      return _createFailedJob(id, thumbnailPath, title, 'Init failed');
    }

    // ── Step 2: upload thumbnail ──────────────────────────────────────
    final thumbJob = UploadJob(
      id: '${id}_thumb',
      filePath: thumbnailPath,
      type: UploadAssetType.courseThumb,
      title: 'Course thumbnail: $title',
      fileSize: thumbnailFileSize,
      metadata: {
        'courseTitle': title,
        'shortDescription': shortDescription,
        'description': description,
        'requirements': requirements,
        'language': language,
        'level': level,
        'type': type,
        'price': price,
        ...extraMetadata,
      },
    );
    _jobs[thumbJob.id] = thumbJob;

    final thumbInit = init.thumbnail;
    if (thumbInit == null) {
      return _failJob(thumbJob, 'Missing thumbnail data in init response');
    }
    _applyInit(thumbJob, thumbInit);
    _setState(thumbJob, UploadJobState.uploading);

    final thumbResult = await _engine.uploadDirect(thumbJob);
    if (!thumbResult.success) {
      return _failJob(thumbJob, thumbResult.error ?? 'Thumbnail upload failed');
    }

    // ── Step 3: upload intro video (if present) ───────────────────────
    String? videoFileUrl;
    if (videoPath != null && videoFileSize != null) {
      final videoInit = init.video;
      if (videoInit == null) {
        return _failJob(thumbJob, 'Missing video data in init response');
      }

      final videoJob = UploadJob(
        id: '${id}_video',
        filePath: videoPath,
        type: UploadAssetType.courseIntro,
        title: 'Course intro: $title',
        fileSize: videoFileSize,
      );
      _jobs[videoJob.id] = videoJob;
      _applyInit(videoJob, videoInit);
      _setState(videoJob, UploadJobState.uploading);

      if (videoJob.isMultipart) {
        final results = await _engine.uploadParts(videoJob);
        for (final r in results) {
          if (r.success && r.partNumber != null) {
            final part =
                videoJob.parts.firstWhere((p) => p.partNumber == r.partNumber);
            part.eTag = r.eTag;
          }
        }
        final allDone = videoJob.parts.every((p) => p.done);
        if (!allDone) {
          await _abort(videoJob, _routes.forJob(videoJob));
          return _failJob(thumbJob, 'One or more video parts failed');
        }

        _setState(videoJob, UploadJobState.completing);
        final complete = await _api.complete(
          endpoint: Urls.uploadCompleteUrl,
          key: videoJob.key!,
          s3UploadId: videoJob.s3UploadId!,
          parts: videoJob.etagPayload,
        );
        if (!complete.isSuccess) {
          await _abort(videoJob, _routes.forJob(videoJob));
          return _failJob(thumbJob, complete.errorMessage ?? 'Video complete failed');
        }
        videoJob.fileUrl = complete.fileUrl;
      } else {
        final result = await _engine.uploadDirect(videoJob);
        if (!result.success) {
          return _failJob(thumbJob, result.error ?? 'Video upload failed');
        }
      }

      videoFileUrl = videoJob.fileUrl;
      _setState(videoJob, UploadJobState.completed);
    }

    // ── Step 4: course creation callback ──────────────────────────────
    _setState(thumbJob, UploadJobState.callback);
    final ok = await _api.callback(
      endpoint: Urls.createCourseUrl,
      method: 'POST',
      body: {
        'title': title,
        'description': description,
        'shortDescription': shortDescription,
        'requirements': requirements,
        'thumbnailUrl': thumbJob.fileUrl,
        'introVideoUrl': ?videoFileUrl,
        'language': language,
        'level': level.toUpperCase(),
        'type': type.toUpperCase(),
        'price': price,
      },
      idempotencyKey: '${id}_course',
    );
    if (!ok) {
      return _failJob(thumbJob, 'Course creation failed');
    }

    _setState(thumbJob, UploadJobState.completed);
    return thumbJob;
  }

  /// Upload thumbnail and/or intro video for an existing course.
  /// Combined init → upload → (optional multipart complete) → return URLs.
  /// Does NOT call any callback/registration endpoint; the caller is
  /// responsible for the PUT /course with the returned URLs.
  /// Returns `{'thumbnailFileUrl': ..., 'videoFileUrl': ...}` on success,
  /// or `null` on failure.
  Future<Map<String, String?>?> uploadCourseAssets({
    required String id,
    String? thumbnailPath,
    String? videoPath,
    int? thumbnailFileSize,
    int? videoFileSize,
  }) async {
    if (thumbnailPath == null && videoPath == null) return {};
    await ensureStarted();

    // Build init body — backend always requires thumbnail fields.
    final initBody = <String, dynamic>{};
    if (thumbnailPath != null && thumbnailFileSize != null) {
      final thumbName = _fileName(thumbnailPath);
      initBody.addAll({
        'thumbnailFilename': thumbName,
        'thumbnailContentType': _imageType(thumbName),
        'thumbnailFileSize': thumbnailFileSize,
      });
    } else {
      initBody.addAll({
        'thumbnailFilename': 'keep.jpg',
        'thumbnailContentType': 'image/jpeg',
        'thumbnailFileSize': 0,
      });
    }
    if (videoPath != null && videoFileSize != null) {
      final vidName = _fileName(videoPath);
      initBody.addAll({
        'videoFilename': vidName,
        'videoContentType': _videoType(vidName),
        'videoFileSize': videoFileSize,
      });
    }

    final init = await _api.initCourseAssets(body: initBody);
    if (init == null) return null;

    String? thumbnailUrl;
    String? videoUrl;

    if (thumbnailPath != null && thumbnailFileSize != null) {
      final thumbInit = init.thumbnail;
      if (thumbInit == null) return null;

      final thumbJob = UploadJob(
        id: '${id}_thumb',
        filePath: thumbnailPath,
        type: UploadAssetType.courseThumb,
        title: 'Course thumbnail',
        fileSize: thumbnailFileSize,
      );
      _applyInit(thumbJob, thumbInit);

      final result = await _engine.uploadDirect(thumbJob);
      if (!result.success) return null;
      thumbnailUrl = thumbJob.fileUrl;
    }

    if (videoPath != null && videoFileSize != null) {
      final videoInit = init.video;
      if (videoInit == null) return null;

      final videoJob = UploadJob(
        id: '${id}_video',
        filePath: videoPath,
        type: UploadAssetType.courseIntro,
        title: 'Course intro',
        fileSize: videoFileSize,
      );
      _applyInit(videoJob, videoInit);

      if (videoJob.isMultipart) {
        final results = await _engine.uploadParts(videoJob);
        for (final r in results) {
          if (r.success && r.partNumber != null) {
            final part = videoJob.parts
                .firstWhere((p) => p.partNumber == r.partNumber);
            part.eTag = r.eTag;
          }
        }
        final allDone = videoJob.parts.every((p) => p.done);
        if (!allDone) {
          await _abort(videoJob, _routes.forJob(videoJob));
          return null;
        }

        final complete = await _api.complete(
          endpoint: Urls.uploadCompleteUrl,
          key: videoJob.key!,
          s3UploadId: videoJob.s3UploadId!,
          parts: videoJob.etagPayload,
        );
        if (!complete.isSuccess) {
          await _abort(videoJob, _routes.forJob(videoJob));
          return null;
        }
        videoJob.fileUrl = complete.fileUrl;
      } else {
        final result = await _engine.uploadDirect(videoJob);
        if (!result.success) return null;
      }
      videoUrl = videoJob.fileUrl;
    }

    return {
      'thumbnailFileUrl': thumbnailUrl,
      'videoFileUrl': videoUrl,
    };
  }

  /// Enqueue a new upload. Returns the created job immediately; processing runs
  /// serially (FIFO) — only one job at a time. Progress is reported via [updates].
  Future<UploadJob> enqueue({
    required String id,
    required String filePath,
    required UploadAssetType type,
    required String title,
    required int fileSize,
    Map<String, dynamic> metadata = const {},
  }) async {
    final job = UploadJob(
      id: id,
      filePath: filePath,
      type: type,
      title: title,
      fileSize: fileSize,
      metadata: Map<String, dynamic>.from(metadata),
    );
    _jobs[id] = job;
    _jobQueue.add(id);
    unawaited(_store.save(job));
    _emit(job);
    _dequeue();
    return job;
  }

  /// Picks the next queued job and processes it serially.
  void _dequeue() {
    if (_isProcessing) return;
    if (_jobQueue.isEmpty) return;

    _isProcessing = true;
    final nextId = _jobQueue.first;
    _jobQueue.remove(nextId);
    final job = _jobs[nextId];
    if (job == null) {
      _isProcessing = false;
      _dequeue();
      return;
    }
    unawaited(_runJob(job));
  }

  Future<void> _runJob(UploadJob job) async {
    try {
      await _process(job);
    } finally {
      _isProcessing = false;
      _dequeue();
    }
  }

  Future<void> _process(UploadJob job) async {
    try {
      AppLogger.i('UploadService._process ${job.id} starting type=${job.type.wire}');

      if (!File(job.filePath).existsSync()) {
        AppLogger.e('UploadService._process ${job.id} source file missing: ${job.filePath}');
        return _fail(job, 'Source file not found');
      }

      await ensureStarted();
      final route = _routes.forJob(job);

      // ---- Android: run the whole pipeline natively (survives app kill) ----
      if (NativeUploadBridge.isSupported) {
        await _processAndroidNative(job, route);
        return;
      }

      // ---- Step 1: init ----
      _setState(job, UploadJobState.uploading);
      AppLogger.i('UploadService._process ${job.id} init endpoint=${route.initEndpoint} body=${route.initBody}');
      final init = await _api.init(
        endpoint: route.initEndpoint,
        body: route.initBody,
        courseAssetKey: route.courseAssetKey,
      );
      if (init == null) {
        AppLogger.e('UploadService._process ${job.id} init returned null');
        return _fail(job, 'Failed to initialize upload');
      }
      _applyInit(job, init);

      // ---- Step 2: transfer ----
      if (job.isMultipart) {
        final results = await _engine.uploadParts(job);
        for (final r in results) {
          if (r.success && r.partNumber != null) {
            final part =
                job.parts.firstWhere((p) => p.partNumber == r.partNumber);
            part.eTag = r.eTag;
          }
        }

        // Retry any parts that failed due to presigned URL expiry.
        final expired = results.where((r) => r.urlExpired).toList();
        if (expired.isNotEmpty) {
          AppLogger.w('UploadService._process ${job.id}: ${expired.length} part(s) URL expired, re-initing');
          final newInit = await _api.init(
            endpoint: route.initEndpoint,
            body: route.initBody,
            courseAssetKey: route.courseAssetKey,
          );
          if (newInit != null) {
            for (final r in expired) {
              if (r.partNumber == null) continue;
              final part = job.parts.firstWhere(
                (p) => p.partNumber == r.partNumber,
              );
              // Find matching fresh part URL from new init.
              final fresh = newInit.parts.where(
                (p) => p.partNumber == r.partNumber,
              ).firstOrNull;
              if (fresh != null) {
                part.uploadUrl = fresh.uploadUrl;
                part.eTag = null;
              }
            }
            // Re-upload only the previously-expired parts.
            final retryResults = await _engine.uploadParts(job);
            for (final r in retryResults) {
              if (r.success && r.partNumber != null) {
                final part = job.parts.firstWhere(
                  (p) => p.partNumber == r.partNumber,
                );
                part.eTag = r.eTag;
              }
            }
          }
        }

        final allDone = job.parts.every((p) => p.done);
        if (!allDone) {
          await _abort(job, route);
          return _fail(job, 'One or more parts failed to upload');
        }

        // ---- Step 3: complete (multipart only) — native task ----
        _setState(job, UploadJobState.completing);
        final completeBody = jsonEncode({
          'key': job.key,
          'uploadId': job.s3UploadId,
          'parts': job.etagPayload,
        });
        var completeTask = _factory.completeTask(
          job: job,
          url: route.completeEndpoint,
          body: completeBody,
          token: AuthController.accessToken ?? '',
        );
        var completeResult = await _engine.enqueueApiCall(completeTask);
        // Retry once if token expired (401).
        if (!completeResult.success && completeResult.urlExpired) {
          AppLogger.w('UploadService._process ${job.id} complete 401, retrying with fresh token');
          completeTask = _factory.completeTask(
            job: job,
            url: route.completeEndpoint,
            body: completeBody,
            token: AuthController.accessToken ?? '',
          );
          completeResult = await _engine.enqueueApiCall(completeTask);
        }
        if (!completeResult.success) {
          await _abort(job, route);
          return _fail(job, completeResult.error ?? 'Complete failed');
        }
        job.fileUrl = completeResult.fileUrl;
      } else {
        // Direct upload: object is already stored at `key` on success; the
        // fileUrl came from init. No S3 complete call needed.
        AppLogger.i('UploadService._process ${job.id} direct upload starting');
        var result = await _engine.uploadDirect(job);
        // Retry once if presigned URL expired.
        if (!result.success && result.urlExpired) {
          AppLogger.w('UploadService._process ${job.id} URL expired, re-initing and retrying');
          final newInit = await _api.init(
            endpoint: route.initEndpoint,
            body: route.initBody,
            courseAssetKey: route.courseAssetKey,
          );
          if (newInit != null) {
            job.directUploadUrl = newInit.uploadUrl;
            job.fileUrl = newInit.fileUrl;
            result = await _engine.uploadDirect(job);
          }
        }
        if (!result.success) {
          AppLogger.e('UploadService._process ${job.id} direct upload failed: ${result.error}');
          return _fail(job, result.error ?? 'Direct upload failed');
        }
        AppLogger.i('UploadService._process ${job.id} direct upload succeeded');
      }

      // ---- Step 4: callback — native task ----
      _setState(job, UploadJobState.callback);
      final callbackBody = jsonEncode(route.callbackBody(job));
      AppLogger.i('UploadService._process ${job.id} callback endpoint=${route.callbackEndpoint} method=${route.callbackMethod} body=$callbackBody');
      var callbackTask = _factory.callbackTask(
        job: job,
        url: route.callbackEndpoint,
        body: callbackBody,
        token: AuthController.accessToken ?? '',
        method: route.callbackMethod,
      );
      var callbackResult = await _engine.enqueueApiCall(callbackTask);
      // Retry once if token expired (401).
      if (!callbackResult.success && callbackResult.urlExpired) {
        AppLogger.w('UploadService._process ${job.id} callback 401, retrying with fresh token');
        callbackTask = _factory.callbackTask(
          job: job,
          url: route.callbackEndpoint,
          body: callbackBody,
          token: AuthController.accessToken ?? '',
          method: route.callbackMethod,
        );
        callbackResult = await _engine.enqueueApiCall(callbackTask);
      }
      // HTTP 409 (idempotent replay) is treated as success.
      if (!callbackResult.success && callbackResult.statusCode != 409) {
        AppLogger.e('UploadService._process ${job.id} callback failed: ${callbackResult.error}');
        return _fail(job, callbackResult.error ?? 'Server callback failed');
      }

      _setState(job, UploadJobState.completed);
    } catch (e, st) {
      AppLogger.e('UploadService._process ${job.id} error: $e\n$st');
      _fail(job, e.toString());
    }
  }

  /// Android path: hand the entire job (init → transfer → complete → callback)
  /// to the native WorkManager pipeline so it completes even if the app is
  /// killed. We build the callback body with a `__FILE_URL__` placeholder that
  /// the worker fills in once it knows the final S3 url.
  Future<void> _processAndroidNative(UploadJob job, UploadRoute route) async {
    // Keep native auth in sync so the worker can call our backend (and refresh
    // the token itself) with no Dart isolate alive.
    await NativeUploadBridge.syncTokens(
      accessToken: AuthController.accessToken ?? '',
      refreshToken: AuthController.userModel?.refreshToken ?? '',
      refreshUrl: Urls.refreshTokenUrl,
    );

    // Build the callback body template, substituting the final-url placeholder
    // for whichever url field this asset type uses.
    final callbackMap = route.callbackBody(job);
    const urlKeys = ['fileUrl', 'thumbnailUrl', 'videoUrl', 'introVideoUrl'];
    var placed = false;
    for (final k in urlKeys) {
      if (callbackMap.containsKey(k)) {
        callbackMap[k] = '__FILE_URL__';
        placed = true;
      }
    }
    if (!placed) callbackMap['fileUrl'] = '__FILE_URL__';

    final jobData = <String, dynamic>{
      'jobId': job.id,
      'filePath': job.filePath,
      'fileSize': job.fileSize,
      'title': job.title,
      'initUrl': route.initEndpoint,
      'completeUrl': route.completeEndpoint,
      'abortUrl': route.abortEndpoint,
      'callbackUrl': route.callbackEndpoint,
      'callbackMethod': route.callbackMethod,
      'initBody': jsonEncode(route.initBody),
      'courseAssetKey': route.courseAssetKey,
      'callbackBodyTemplate': jsonEncode(callbackMap),
    };

    final started = await NativeUploadBridge.enqueueUpload(jobData);
    if (!started) {
      return _fail(job, 'Failed to start native upload');
    }

    job.metadata['nativeBridge'] = true;
    _setState(job, UploadJobState.uploading);
    unawaited(_store.save(job));
    _startNativePolling();
  }

  /// Periodically poll the native pipeline for terminal results and reconcile.
  void _startNativePolling() {
    _nativePollTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollNativeResults(),
    );
  }

  Future<void> _pollNativeResults() async {
    if (!NativeUploadBridge.isSupported) return;
    final results = await NativeUploadBridge.getCompletedJobs();
    for (final r in results) {
      final jobId = r['jobId'] as String?;
      if (jobId == null) continue;
      final job = _jobs[jobId];
      if (job == null) {
        // Result for a job we no longer track — clear it so it doesn't pile up.
        unawaited(NativeUploadBridge.clearResult(jobId));
        continue;
      }
      _reconcileNativeResult(job, r);
    }

    // Stop polling once no native jobs remain in flight.
    final hasNative = _jobs.values.any(
      (j) => j.metadata['nativeBridge'] == true && !j.state.isTerminal,
    );
    if (!hasNative) {
      _nativePollTimer?.cancel();
      _nativePollTimer = null;
    }
  }

  void _reconcileNativeResult(UploadJob job, Map<String, dynamic> result) {
    final status = result['status'] as String? ?? '';
    final fileUrl = result['fileUrl'] as String?;
    final error = result['error'] as String?;

    if (status == 'completed') {
      if (fileUrl != null && fileUrl.isNotEmpty) job.fileUrl = fileUrl;
      _setState(job, UploadJobState.completed);
      unawaited(NativeUploadBridge.clearResult(job.id));
    } else {
      // 'failed' — the native worker exhausted its retries.
      unawaited(NativeUploadBridge.clearResult(job.id));
      _fail(job, error ?? 'Native upload failed');
    }
  }

  void _applyInit(UploadJob job, S3InitResponse init) {
    job.isMultipart = init.isMultipart;
    job.key = init.key;
    job.fileUrl = init.fileUrl;
    job.s3UploadId = init.s3UploadId;

    if (init.isMultipart) {
      job.parts.clear();
      const partSize = 5 * 1024 * 1024;
      final serverTotal = init.parts.length;
      final needed = serverTotal > 0
          ? (job.fileSize + partSize - 1) ~/ partSize
          : 0;
      final total = needed < serverTotal ? needed : serverTotal;
      for (var i = 0; i < total; i++) {
        final p = init.parts[i];
        final start = i * partSize;
        final isLast = i == total - 1;
        final end = isLast ? -1 : (start + partSize - 1);
        job.parts.add(UploadPart(
          partNumber: p.partNumber,
          rangeStart: start,
          rangeEnd: end,
          uploadUrl: p.uploadUrl,
        ));
      }
    } else {
      job.directUploadUrl = init.uploadUrl;
    }
    job.touch();
    unawaited(_store.save(job));
    _emit(job);
  }

  Future<void> _abort(UploadJob job, UploadRoute route) async {
    if (job.key == null || job.s3UploadId == null) return;
    try {
      await _api.abort(
        endpoint: route.abortEndpoint,
        key: job.key!,
        s3UploadId: job.s3UploadId!,
      );
    } catch (e) {
      AppLogger.e('UploadService._abort ${job.id} error: $e');
    }
  }

  /// Retry a failed job from scratch. Goes through the serial queue.
  Future<void> retry(String id) async {
    final job = _jobs[id];
    if (job == null || !job.state.isTerminal) return;
    job.error = null;
    job.progress = 0.0;
    job.key = null;
    job.s3UploadId = null;
    job.fileUrl = null;
    job.directUploadUrl = null;
    job.isMultipart = false;
    job.parts.clear();
    job.metadata.remove('nativeBridge');
    _setState(job, UploadJobState.pending);
    _jobQueue.add(id);
    _dequeue();
  }

  Future<void> cancel(String id) async {
    _jobQueue.remove(id);
    final job = _jobs[id];
    if (job == null) return;
    await _engine.cancelJob(id);
    final route = _routes.forJob(job);
    await _abort(job, route);
    _setState(job, UploadJobState.cancelled);
  }

  Future<void> remove(String id) async {
    final job = _jobs[id];
    if (job != null) _hardRemove(job);
    await _store.delete(id);
  }

  void _onEngineProgress(String jobId, double progress) {
    final job = _jobs[jobId];
    if (job == null) return;
    // Reserve the last 5% for complete+callback so the bar doesn't sit at 100%
    // while finalizing.
    job.progress = job.isMultipart ? progress * 0.95 : progress;
    job.touch();
    _emit(job);
  }

  void _setState(UploadJob job, UploadJobState state) {
    // Prevent overwriting a terminal state (e.g. cancel vs fail race).
    if (job.state.isTerminal && state != UploadJobState.pending) return;
    job.state = state;
    if (state == UploadJobState.completed) {
      job.progress = 1.0;
    } else if (state == UploadJobState.callback && job.progress < 0.99) {
      job.progress = 0.99;
    } else if (state == UploadJobState.completing && job.progress < 0.95) {
      job.progress = 0.95;
    }
    job.touch();
    if (state == UploadJobState.failed) {
      // Erase failed jobs entirely — user does not want to see or retry them.
      unawaited(_store.delete(job.id));
      _jobs.remove(job.id);
    } else {
      unawaited(_store.save(job));
    }
    if (state.isTerminal) {
      unawaited(_cleanupJob(job));
    }
    _emit(job);
  }

  void _fail(UploadJob job, String message) {
    job.error = message;
    _setState(job, UploadJobState.failed);
    // Remove from everywhere on the Flutter side — no lingering state.
    _hardRemove(job);
  }

  void _hardRemove(UploadJob job) {
    _jobQueue.remove(job.id);
    _jobs.remove(job.id);
    unawaited(_store.delete(job.id));
    unawaited(_cleanupJob(job));
  }

  UploadJob _failJob(UploadJob job, String message) {
    _fail(job, message);
    return job;
  }

  UploadJob _createFailedJob(
    String id,
    String filePath,
    String title,
    String message,
  ) {
    final job = UploadJob(
      id: id,
      filePath: filePath,
      type: UploadAssetType.course,
      title: title,
      fileSize: 0,
      state: UploadJobState.failed,
      error: message,
    );
    _jobs[job.id] = job;
    _emit(job);
    return job;
  }

  void _emit(UploadJob job) {
    if (!_controller.isClosed) _controller.add(job);
  }

  String _fileName(String path) =>
      path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

  String _videoType(String filename) {
    switch (filename.split('.').last.toLowerCase()) {
      case 'mov':
      case 'quicktime':
        return 'video/quicktime';
      case 'mkv':
      case 'x-matroska':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  String _imageType(String filename) {
    switch (filename.split('.').last.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'avif':
        return 'image/avif';
      default:
        return 'image/jpeg';
    }
  }

  /// Remove background_downloader tasks for a terminal job so its SQLite DB
  /// doesn't grow unboundedly. Safe to call multiple times.
  Future<void> _cleanupJob(UploadJob job) async {
    try {
      final group = UploadTaskFactory.groupFor(job.id);
      await _engine.cancelGroup(group);
      await _engine.clearProgress(job.id);
    } catch (e) {
      AppLogger.w('UploadService._cleanupJob ${job.id}: $e');
    }
  }

  /// Purge all terminal job records from the store on startup.
  Future<void> _purgeTerminalStoreRecords() async {
    try {
      await _store.deleteAllTerminal();
    } catch (e) {
      AppLogger.w('UploadService._purgeTerminalStoreRecords: $e');
    }
  }

  Future<void> dispose() async {
    _nativePollTimer?.cancel();
    await _engine.dispose();
    await _controller.close();
    await _store.close();
  }
}

/// Buffered completion from a native background task that fired before
/// [_recovering] was populated by [_recoverJobs].
class _PendingRecoveryEvent {
  final String jobId;
  final bool success;
  final String? eTag;
  final bool urlExpired;
  final String? fileUrl;
  final bool isApi;
  final String? responseBody;
  final int? statusCode;

  const _PendingRecoveryEvent({
    required this.jobId,
    required this.success,
    this.eTag,
    required this.urlExpired,
    this.fileUrl,
    required this.isApi,
    this.responseBody,
    this.statusCode,
  });
}
