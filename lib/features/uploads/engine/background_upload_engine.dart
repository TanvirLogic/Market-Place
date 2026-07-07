import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import '../data/models/upload_job.dart';
import 'upload_task_factory.dart';

/// Outcome of a single task (direct upload or one multipart part).
class PartResult {
  final int? partNumber; // null for a direct upload
  final bool success;
  final String? eTag;
  final int? statusCode;
  final bool urlExpired;
  final String? error;

  const PartResult({
    required this.partNumber,
    required this.success,
    this.eTag,
    this.statusCode,
    this.urlExpired = false,
    this.error,
  });
}

/// Aggregated progress for a job (0.0 – 1.0).
typedef JobProgress = void Function(String jobId, double progress);

/// Wraps `background_downloader` for S3 uploads. Responsible only for the byte
/// transfer (step 2): enqueuing binary PUTs (direct or per-part with Range),
/// pacing them through a [MemoryTaskQueue], and reporting per-task results with
/// the S3 ETag pulled from the response headers.
///
/// The engine is intentionally stateless about the S3 flow — the orchestrator
/// ([UploadService]) drives init/complete/callback. This class just moves bytes
/// and hands back ETags.
class BackgroundUploadEngine {
  BackgroundUploadEngine({
    int maxConcurrent = 3,
    int maxConcurrentByHost = 3,
  })  : _maxConcurrent = maxConcurrent,
        _maxConcurrentByHost = maxConcurrentByHost;

  final int _maxConcurrent;
  final int _maxConcurrentByHost;
  final _factory = const UploadTaskFactory();

  final _fd = FileDownloader();
  late final MemoryTaskQueue _queue;

  StreamSubscription<TaskUpdate>? _updatesSub;
  StreamSubscription? _enqueueErrSub;

  bool _started = false;

  /// Per-task completers keyed by taskId, resolved when a task reaches a final
  /// state. Lets callers `await` a specific upload.
  final Map<String, Completer<PartResult>> _pending = {};

  /// Optional aggregate progress callback per job.
  JobProgress? onJobProgress;

  /// Live progress fraction per task, used to aggregate a job's progress.
  final Map<String, double> _taskProgress = {};

  /// Initialize the downloader database, task queue and update listener.
  /// Safe to call multiple times.
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;

    _queue = MemoryTaskQueue()
      ..maxConcurrent = _maxConcurrent
      ..maxConcurrentByHost = _maxConcurrentByHost;
    _fd.addTaskQueue(_queue);

    _updatesSub = _fd.updates.listen(_onUpdate);
    _enqueueErrSub = _queue.enqueueErrors.listen((task) {
      final c = _pending.remove(task.taskId);
      c?.complete(PartResult(
        partNumber: UploadTaskFactory.partNumberOf(task.taskId),
        success: false,
        error: 'Failed to enqueue task',
      ));
    });

    // Show OS progress notifications for uploads (survives app kill). Applies
    // to all upload tasks; per-job grouping is handled by the Task.group.
    _fd.configureNotification(
      running: const TaskNotification('Uploading', '{filename}  {progress}'),
      complete: const TaskNotification('Upload complete', '{filename}'),
      error: const TaskNotification('Upload failed', '{filename}'),
      progressBar: true,
    );

