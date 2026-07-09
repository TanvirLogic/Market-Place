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

/// Log a message with a tag that's visible in `adb logcat` in release mode.
void _log(String message) {
  // Use print() instead of AppLogger because the logger package uses
  // debugPrint which is silenced in release builds. print() goes to
  // stdout which Flutter's engine forwards to logcat with tag "flutter".
  print('EduverseUpload: $message');
}

/// If a job has been queued longer than this, proactively refresh its
/// presigned URLs before starting the upload loop to avoid 403 storms.
const Duration _presignedRefreshAge = Duration(minutes: 30);

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

  /// Connectivity monitoring — auto-pause on disconnect, auto-resume on reconnect.
  Timer? _connectivityTimer;
  bool _isOnline = true;

  /// Jobs explicitly paused by the user.
  final Set<String> _pausedJobs = {};

  /// Whether the entire queue is paused (e.g. due to connectivity loss).
  bool _queuePaused = false;

  /// Speed tracking: bytes uploaded tracked per second for ETA calculation.
  final Map<String, _SpeedSample> _speedSamples = {};

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
    _startConnectivityMonitoring();
  }

  void _startConnectivityMonitoring() {
    if (_connectivityTimer != null) return;
    _connectivityTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final online = await _checkConnectivity();
      if (online && !_isOnline) {
        _log('CONNECTIVITY: online — resuming queue');
        _isOnline = true;
        _queuePaused = false;
        _dequeue();
      } else if (!online && _isOnline) {
        _log('CONNECTIVITY: offline — pausing queue');
        _isOnline = false;
        _queuePaused = true;
      }
    });
  }

  Future<bool> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Scan persisted jobs and reconcile with background_downloader tasks after
  /// an app restart. Jobs whose S3 upload completed while we were dead proceed
  /// to the callback phase. Jobs with running tasks are tracked via
  /// [BackgroundUploadEngine.onTaskFinal].
  Future<void> _recoverJobs() async {
    final jobs = await _store.loadAll();
    if (jobs.isEmpty) {
      _log('RECOVERY: no persisted jobs found');
      return;
    }

    _log('RECOVERY: ${jobs.length} job(s) to recover');
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
        _log('RECOVERY: id=${job.id} native bridge job, already reconciled above');
        continue;
      }
      _jobs[job.id] = job;
      _log('RECOVERY: id=${job.id} state=${job.state.wire} type=${job.type.wire} title="${job.title}"');

      // Fetch all background_downloader task records for this job.
      final group = UploadTaskFactory.groupFor(job.id);
      final records = await db.allRecords(group: group);

      if (records.isEmpty) {
        // No engine tasks — either never started, or already finished and the
        // terminal state save didn't persist before kill.
        if (job.state == UploadJobState.callback) {
          // Upload + complete steps already ran; just re-run idempotent callback.
          _log('RECOVERY: id=${job.id} no tasks, state=callback — re-running callback');
          AppLogger.i('UploadService._recoverJobs: ${job.id} has no tasks but state=callback, re-running callback');
          _recoverRunCallback(job);
          continue;
        }
        if (!File(job.filePath).existsSync()) {
          _log('RECOVERY: id=${job.id} source file missing — failing');
          AppLogger.w('UploadService._recoverJobs: ${job.id} source file missing');
          _fail(job, 'Source file not found');
          continue;
        }
        // Never got to the transfer phase — start from scratch.
        _log('RECOVERY: id=${job.id} no tasks, re-enqueueing from scratch');
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
            final doneCount = records.where((r) => r.status.isFinalState).length;
            _log('RECOVERY: id=${job.id} $doneCount/$allPendingTasks tasks done, tracking for completion');
            AppLogger.i('UploadService._recoverJobs: ${job.id} has $allPendingTasks pending task(s), tracking for recovery');
            _recovering.add(job.id);
            _recoveryTotal[job.id] = allPendingTasks;
            _recoveryDone[job.id] = doneCount;
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
    const maxAttempts = 5;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final body = jsonEncode(_routes.forJob(job).callbackBody(job));
        final task = _buildCallbackTask(job, body);
        final result = await _engine.enqueueApiCall(task);
        if (result.success || result.statusCode == 409) {
          AppLogger.i('UploadService._runCallback ${job.id} succeeded');
          _setState(job, UploadJobState.completed);
          return;
        }
        // On 401/403 refresh the token and retry immediately this attempt.
        if (result.urlExpired) {
          final fresh = _buildCallbackTask(job, body);
          final retry = await _engine.enqueueApiCall(fresh);
          if (retry.success || retry.statusCode == 409) {
            AppLogger.i('UploadService._runCallback ${job.id} succeeded after token refresh');
            _setState(job, UploadJobState.completed);
            return;
          }
        }
        AppLogger.w('UploadService._runCallback ${job.id} attempt $attempt/$maxAttempts '
            'HTTP ${result.statusCode} ${result.error}');
      } catch (e) {
        AppLogger.w('UploadService._runCallback ${job.id} attempt $attempt/$maxAttempts error: $e');
      }
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    AppLogger.e('UploadService._runCallback ${job.id} exhausted $maxAttempts attempts');
    _setState(job, UploadJobState.failed);
  }

  DataTask _buildCallbackTask(UploadJob job, String body) {
    final route = _routes.forJob(job);
    return _factory.callbackTask(
      job: job,
      url: route.callbackEndpoint,
      body: body,
      token: AuthController.accessToken ?? '',
      method: route.callbackMethod,
    );
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
    _log('enqueue: id=$id type=${type.wire} title="$title" path=$filePath size=$fileSize');
    unawaited(_store.save(job));
    _emit(job);
    _dequeue();
    return job;
  }

  /// Picks the next queued job and processes it serially.
  void _dequeue() {
    if (_isProcessing) return;
    if (_queuePaused) return;
    if (_jobQueue.isEmpty) return;

    _isProcessing = true;
    final nextId = _jobQueue.first;
    _jobQueue.remove(nextId);

    // Skip if job was paused while queued.
    if (_pausedJobs.contains(nextId)) {
      _isProcessing = false;
      _dequeue();
      return;
    }

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
      _log('PROCESS START: id=${job.id} type=${job.type.wire} title="${job.title}" path=${job.filePath} size=${job.fileSize}');
      AppLogger.i('UploadService._process ${job.id} starting type=${job.type.wire}');

      if (!File(job.filePath).existsSync()) {
        _log('PROCESS FAIL: id=${job.id} source file missing: ${job.filePath}');
        AppLogger.e('UploadService._process ${job.id} source file missing: ${job.filePath}');
        return _fail(job, 'Source file not found');
      }

      await ensureStarted();
      final route = _routes.forJob(job);

      // ---- Android: run the whole pipeline natively (survives app kill) ----
      if (NativeUploadBridge.isSupported) {
        _log('PROCESS NATIVE BRIDGE: id=${job.id} delegating to native WorkManager');
        await _processAndroidNative(job, route);
        return;
      }

      // ---- Step 1: init ----
      _setState(job, UploadJobState.uploading);
      _log('INIT REQUEST: id=${job.id} url=${route.initEndpoint} body=${jsonEncode(route.initBody)}');
      AppLogger.i('UploadService._process ${job.id} init endpoint=${route.initEndpoint} body=${route.initBody}');
      final init = await _api.init(
        endpoint: route.initEndpoint,
        body: route.initBody,
        courseAssetKey: route.courseAssetKey,
      );
      if (init == null) {
        _log('INIT FAILED: id=${job.id} url=${route.initEndpoint} — null response');
        AppLogger.e('UploadService._process ${job.id} init returned null');
        return _fail(job, 'Failed to initialize upload');
      }
      _log('INIT SUCCESS: id=${job.id} isMultipart=${init.isMultipart} parts=${init.parts.length} fileUrl=${init.fileUrl} key=${init.key} s3UploadId=${init.s3UploadId}');
      _applyInit(job, init);

      // ── Proactive presigned URL refresh ──
      // If the job was queued long ago, its S3 presigned URLs may have expired.
      // Re-init to get fresh URLs before starting the transfer loop, avoiding
      // a cascade of 403 mid-upload failures and individual retries.
      if (job.isMultipart) {
        final jobAge = DateTime.now().millisecondsSinceEpoch - job.createdAt;
        if (jobAge > _presignedRefreshAge.inMilliseconds) {
          _log('REFRESH: id=${job.id} is ${jobAge ~/ 1000}s old — refreshing presigned URLs');
          AppLogger.i('UploadService._process ${job.id} is ${jobAge ~/ 1000}s old — proactively refreshing presigned URLs');
          final freshInit = await _api.init(
            endpoint: route.initEndpoint,
            body: route.initBody,
            courseAssetKey: route.courseAssetKey,
          );
          if (freshInit != null && freshInit.isMultipart &&
              freshInit.parts.length == job.parts.length) {
            for (var i = 0; i < job.parts.length; i++) {
              job.parts[i].uploadUrl = freshInit.parts[i].uploadUrl;
            }
            _log('REFRESH SUCCESS: id=${job.id} URLs refreshed');
            AppLogger.i('UploadService._process ${job.id}: proactive refresh succeeded');
          }
        }
      }

      // ---- Step 2: transfer ----
      job.transferStartedAt = DateTime.now().millisecondsSinceEpoch;
      job.transferredBytes = 0;
      if (job.isMultipart) {
        _log('MULTIPART START: id=${job.id} parts=${job.parts.length} fileSize=${job.fileSize}');
        final results = await _engine.uploadParts(job);
        final ok = results.where((r) => r.success).length;
        final fail = results.where((r) => !r.success).length;
        _log('MULTIPART DONE: id=${job.id} success=$ok failed=$fail');
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
          _log('MULTIPART FAIL: id=${job.id} not all parts done — aborting');
          await _abort(job, route);
          return _fail(job, 'One or more parts failed to upload');
        }
        _log('MULTIPART ALL DONE: id=${job.id}');

        // ---- Step 3: complete (multipart only) — native task ----
        _setState(job, UploadJobState.completing);
        final completeBody = jsonEncode({
          'key': job.key,
          'uploadId': job.s3UploadId,
          'parts': job.etagPayload,
        });
        _log('COMPLETE REQUEST: id=${job.id} url=${route.completeEndpoint} body=$completeBody');
        var completeTask = _factory.completeTask(
          job: job,
          url: route.completeEndpoint,
          body: completeBody,
          token: AuthController.accessToken ?? '',
        );
        var completeResult = await _engine.enqueueApiCall(completeTask);
        // Retry once if token expired (401).
        if (!completeResult.success && completeResult.urlExpired) {
          _log('COMPLETE RETRY: id=${job.id} 401, retrying with fresh token');
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
          _log('COMPLETE FAILED: id=${job.id} error=${completeResult.error}');
          await _abort(job, route);
          return _fail(job, completeResult.error ?? 'Complete failed');
        }
        _log('COMPLETE SUCCESS: id=${job.id} fileUrl=${completeResult.fileUrl}');
        job.fileUrl = completeResult.fileUrl;
      } else {
        // Direct upload: object is already stored at `key` on success; the
        // fileUrl came from init. No S3 complete call needed.
        _log('DIRECT UPLOAD START: id=${job.id}');
        AppLogger.i('UploadService._process ${job.id} direct upload starting');
        var result = await _engine.uploadDirect(job);
        // Retry once if presigned URL expired.
        if (!result.success && result.urlExpired) {
          _log('DIRECT UPLOAD RETRY: id=${job.id} URL expired, re-initing');
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
          _log('DIRECT UPLOAD FAILED: id=${job.id} error=${result.error}');
          AppLogger.e('UploadService._process ${job.id} direct upload failed: ${result.error}');
          return _fail(job, result.error ?? 'Direct upload failed');
        }
        _log('DIRECT UPLOAD SUCCESS: id=${job.id}');
        AppLogger.i('UploadService._process ${job.id} direct upload succeeded');
      }

      // ---- Step 4: callback — native task ----
      _setState(job, UploadJobState.callback);
      final callbackBody = jsonEncode(route.callbackBody(job));
      _log('CALLBACK REQUEST: id=${job.id} url=${route.callbackEndpoint} method=${route.callbackMethod} body=$callbackBody');
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
        _log('CALLBACK RETRY: id=${job.id} 401, retrying with fresh token');
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
        _log('CALLBACK FAILED: id=${job.id} statusCode=${callbackResult.statusCode} error=${callbackResult.error}');
        AppLogger.e('UploadService._process ${job.id} callback failed: ${callbackResult.error}');
        return _fail(job, callbackResult.error ?? 'Server callback failed');
      }
      _log('CALLBACK SUCCESS: id=${job.id} statusCode=${callbackResult.statusCode}');

      _setState(job, UploadJobState.completed);
      _log('PROCESS COMPLETE: id=${job.id} fileUrl=${job.fileUrl}');
    } catch (e, st) {
      _log('PROCESS ERROR: id=${job.id} error=$e');
      AppLogger.e('UploadService._process ${job.id} error: $e\n$st');
      _fail(job, e.toString());
    }
  }

  /// Android path: hand the entire job (init → transfer → complete → callback)
  /// to the native WorkManager pipeline so it completes even if the app is
  /// killed. We build the callback body with a `__FILE_URL__` placeholder that
  /// the worker fills in once it knows the final S3 url.
  Future<void> _processAndroidNative(UploadJob job, UploadRoute route) async {
    _log('NATIVE BRIDGE: id=${job.id} initUrl=${route.initEndpoint} completeUrl=${route.completeEndpoint} callbackUrl=${route.callbackEndpoint} method=${route.callbackMethod}');
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
      'createdAt': job.createdAt,
    };

    final started = await NativeUploadBridge.enqueueUpload(jobData);
    if (!started) {
      _log('NATIVE BRIDGE ENQUEUE FAILED: id=${job.id}');
      return _fail(job, 'Failed to start native upload');
    }

    _log('NATIVE BRIDGE ENQUEUED: id=${job.id} — pipeline runs in WorkManager');
    job.metadata['nativeBridge'] = true;
    _setState(job, UploadJobState.uploading);
    unawaited(_store.save(job));
    _startNativePolling();
  }

  /// Periodically poll the native pipeline for terminal results and reconcile.
  void _startNativePolling() {
    if (_nativePollTimer != null) return;
    _log('NATIVE POLLING STARTED: polling every 3s');
    _nativePollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollNativeResults(),
    );
  }

  Future<void> _pollNativeResults() async {
    if (!NativeUploadBridge.isSupported) return;
    final results = await NativeUploadBridge.getCompletedJobs();
    if (results.isNotEmpty) {
      _log('NATIVE POLL: ${results.length} result(s) from native pipeline');
    }
    for (final r in results) {
      final jobId = r['jobId'] as String?;
      if (jobId == null) continue;
      final job = _jobs[jobId];
      if (job == null) {
        unawaited(NativeUploadBridge.clearResult(jobId));
        continue;
      }
      _reconcileNativeResult(job, r);
    }

    // Pull real-time progress for active native jobs.
    for (final job in _jobs.values) {
      if (job.metadata['nativeBridge'] != true) continue;
      if (job.state.isTerminal) continue;
      final pct = await NativeUploadBridge.getProgress(job.id);
      if (pct != null) {
        // Native progress is 0-100; map to 0.0-0.95 (reserve 5% for complete+callback).
        job.progress = (pct / 100.0 * 0.95).clamp(0.0, 0.95);
        job.touch();
        _emit(job);
        _log('NATIVE PROGRESS: id=${job.id} ${job.state.wire} nativePct=$pct mappedProgress=${(job.progress * 100).toStringAsFixed(0)}%');
      }
    }

    // Stop polling once no native jobs remain in flight.
    final hasNative = _jobs.values.any(
      (j) => j.metadata['nativeBridge'] == true && !j.state.isTerminal,
    );
    if (!hasNative) {
      _log('NATIVE POLLING STOPPED: no pending native jobs');
      _nativePollTimer?.cancel();
      _nativePollTimer = null;
    }
  }

  void _reconcileNativeResult(UploadJob job, Map<String, dynamic> result) {
    final status = result['status'] as String? ?? '';
    final fileUrl = result['fileUrl'] as String?;
    final error = result['error'] as String?;

    _log('NATIVE RESULT: id=${job.id} status=$status fileUrl=$fileUrl error=$error');
    if (status == 'completed') {
      if (fileUrl != null && fileUrl.isNotEmpty) job.fileUrl = fileUrl;
      _setState(job, UploadJobState.completed);
      unawaited(NativeUploadBridge.clearResult(job.id));
    } else if (fileUrl != null && fileUrl.isNotEmpty) {
      // S3 upload succeeded (bytes on S3) but the native callback (step 4)
      // failed. Retry the callback from Dart since it's idempotent (409-safe).
      _log('NATIVE CALLBACK RETRY: id=${job.id} S3 bytes uploaded, retrying callback from Dart');
      unawaited(NativeUploadBridge.clearResult(job.id));
      job.fileUrl = fileUrl;
      job.progress = 0.99;
      _setState(job, UploadJobState.callback);
      unawaited(_runCallback(job));
    } else {
      // Genuine failure — nothing on S3.
      _log('NATIVE FAILED: id=${job.id} error=$error');
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
      // Fixed 5 MB part size as specified by the backend.
      const partSize = 5 * 1024 * 1024;
      final serverTotal = init.parts.length;
      final needed = (job.fileSize + partSize - 1) ~/ partSize;
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
    _pausedJobs.remove(id);
    job.error = null;
    job.progress = 0.0;
    job.key = null;
    job.s3UploadId = null;
    job.fileUrl = null;
    job.directUploadUrl = null;
    job.isMultipart = false;
    job.parts.clear();
    job.metadata.remove('nativeBridge');
    job.speedBytesPerSec = null;
    job.etaSeconds = null;
    job.transferStartedAt = null;
    job.transferredBytes = 0;
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
    if (job != null) {
      await _hardRemove(job);
    } else {
      await _store.delete(id);
    }
  }

  void _onEngineProgress(String jobId, double progress) {
    final job = _jobs[jobId];
    if (job == null) return;
    job.progress = job.isMultipart ? progress * 0.95 : progress;
    job.transferredBytes = (progress * job.fileSize).round();

    // Speed & ETA calculation.
    final now = DateTime.now().millisecondsSinceEpoch;
    final sample = _speedSamples.putIfAbsent(jobId, () => _SpeedSample(now: now, bytes: job.transferredBytes));
    final elapsed = now - sample.now;
    if (elapsed >= 2000) {
      final bytesDelta = job.transferredBytes - sample.bytes;
      final secDelta = elapsed / 1000.0;
      if (bytesDelta > 0 && secDelta > 0) {
        job.speedBytesPerSec = (bytesDelta / secDelta).roundToDouble();
        if (job.speedBytesPerSec! > 0) {
          final remaining = job.fileSize - job.transferredBytes;
          job.etaSeconds = (remaining / job.speedBytesPerSec!).round();
        }
      }
      sample.now = now;
      sample.bytes = job.transferredBytes;
    }

    job.touch();
    _emit(job);
  }

  void _setState(UploadJob job, UploadJobState state) {
    // Prevent overwriting a terminal state (e.g. cancel vs fail race).
    if (job.state.isTerminal && state != UploadJobState.pending) return;
    _log('STATE: id=${job.id} ${job.state.wire} -> ${state.wire}');
    job.state = state;
    if (state == UploadJobState.completed) {
      job.progress = 1.0;
    } else if (state == UploadJobState.callback && job.progress < 0.99) {
      job.progress = 0.99;
    } else if (state == UploadJobState.completing && job.progress < 0.95) {
      job.progress = 0.95;
    }
    job.touch();
    unawaited(_store.save(job));
    if (state.isTerminal) {
      unawaited(_cleanupJob(job));
    }
    _emit(job);
  }

  void _fail(UploadJob job, String message) {
    job.error = message;
    _setState(job, UploadJobState.failed);
    // Keep job in _jobs so the UI can show it and the user can retry.
    unawaited(_store.save(job));
  }

  /// Permanently remove a job from memory and storage (used by explicit
  /// user command via [remove]).
  Future<void> _hardRemove(UploadJob job) async {
    _jobQueue.remove(job.id);
    _jobs.remove(job.id);
    await _store.delete(job.id);
    await _cleanupJob(job);
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

  // ── Pause / Resume ─────────────────────────────────────────────────────

  /// Pause a single active job. It will be skipped when dequeue picks it up.
  Future<void> pause(String id) async {
    final job = _jobs[id];
    if (job == null || job.state.isTerminal || _pausedJobs.contains(id)) return;
    _pausedJobs.add(id);
    // If currently processing, cancel the engine tasks so they stop.
    if (job.state == UploadJobState.uploading ||
        job.state == UploadJobState.completing ||
        job.state == UploadJobState.callback) {
      await _engine.cancelJob(id);
    }
    _setState(job, UploadJobState.paused);
  }

  /// Resume a paused job — re-enqueue it for processing.
  Future<void> resume(String id) async {
    final job = _jobs[id];
    if (job == null || job.state != UploadJobState.paused) return;
    _pausedJobs.remove(id);
    _setState(job, UploadJobState.pending);
    _jobQueue.add(id);
    _dequeue();
  }

  /// Pause all active uploads.
  Future<void> pauseAll() async {
    _queuePaused = true;
    final ids = _jobs.values
        .where((j) => j.state.isActive && !j.state.isTerminal)
        .map((j) => j.id)
        .toList();
    for (final id in ids) {
      await pause(id);
    }
    _log('PAUSE ALL: ${ids.length} job(s) paused');
  }

  /// Resume all paused uploads.
  Future<void> resumeAll() async {
    _queuePaused = false;
    final ids = _jobs.values
        .where((j) => j.state == UploadJobState.paused)
        .map((j) => j.id)
        .toList();
    for (final id in ids) {
      await resume(id);
    }
    _log('RESUME ALL: ${ids.length} job(s) resumed');
  }

  // ── Batch operations ───────────────────────────────────────────────────

  /// Retry all failed uploads. Returns the count retried.
  Future<int> retryAllFailed() async {
    final failed = _jobs.values
        .where((j) => j.state == UploadJobState.failed)
        .map((j) => j.id)
        .toList();
    for (final id in failed) {
      // Re-add to store and re-enqueue.
      final job = _jobs[id];
      if (job != null) {
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
        unawaited(_store.save(job));
      }
    }
    _dequeue();
    _log('RETRY ALL FAILED: ${failed.length} job(s)');
    return failed.length;
  }

  /// Cancel all active (non-terminal) uploads.
  Future<void> cancelAllActive() async {
    final ids = _jobs.values
        .where((j) => !j.state.isTerminal)
        .map((j) => j.id)
        .toList();
    for (final id in ids) {
      _jobQueue.remove(id);
      final job = _jobs[id];
      if (job != null) {
        await _engine.cancelJob(id);
        final route = _routes.forJob(job);
        await _abort(job, route);
        _setState(job, UploadJobState.cancelled);
      }
    }
    _log('CANCEL ALL: ${ids.length} job(s) cancelled');
  }

  Future<void> dispose() async {
    _nativePollTimer?.cancel();
    _connectivityTimer?.cancel();
    await _engine.dispose();
    await _controller.close();
    await _store.close();
  }
}

/// A snapshot of bytes-transferred-at-timestamp used for speed computation.
class _SpeedSample {
  int now;
  int bytes;
  _SpeedSample({required this.now, required this.bytes});
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
