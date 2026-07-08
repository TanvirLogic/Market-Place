import 'dart:async';

import 'package:edtech/global/core/services/logger_service.dart';

import '../data/api/s3_upload_api.dart';
import '../data/models/s3_init_response.dart';
import '../data/models/upload_enums.dart';
import '../data/models/upload_job.dart';
import '../engine/background_upload_engine.dart';
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
  })  : _api = api,
        _routes = routes,
        _engine = engine ?? BackgroundUploadEngine() {
    _engine.onJobProgress = _onEngineProgress;
  }

  final S3UploadApi _api;
  final UploadRoutes _routes;
  final BackgroundUploadEngine _engine;

  final Map<String, UploadJob> _jobs = {};
  final _controller = StreamController<UploadJob>.broadcast();

  /// Emits a job whenever its state or progress changes.
  Stream<UploadJob> get updates => _controller.stream;

  List<UploadJob> get jobs => _jobs.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  UploadJob? job(String id) => _jobs[id];

  Future<void> ensureStarted() => _engine.ensureStarted();

  /// Enqueue a new upload. Returns the created job immediately; processing runs
  /// asynchronously and progress is reported via [updates].
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
    _emit(job);
    // Fire and forget — the flow drives itself and reports via the stream.
    unawaited(_process(job));
    return job;
  }

  Future<void> _process(UploadJob job) async {
    try {
      AppLogger.i('UploadService._process ${job.id} starting type=${job.type.wire}');
      await ensureStarted();
      final route = _routes.forJob(job);

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
        final allDone = job.parts.every((p) => p.done);
        if (!allDone) {
          await _abort(job, route);
          return _fail(job, 'One or more parts failed to upload');
        }

        // ---- Step 3: complete (multipart only) ----
        _setState(job, UploadJobState.completing);
        final complete = await _api.complete(
          endpoint: route.completeEndpoint,
          key: job.key!,
          s3UploadId: job.s3UploadId!,
          parts: job.etagPayload,
        );
        if (!complete.isSuccess) {
          await _abort(job, route);
          return _fail(job, complete.errorMessage ?? 'Complete failed');
        }
        job.fileUrl = complete.fileUrl;
      } else {
        // Direct upload: object is already stored at `key` on success; the
        // fileUrl came from init. No S3 complete call needed.
        AppLogger.i('UploadService._process ${job.id} direct upload starting');
        final result = await _engine.uploadDirect(job);
        if (!result.success) {
          AppLogger.e('UploadService._process ${job.id} direct upload failed: ${result.error}');
          return _fail(job, result.error ?? 'Direct upload failed');
        }
        AppLogger.i('UploadService._process ${job.id} direct upload succeeded');
      }

      // ---- Step 4: callback ----
      _setState(job, UploadJobState.callback);
      AppLogger.i('UploadService._process ${job.id} callback endpoint=${route.callbackEndpoint} method=${route.callbackMethod} body=${route.callbackBody(job)}');
      final ok = await _api.callback(
        endpoint: route.callbackEndpoint,
        method: route.callbackMethod,
        body: route.callbackBody(job),
        idempotencyKey: '${job.id}_callback',
      );
      if (!ok) {
        AppLogger.e('UploadService._process ${job.id} callback failed');
        return _fail(job, 'Server callback failed');
      }

      _setState(job, UploadJobState.completed);
    } catch (e, st) {
      AppLogger.e('UploadService._process ${job.id} error: $e\n$st');
      _fail(job, e.toString());
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

  /// Retry a failed job from scratch.
  Future<void> retry(String id) async {
    final job = _jobs[id];
    if (job == null || !job.state.isTerminal) return;
    job.error = null;
    job.progress = 0.0;
    for (final p in job.parts) {
      p.eTag = null;
    }
    _setState(job, UploadJobState.pending);
    unawaited(_process(job));
  }

  Future<void> cancel(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    await _engine.cancelJob(id);
    final route = _routes.forJob(job);
    await _abort(job, route);
    _setState(job, UploadJobState.cancelled);
  }

  void remove(String id) {
    _jobs.remove(id);
  }

  void _onEngineProgress(String jobId, double progress) {
    final job = _jobs[jobId];
    if (job == null) return;
    // Reserve the last 10% for complete+callback so the bar doesn't sit at 100%
    // while finalizing.
    job.progress = job.isMultipart ? progress * 0.9 : progress;
    job.touch();
    _emit(job);
  }

  void _setState(UploadJob job, UploadJobState state) {
    job.state = state;
    if (state == UploadJobState.completed) job.progress = 1.0;
    job.touch();
    _emit(job);
  }

  void _fail(UploadJob job, String message) {
    job.error = message;
    _setState(job, UploadJobState.failed);
  }

  void _emit(UploadJob job) {
    if (!_controller.isClosed) _controller.add(job);
  }

  Future<void> dispose() async {
    await _engine.dispose();
    await _controller.close();
  }
}
