import 'dart:async';
import 'dart:io';

import 'package:edtech/app/app.dart';
import 'package:edtech/features/courses/data/models/upload_task.dart'
    show CourseUploadMetadata;
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
    _sub = _service.updates.listen((_) => notifyListeners());
    _service.ensureStarted();
  }

  final UploadService _service;
  StreamSubscription<UploadJob>? _sub;

  /// Maps the app's integer queue ids to internal string job ids.
  final Map<int, String> _intToJob = {};
  final Map<String, int> _jobToInt = {};
  int _nextIntId = 1;

  bool _adding = false;

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
    try {
      if (_hasInFlightFile(file.path)) {
        ToastService.showError('This file is already being uploaded');
        return false;
      }
      if (!await _ensureNotificationPermission()) {
        ToastService.showError('Notification permission required to upload');
        return false;
      }
      final duration = await VideoMetadataHelper.getDurationSeconds(file.path);
      final fileSize = await VideoMetadataHelper.getFileSizeBytes(file.path);
      await _enqueue(
        filePath: file.path,
        type: UploadAssetType.videoPost,
        title: title,
        fileSize: fileSize,
        metadata: {'videoDuration': duration, 'fileSize': fileSize},
      );
      ToastService.showSuccess('Video queued for upload');
      return true;
    } catch (e) {
      AppLogger.e('addToQueue error - $e');
      ToastService.showError('Failed to queue video. Please try again.');
      return false;
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
    if (!await _ensureNotificationPermission()) {
      ToastService.showError('Notification permission required to upload');
      return 0;
    }
    _adding = true;
    try {
      final fileSize = await File(videoPath).length();
      final duration = await VideoMetadataHelper.getDurationSeconds(videoPath);
      final job = await _enqueue(
        filePath: videoPath,
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
    if (!await _ensureNotificationPermission()) {
      ToastService.showError('Notification permission required to upload');
      return 0;
    }
    _adding = true;
    try {
      final fileSize = await File(filePath).length();
      final job = await _enqueue(
        filePath: filePath,
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

  Future<int> addCourseToQueue({
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
    String? introVideoUrl,
  }) async {
    if (_adding) return 0;
    if (_hasInFlightFile(thumbnailPath, type: UploadAssetType.course)) {
      ToastService.showError('This thumbnail is already uploading');
      return 0;
    }
    if (!await _ensureNotificationPermission()) {
      ToastService.showError('Notification permission required to upload');
      return 0;
    }
    _adding = true;
    try {
      final meta = CourseUploadMetadata(
        courseTitle: title,
        shortDescription: shortDescription,
        description: description,
        requirements: requirements,
        language: language,
        level: level,
        type: type,
        price: price,
        videoPath: introVideoUrl != null ? null : videoPath,
      );
      final thumbSize = await File(thumbnailPath).length();
      final job = await _enqueue(
        filePath: thumbnailPath,
        type: UploadAssetType.course,
        title: 'Course: $title',
        fileSize: thumbSize,
        metadata: {...meta.toJson(), 'fileSize': thumbSize},
      );

      if (introVideoUrl == null && videoPath != null) {
        final vSize = await File(videoPath).length();
        await _enqueue(
          filePath: videoPath,
          type: UploadAssetType.courseIntro,
          title: 'Course intro video: $title',
          fileSize: vSize,
          metadata: {'videoPath': videoPath, 'fileSize': vSize},
        );
      }
      ToastService.showSuccess('Course upload queued');
      return _jobToInt[job.id]!;
    } catch (e) {
      AppLogger.e('addCourseToQueue error: $e');
      ToastService.showError('Failed to queue course');
      return 0;
    } finally {
      _adding = false;
    }
  }

  Future<String?> addCourseIntroVideo({
    required String filePath,
    required String title,
  }) async {
    if (_hasInFlightFile(filePath)) {
      ToastService.showError('This video is already queued');
      return null;
    }
    if (!await _ensureNotificationPermission()) {
      ToastService.showError('Notification permission required to upload');
      return null;
    }
    try {
      final fileSize = await File(filePath).length();
      final job = await _enqueue(
        filePath: filePath,
        type: UploadAssetType.courseIntro,
        title: title,
        fileSize: fileSize,
        metadata: {'fileSize': fileSize},
      );
      ToastService.showSuccess('Intro video queued');
      return job.fileUrl;
    } catch (e) {
      AppLogger.e('addCourseIntroVideo error: $e');
      ToastService.showError('Failed to queue intro video');
      return null;
    }
  }

  Future<Map<String, String?>?> queueCourseEditAssets({
    String? thumbnailPath,
    String? videoPath,
    required int courseId,
    required String courseTitle,
  }) async {
    if (thumbnailPath == null && videoPath == null) return {};
    if (!await _ensureNotificationPermission()) {
      ToastService.showError('Notification permission required to upload');
      return null;
    }
    try {
      if (thumbnailPath != null) {
        if (_hasInFlightFile(thumbnailPath, type: UploadAssetType.courseThumb)) {
          ToastService.showError('This thumbnail is already uploading');
          return null;
        }
        final size = await File(thumbnailPath).length();
        await _enqueue(
          filePath: thumbnailPath,
          type: UploadAssetType.courseThumb,
          title: 'Course thumbnail: $courseTitle',
          fileSize: size,
          metadata: {'courseId': courseId},
        );
      }
      if (videoPath != null) {
        if (_hasInFlightFile(videoPath, type: UploadAssetType.courseIntro)) {
          ToastService.showError('This intro video is already uploading');
          return null;
        }
        final size = await File(videoPath).length();
        await _enqueue(
          filePath: videoPath,
          type: UploadAssetType.courseIntro,
          title: 'Course intro: $courseTitle',
          fileSize: size,
          metadata: {'courseId': courseId},
        );
      }
      ToastService.showSuccess('Assets queued for upload');
      return {};
    } catch (e) {
      AppLogger.e('queueCourseEditAssets error: $e');
      ToastService.showError('Failed to queue course assets');
      return null;
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
      if (File(j.filePath).absolute.path != normalized) return false;
      if (UploadState.from(j.state) == UploadState.completed ||
          UploadState.from(j.state) == UploadState.failed ||
          UploadState.from(j.state) == UploadState.cancelled) {
        return false;
      }
      if (type != null && j.type != type) return false;
      return true;
    });
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
