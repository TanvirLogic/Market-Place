import 'dart:async';
import 'dart:io';

import 'package:edtech/app/app.dart';
import 'package:edtech/features/courses/data/helpers/video_metadata_helper.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:flutter/material.dart';

import '../data/models/upload_enums.dart';
import '../data/models/upload_job.dart';
import '../service/upload_service.dart';

/// UI-facing state names, kept compatible with the previous `UploadState` enum
/// (`pending`, `uploading`, `completed`, `failed`, `cancelled`) so existing
/// screens continue to work unchanged.
enum UploadState {
  pending,
  uploading,
  completed,
  failed,
  cancelled;

  static UploadState from(UploadJobState s) {
    switch (s) {
      case UploadJobState.pending:
        return UploadState.pending;
      case UploadJobState.uploading:
      case UploadJobState.completing:
      case UploadJobState.callback:
        return UploadState.uploading;
      case UploadJobState.completed:
        return UploadState.completed;
      case UploadJobState.failed:
        return UploadState.failed;
      case UploadJobState.cancelled:
        return UploadState.cancelled;
    }
  }
}

/// Immutable snapshot of an upload for the UI. Mirrors the fields the old
/// `UploadTask` exposed so widgets/providers keep compiling.
class UploadTaskView {
  final int id;
  final UploadState state;
  final double progress;
  final String title;
  final String filePath;
  final String? fileUrl;
  final Map<String, dynamic>? metadata;

  const UploadTaskView({
    required this.id,
    required this.state,
    required this.progress,
    required this.title,
    required this.filePath,
    required this.fileUrl,
    required this.metadata,
  });
}

/// Drop-in replacement for the previous `UnifiedUploadQueueProvider`, backed by
/// the new `background_downloader`-based [UploadService]. Exposes the same
/// public API the app already calls.
class UploadQueueProvider extends ChangeNotifier {
  UploadQueueProvider({UploadService? service})
      : _service = service ?? UploadService() {
    _sub = _service.updates.listen(_onJobUpdate);
    _service.ensureStarted();
  }

  final UploadService _service;
  StreamSubscription<UploadJob>? _sub;

  /// Maps the app's integer queue ids to internal string job ids.
  final Map<int, String> _intToJob = {};
  final Map<String, int> _jobToInt = {};
  int _nextIntId = 1;

  bool _adding = false;

  void _onJobUpdate(UploadJob job) {
    // Register unknown job IDs (e.g., from recovery) off the stream.
    if (!_jobToInt.containsKey(job.id)) {
      final intId = _nextIntId++;
      _intToJob[intId] = job.id;
      _jobToInt[job.id] = intId;
    }
    // Note: upload notifications are shown natively by background_downloader
    // (configured in BackgroundUploadEngine) so the progress notification
    // survives app kill. We intentionally do NOT show Dart-side notifications
    // here — doing so produced duplicate entries in the system tray.
    // Service auto-removes failed jobs from everywhere; keep our mappings in sync.
    if (job.state == UploadJobState.failed) {
      final intId = _jobToInt.remove(job.id);
      if (intId != null) _intToJob.remove(intId);
    }
    notifyListeners();
  }

  // ── Compatibility getters ─────────────────────────────────────────────

  List<UploadTaskView> get tasks =>
      _service.jobs.map(_view).toList();

  int? get activeUploadId {
    final job = _service.jobs
        .where((j) => UploadState.from(j.state) == UploadState.uploading)
        .firstOrNull;
    return job == null ? null : _jobToInt[job.id];
  }

  double get activeUploadProgress {
    final job = _service.jobs
        .where((j) => UploadState.from(j.state) == UploadState.uploading)
        .firstOrNull;
    return job?.progress ?? 0.0;
  }

  int get pendingCount => _service.jobs
      .where((j) => UploadState.from(j.state) == UploadState.pending)
      .length;

  int get completedCount => _service.jobs
      .where((j) => UploadState.from(j.state) == UploadState.completed)
      .length;

  int get failedCount => _service.jobs
      .where((j) => UploadState.from(j.state) == UploadState.failed)
      .length;

  // ── Public queue methods (same signatures as before) ──────────────────

