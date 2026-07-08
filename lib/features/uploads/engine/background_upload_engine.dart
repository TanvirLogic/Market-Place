import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

import '../data/models/upload_job.dart';
import 'upload_task_factory.dart';

/// Outcome of a single task (S3 byte transfer or API call).
class PartResult {
  final int? partNumber; // null for direct upload / API task
  final bool success;
  final String? eTag;
  final int? statusCode;
  final bool urlExpired;
  final String? error;

  /// Set for the S3 complete API response; null otherwise.
  final String? fileUrl;

  /// Raw response body from API tasks.
  final String? responseBody;

  const PartResult({
    this.partNumber,
    required this.success,
    this.eTag,
    this.statusCode,
    this.urlExpired = false,
    this.error,
    this.fileUrl,
    this.responseBody,
  });
}

/// Aggregated progress for a job (0.0 – 1.0).
typedef JobProgress = void Function(String jobId, double progress);

/// Called when any tracked task reaches a final state (complete/failed).
/// Fires even when no [PartResult] completer was registered, which is critical
/// for restart recovery where [BackgroundUploadEngine._pending] is empty.
typedef TaskFinal = void Function(
  String jobId,
  bool success,
  String? eTag,
  bool urlExpired,
  String? fileUrl,
  bool isApi,
  String? responseBody,
  int? statusCode,
);

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

  /// Called when ANY tracked task reaches a final state, even without a
  /// registered [PartResult] completer. Used for restart recovery.
  TaskFinal? onTaskFinal;

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

    // Activate DB tracking + resume background events + reschedule killed tasks.
    await _fd.start(
      doTrackTasks: true,
      doRescheduleKilledTasks: true,
    );
  }

  /// Configure the OS notification for a byte-transfer [task]. On Android this
  /// is what promotes the upload to a foreground service, so the transfer keeps
  /// running after the app is backgrounded or killed. It is the SINGLE source
  /// of upload notifications (the Dart-side notification service is not used for
  /// uploads, to avoid duplicate notifications).
  ///
  /// [groupId], when set, collapses all of a job's multipart parts into ONE
  /// notification. Direct (single-PUT) uploads pass null so the notification can
  /// show a smooth percentage via `{progress}`.
  ///
  /// The tiny complete/callback API calls (DataTasks) are intentionally left
  /// without a notification config so they stay silent.
  void _configureTransferNotification(Task task, {String? groupId}) {
    _fd.configureNotificationForTask(
      task,
      running: TaskNotification(
        '{displayName}',
        groupId == null ? 'Uploading {progress}' : 'Uploading…',
      ),
      complete: const TaskNotification('{displayName}', 'Uploaded successfully'),
      error: const TaskNotification('{displayName}', 'Upload failed — tap to retry'),
      progressBar: true,
      groupNotificationId: groupId ?? '',
    );
  }

  /// Enqueue a direct single-PUT upload and return a future for its result.
  Future<PartResult> uploadDirect(UploadJob job) async {
    await ensureStarted();
    final task = await _factory.directTask(job);
    // Single PUT → per-task notification with a smooth percentage.
    _configureTransferNotification(task);
    return _enqueueAndAwait(task);
  }

  /// Enqueue one multipart part and return a future for its result.
  Future<PartResult> uploadPart(UploadJob job, UploadPart part) async {
    await ensureStarted();
    final task = await _factory.partTask(job, part);
    // Multipart → group all parts of this job under ONE notification.
    _configureTransferNotification(task, groupId: 'upload_${job.id}');
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

  /// Enqueue an API call task (complete or callback step) that runs
  /// natively via background_downloader. Awaits its result.
  Future<PartResult> enqueueApiCall(Task task) async {
    await ensureStarted();
    return _enqueueAndAwait(task);
  }

  Future<PartResult> _enqueueAndAwait(Task task) {
    final completer = Completer<PartResult>();
    _pending[task.taskId] = completer;
    _taskProgress[task.taskId] = 0.0;
    _queue.add(task);
    return completer.future;
  }

  void _onUpdate(TaskUpdate update) {
    final taskId = update.task.taskId;
    // Only handle our own tasks (both transfer and API).
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
        if (completer != null && !completer.isCompleted) {
          completer.complete(_resultFrom(update));
        }
        // Always fire onTaskFinal for recovery, even without a completer.
        final jobId = UploadTaskFactory.jobIdOf(taskId);
        final result = _resultFrom(update);
        final isApi = update.task is DataTask;
        onTaskFinal?.call(
          jobId,
          result.success,
          result.eTag,
          result.urlExpired,
          result.fileUrl,
          isApi,
          update.responseBody,
          result.statusCode,
        );
    }
  }

  PartResult _resultFrom(TaskStatusUpdate update) {
    final taskId = update.task.taskId;
    final code = update.responseStatusCode;

    // API call task (complete or callback) routed through DataTask.
    if (update.task is DataTask) {
      if (update.status == TaskStatus.complete) {
        _taskProgress[taskId] = 1.0;
        _emitJobProgress(UploadTaskFactory.jobIdOf(taskId));
        return PartResult(
          success: true,
          statusCode: code,
          responseBody: update.responseBody,
          // For S3 complete API: extract fileUrl from response JSON.
          fileUrl: _fileUrlFromResponse(update.responseBody),
        );
      }
      final is401 = code == 401;
      return PartResult(
        success: false,
        statusCode: code,
        urlExpired: is401,
        error: update.exception?.description ??
            'API ${update.status.name} (HTTP ${code ?? '—'})',
      );
    }

    // S3 transfer task (UploadTask – direct PUT or multipart part).
    final partNumber = UploadTaskFactory.partNumberOf(taskId);

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

  /// Parse the S3 complete API response JSON to extract the final file URL.
  /// Expected shape: `{"data": {"fileUrl": "https://..."}}` or `{"fileUrl": "https://..."}`.
  String? _fileUrlFromResponse(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map == false) return null;
      // Option A: { data: { fileUrl: '...' } }
      final data = json['data'];
      if (data is Map && data['fileUrl'] is String) return data['fileUrl'] as String;
      // Option B: { fileUrl: '...' }
      if (json['fileUrl'] is String) return json['fileUrl'] as String;
    } catch (_) {}
    return null;
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

  /// Cancel all tasks in [group] without resolving awaiting completers.
  /// Used for cleanup after a job reaches a terminal state.
  Future<void> cancelGroup(String group) async {
    await _fd.cancelAll(group: group);
  }

  /// Remove all progress entries for [jobId] to prevent memory leaks.
  Future<void> clearProgress(String jobId) async {
    final ids = _taskProgress.keys
        .where((k) => UploadTaskFactory.jobIdOf(k) == jobId)
        .toList();
    for (final id in ids) {
      _taskProgress.remove(id);
    }
  }

  Future<void> dispose() async {
    await _updatesSub?.cancel();
    await _enqueueErrSub?.cancel();
  }
}