    // Activate DB tracking + resume background events + reschedule killed tasks.
    await _fd.start(
      doTrackTasks: true,
      doRescheduleKilledTasks: true,
    );
  }

  /// Enqueue a direct single-PUT upload and return a future for its result.
  Future<PartResult> uploadDirect(UploadJob job) async {
    await ensureStarted();
    final task = await _factory.directTask(job);
    return _enqueueAndAwait(task);
  }

  /// Enqueue one multipart part and return a future for its result.
  Future<PartResult> uploadPart(UploadJob job, UploadPart part) async {
    await ensureStarted();
    final task = await _factory.partTask(job, part);
    return _enqueueAndAwait(task);
  }

  /// Enqueue all not-yet-done parts of a job concurrently; completes when all
  /// have finished. Returns results in part-number order.
  Future<List<PartResult>> uploadParts(UploadJob job) async {
    await ensureStarted();
    final pending = job.parts.where((p) => !p.done).toList();
    final futures = pending.map((p) => uploadPart(job, p)).toList();
    final results = await Future.wait(futures);
    results.sort((a, b) => (a.partNumber ?? 0).compareTo(b.partNumber ?? 0));
    return results;
  }

  Future<PartResult> _enqueueAndAwait(UploadTask task) {
    final completer = Completer<PartResult>();
    _pending[task.taskId] = completer;
    _taskProgress[task.taskId] = 0.0;
    _queue.add(task);
    return completer.future;
  }

  void _onUpdate(TaskUpdate update) {
    final taskId = update.task.taskId;
    // Only handle our own upload tasks.
    if (!update.task.group.startsWith(UploadTaskFactory.groupPrefix)) return;

    switch (update) {
      case TaskProgressUpdate():
        if (update.progress >= 0) {
          _taskProgress[taskId] = update.progress;
          _emitJobProgress(UploadTaskFactory.jobIdOf(taskId));
        }
      case TaskStatusUpdate():
        if (!update.status.isFinalState) return;
        final completer = _pending.remove(taskId);
        if (completer == null || completer.isCompleted) return;
        completer.complete(_resultFrom(update));
    }
  }

  PartResult _resultFrom(TaskStatusUpdate update) {
    final taskId = update.task.taskId;
    final partNumber = UploadTaskFactory.partNumberOf(taskId);
    final code = update.responseStatusCode;

    if (update.status == TaskStatus.complete) {
      final etag = _readETag(update.responseHeaders);
      _taskProgress[taskId] = 1.0;
      _emitJobProgress(UploadTaskFactory.jobIdOf(taskId));
      return PartResult(
        partNumber: partNumber,
        success: true,
        eTag: etag,
        statusCode: code,
      );
    }

    return PartResult(
      partNumber: partNumber,
      success: false,
      statusCode: code,
      // S3 presigned URLs return 403 when expired.
      urlExpired: code == 403,
      error: update.exception?.description ??
          'Upload ${update.status.name} (HTTP ${code ?? '—'})',
    );
  }

  /// Read the S3 ETag from response headers. background_downloader lowercases
  /// header names. Preserve the value verbatim (quotes included) — the complete
  /// endpoint expects the raw header value.
  String? _readETag(Map<String, String>? headers) {
    if (headers == null) return null;
    return headers['etag'] ?? headers['ETag'] ?? headers['Etag'];
  }

  void _emitJobProgress(String jobId) {
    final cb = onJobProgress;
    if (cb == null) return;
    final entries = _taskProgress.entries
        .where((e) => UploadTaskFactory.jobIdOf(e.key) == jobId)
        .toList();
    if (entries.isEmpty) return;
    final avg =
        entries.map((e) => e.value).reduce((a, b) => a + b) / entries.length;
    cb(jobId, avg.clamp(0.0, 1.0));
  }

  /// Cancel every task belonging to a job (all parts / the direct task).
  Future<void> cancelJob(String jobId) async {
    final group = UploadTaskFactory.groupFor(jobId);
    await _fd.cancelAll(group: group);
    // Fail any awaiting completers for this job.
    final ids =
        _pending.keys.where((id) => UploadTaskFactory.jobIdOf(id) == jobId).toList();
    for (final id in ids) {
      final c = _pending.remove(id);
      if (c != null && !c.isCompleted) {
        c.complete(PartResult(
          partNumber: UploadTaskFactory.partNumberOf(id),
          success: false,
          error: 'Cancelled',
        ));
      }
    }
  }

  Future<void> dispose() async {
    await _updatesSub?.cancel();
    await _enqueueErrSub?.cancel();
  }
}