  Future<bool> addToQueue(File file, String title) async {
    if (_adding) return false;
    if (_hasInFlightFile(file.path)) {
      ToastService.showError('This file is already being uploaded');
      return false;
    }
    _adding = true;
    try {
      if (!await _ensureNotificationPermission()) {
        ToastService.showError('Notification permission required to upload');
        return false;
      }
      final localPath = await _copyToAppCache(file.path);
      if (localPath == null) {
        ToastService.showError('Failed to access video file');
        return false;
      }
      final duration = await VideoMetadataHelper.getDurationSeconds(localPath);
      final fileSize = await VideoMetadataHelper.getFileSizeBytes(localPath);
      await _enqueue(
        filePath: localPath,
        type: UploadAssetType.videoPost,
        title: title,
        fileSize: fileSize,
        metadata: {
          'videoDuration': duration,
          'fileSize': fileSize,
          'originalPath': file.path,
        },
      );
      ToastService.showSuccess('Video queued for upload');
      return true;
    } catch (e) {
      AppLogger.e('addToQueue error - $e');
      ToastService.showError('Failed to queue video. Please try again.');
      return false;
    } finally {
      _adding = false;
    }
  }

  Future<int> addModuleLessonToQueue({
    required String videoPath,
    required String lessonTitle,
    required int moduleId,
    required int courseId,
    int? lessonId,
  }) async {
    if (_adding) return 0;
    if (!File(videoPath).existsSync()) {
      ToastService.showError('Video file not found');
      return 0;
    }
    if (_hasInFlightFile(videoPath, type: UploadAssetType.moduleLesson)) {
      ToastService.showError('This video is already in the upload queue');
      return 0;
    }
    _adding = true;
    try {
      if (!await _ensureNotificationPermission()) {
        ToastService.showError('Notification permission required to upload');
        return 0;
      }
      // Copy file to app-local temp to ensure native service can access it,
      // even when the original path is a content:// URI from image_picker.
      final localPath = await _copyToAppCache(videoPath);
      if (localPath == null) {
        ToastService.showError('Failed to access video file');
        return 0;
      }
      final fileSize = await File(localPath).length();
      final duration = await VideoMetadataHelper.getDurationSeconds(localPath);
      final job = await _enqueue(
        filePath: localPath,
        type: UploadAssetType.moduleLesson,
        title: lessonTitle,
        fileSize: fileSize,
        metadata: {
          'moduleId': moduleId,
          'courseId': courseId,
          'lessonId': lessonId,
          'lessonTitle': lessonTitle,
          'videoDuration': duration,
          'fileSize': fileSize,
          'originalPath': videoPath,
        },
      );
      ToastService.showSuccess('Your video is being uploaded');
      return _jobToInt[job.id]!;
    } catch (e) {
      AppLogger.e('addModuleLessonToQueue error: $e');
      ToastService.showError('Failed to queue video lesson');
      return 0;
    } finally {
      _adding = false;
    }
  }

  Future<int> addResourceToQueue({
    required String filePath,
    required String lessonTitle,
    required int moduleId,
    required int courseId,
    required String contentType,
    int? lessonId,
  }) async {
    if (_adding) return 0;
    if (!File(filePath).existsSync()) {
      ToastService.showError('Resource file not found');
      return 0;
    }
    if (_hasInFlightFile(filePath, type: UploadAssetType.resource)) {
      ToastService.showError('This resource is already in the upload');
      return 0;
    }
    _adding = true;
    try {
      if (!await _ensureNotificationPermission()) {
        ToastService.showError('Notification permission required to upload');
        return 0;
      }
      final localPath = await _copyToAppCache(filePath);
      if (localPath == null) {
        ToastService.showError('Failed to access resource file');
        return 0;
      }
      final fileSize = await File(localPath).length();
      final job = await _enqueue(
        filePath: localPath,
        type: UploadAssetType.resource,
        title: lessonTitle,
        fileSize: fileSize,
        metadata: {
          'moduleId': moduleId,
          'courseId': courseId,
          'lessonId': lessonId,
          'lessonTitle': lessonTitle,
          'contentType': contentType,
          'fileSize': fileSize,
          'originalPath': filePath,
        },
      );
      ToastService.showSuccess('Your Resource is being uploaded');
      return _jobToInt[job.id]!;
    } catch (e) {
      AppLogger.e('addResourceToQueue error: $e');
      ToastService.showError('Failed to queue resource');
      return 0;
    } finally {
      _adding = false;
    }
  }

  /// Upload new thumbnail/video for an existing course and return their CDN
  /// URLs. Awaits the full upload (init → transfer → complete) so the caller
  /// can include the new URLs in the PUT /course body.
  Future<Map<String, String?>?> updateCourseAssets({
    String? thumbnailPath,
    String? videoPath,
    required int courseId,
    required String courseTitle,
  }) async {
    if (thumbnailPath == null && videoPath == null) return {};
    if (_adding) return null;
    _adding = true;
    try {
      if (!await _ensureNotificationPermission()) {
        ToastService.showError('Notification permission required to upload');
        return null;
      }
      final thumbSize = thumbnailPath != null
          ? await File(thumbnailPath).length()
          : null;
      final videoSize = videoPath != null
          ? await File(videoPath).length()
          : null;

      final intId = _nextIntId++;
      final jobId = 'edit_course_${DateTime.now().millisecondsSinceEpoch}_$intId';

      final urls = await _service.uploadCourseAssets(
        id: jobId,
        thumbnailPath: thumbnailPath,
        videoPath: videoPath,
        thumbnailFileSize: thumbSize,
        videoFileSize: videoSize,
      );

      if (urls == null) {
        ToastService.showError('Failed to upload course assets');
        return null;
      }

      return urls;
    } catch (e) {
      AppLogger.e('updateCourseAssets error: $e');
      ToastService.showError('Failed to upload course assets');
      return null;
    } finally {
      _adding = false;
    }
  }

  /// Upload an image (avatar/cover) and await completion. Returns the final
  /// file URL, or null on failure. Used by the profile image providers.
  Future<String?> uploadImageSync({
    required String filePath,
    required UploadAssetType type,
    required String title,
  }) async {
    final fileSize = await File(filePath).length();
    final job = await _enqueue(
      filePath: filePath,
      type: type,
      title: title,
      fileSize: fileSize,
      metadata: {'fileSize': fileSize},
    );
    // Await terminal state.
    await for (final j in _service.updates) {
      if (j.id != job.id) continue;
      if (j.state == UploadJobState.completed) return j.fileUrl;
      if (j.state == UploadJobState.failed ||
          j.state == UploadJobState.cancelled) {
        return null;
      }
    }
    return _service.job(job.id)?.fileUrl;
  }

  /// Combined course creation — single init, upload both thumb + optional
  /// video, then POST to `/course` with all data. Returns the queue id (> 0)
  /// on success, or 0 on failure.
  Future<int> createCourse({
    required String thumbnailPath,
    String? videoPath,
    required String title,
    required String shortDescription,
    required String description,
    required String requirements,
    required String language,
    required String level,
    required String type,
    required double price,
  }) async {
    if (_adding) return 0;
    if (!File(thumbnailPath).existsSync()) {
      ToastService.showError('Thumbnail file not found');
      return 0;
    }
    _adding = true;
    try {
      if (!await _ensureNotificationPermission()) {
        ToastService.showError('Notification permission required to upload');
        return 0;
      }
      final intId = _nextIntId++;
      final jobId = 'course_${DateTime.now().millisecondsSinceEpoch}_$intId';
      final thumbSize = await File(thumbnailPath).length();
      final videoSize = videoPath != null
          ? await File(videoPath).length()
          : null;

      final job = await _service.createCourse(
        id: jobId,
        thumbnailPath: thumbnailPath,
        videoPath: videoPath,
        thumbnailFileSize: thumbSize,
        videoFileSize: videoSize,
        title: title,
        shortDescription: shortDescription,
        description: description,
        requirements: requirements,
        language: language,
        level: level,
        type: type,
        price: price,
      );

      // Register both thumb and video sub-job ids for notification tracking.
      _intToJob[intId] = job.id;
      _jobToInt[job.id] = intId;

      if (job.state == UploadJobState.completed) {
        ToastService.showSuccess('Course created successfully!');
        return intId;
      }
      AppLogger.e('createCourse failed: ${job.error}');
      ToastService.showError(job.error ?? 'Failed to create course');
      return 0;
    } catch (e) {
      AppLogger.e('createCourse error: $e');
      ToastService.showError('Failed to create course');
      return 0;
    } finally {
      _adding = false;
    }
  }

  Future<void> cancelTask(int queueId) async {
    final jobId = _intToJob[queueId];
    if (jobId != null) await _service.cancel(jobId);
    ToastService.showInfo('Upload cancelled');
  }

  Future<void> retryFailed(int queueId) async {
    final jobId = _intToJob[queueId];
    if (jobId != null) await _service.retry(jobId);
    ToastService.showInfo('Retrying upload');
  }

  Future<void> removeTask(int queueId) async {
    final jobId = _intToJob[queueId];
    if (jobId != null) {
      _service.remove(jobId);
      _intToJob.remove(queueId);
      _jobToInt.remove(jobId);
      notifyListeners();
    }
  }

  Future<void> pauseQueue() async {
    ToastService.showInfo('Resource management handled by system notifications');
  }

  Future<void> resumeQueue() async {
    ToastService.showInfo('Upload assets resumed');
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<UploadJob> _enqueue({
    required String filePath,
    required UploadAssetType type,
    required String title,
    required int fileSize,
    Map<String, dynamic> metadata = const {},
  }) async {
    final intId = _nextIntId++;
    final jobId = 'job_${DateTime.now().millisecondsSinceEpoch}_$intId';
    _intToJob[intId] = jobId;
    _jobToInt[jobId] = intId;
    return _service.enqueue(
      id: jobId,
      filePath: filePath,
      type: type,
      title: title,
      fileSize: fileSize,
      metadata: {...metadata, 'uploadType': type.wire},
    );
  }

  UploadTaskView _view(UploadJob j) => UploadTaskView(
        id: _jobToInt[j.id] ?? 0,
        state: UploadState.from(j.state),
        progress: j.progress,
        title: j.title,
        filePath: j.filePath,
        fileUrl: j.fileUrl,
        metadata: j.metadata,
      );

  bool _hasInFlightFile(String filePath, {UploadAssetType? type}) {
    final normalized = File(filePath).absolute.path;
    return _service.jobs.any((j) {
      // Check both the job's current filePath and the original path from
      // metadata (in case the file was copied to app cache).
      final jobPath = File(j.filePath).absolute.path;
      final originalPath = j.metadata['originalPath'] as String?;
      final jobOriginalPath = originalPath != null ? File(originalPath).absolute.path : null;
      final matches = jobPath == normalized || (jobOriginalPath != null && jobOriginalPath == normalized);
      if (!matches) return false;
      if (UploadState.from(j.state) == UploadState.completed ||
          UploadState.from(j.state) == UploadState.failed ||
          UploadState.from(j.state) == UploadState.cancelled) {
        return false;
      }
      if (type != null && j.type != type) return false;
      return true;
    });
  }

  /// Copy [sourcePath] to the app's cache directory and return the local path.
  /// On Android this ensures the native foreground service can access the file
  /// even when the original path is a content:// URI. Returns null on failure.
  Future<String?> _copyToAppCache(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      // Use a stable name based on the original path so the same file isn't
      // copied repeatedly on recovery.
      final hash = sourcePath.hashCode.toString();
      final ext = sourcePath.contains('.')
          ? '.${sourcePath.split('.').last}'
          : '.mp4';
      final dir = Directory.systemTemp;
      final target = File('${dir.path}/eduverse_upload_$hash$ext');
      if (await target.exists()) {
        // Already cached — verify it's still valid.
        if (await target.length() == await source.length()) {
          return target.path;
        }
        await target.delete();
      }
      await source.copy(target.path);
      return target.path;
    } catch (e) {
      AppLogger.e('_copyToAppCache error: $e');
      return null;
    }
  }

  Future<bool> _ensureNotificationPermission() async {
    if (await UploadNotificationService.hasNotificationPermission()) {
      return true;
    }
    final first =
        await UploadNotificationService.requestNotificationPermission();
    if (first) return true;

    final retry = await _showPermissionDialog(
      title: 'Notification Permission Required',
      content:
          'Background uploads need notification permission to show progress and keep the upload alive.',
      confirmText: 'Grant',
      cancelText: 'Not Now',
    );
    if (retry != true) return false;
    return UploadNotificationService.requestNotificationPermission();
  }

  Future<bool?> _showPermissionDialog({
    required String title,
    required String content,
    required String confirmText,
    required String cancelText,
  }) {
    final ctx = App.navigatorKey.currentContext;
    if (ctx == null) return Future.value(false);
    return showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
