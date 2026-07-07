import 'dart:async';
import 'dart:io';

import 'package:edtech/app/app.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/features/courses/data/helpers/video_metadata_helper.dart';
import 'package:edtech/features/courses/data/models/upload_task.dart';
import 'package:edtech/features/courses/services/native_background_engine.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:upload_queue/upload_queue.dart';

class UnifiedUploadQueueProvider extends ChangeNotifier {
  late final UploadQueue _queue;
  NativeBackgroundEngine? _nativeEngine;
  StreamSubscription? _updateSub;
  bool _adding = false;

  List<UploadTask> get tasks => _queue.tasks;
  int? get activeUploadId {
    final uploading = _queue.tasks
        .where((t) => t.state == UploadState.uploading)
        .firstOrNull;
    return uploading?.id;
  }

  double get activeUploadProgress {
    final uploading = _queue.tasks
        .where((t) => t.state == UploadState.uploading)
        .firstOrNull;
    return uploading?.progress ?? 0.0;
  }

  int get pendingCount =>
      _queue.tasks.where((t) => t.state == UploadState.pending).length;

  int get completedCount =>
      _queue.tasks.where((t) => t.state == UploadState.completed).length;

  int get failedCount =>
      _queue.tasks.where((t) => t.state == UploadState.failed).length;

  UploadQueue get queue => _queue;

  /// The native engine, if running on a mobile platform. Exposed so callers
  /// can query background upload status after process death.
  NativeBackgroundEngine? get nativeEngine => _nativeEngine;

  /// Tracks which asset section to extract from the combined course response.
  /// Set by [_buildInitBody] before the init request, read by [_parseInitResponse].
  String? _pendingCourseAssetKey;

  UnifiedUploadQueueProvider() {
    _init();
  }

  /// Absolute paths of app-owned temp/cache directories. A source file is only
  /// deleted after upload if it lives under one of these (e.g. an image_picker
  /// copy), never an original user file elsewhere.
  final List<String> _deletableRoots = [];

  Future<void> _resolveDeletableRoots() async {
    try {
      final tmp = await getTemporaryDirectory();
      _deletableRoots.add(tmp.path);
      final support = await getApplicationSupportDirectory();
      _deletableRoots.add(support.path);
    } catch (_) {}
  }

  bool _shouldDeleteSourceOnComplete(UploadTask task) {
    if (_deletableRoots.isEmpty) return false;
    final path = File(task.filePath).absolute.path;
    return _deletableRoots.any((root) => path.startsWith(root));
  }

  Future<void> _init() async {
    await _resolveDeletableRoots();
    final config = UploadConfig(
      initUploadEndpoint: Urls.courseModuleUploadUrl,
      tokenProvider: () => AuthController.accessToken ?? '',
      refreshTokenProvider: () => AuthController.userModel?.refreshToken ?? '',
      refreshEndpoint: Urls.refreshTokenUrl,
      buildInitEndpoint: (metadata) =>
          metadata?['initEndpoint'] as String? ?? Urls.courseModuleUploadUrl,
      buildInitBody: _buildInitBody,
      parseInitResponse: _parseInitResponse,
      parseCompleteResponse: _parseCompleteResponse,
      buildCompleteExtraFields: _buildCompleteExtraFields,
      buildCompleteEndpoint: (_) => Urls.uploadCompleteUrl,
      buildAbortEndpoint: (_) => Urls.uploadAbortUrl,
      buildCallback: _buildCallback,
      shouldDeleteSourceOnComplete: _shouldDeleteSourceOnComplete,
      logger: (msg) => AppLogger.i(msg, tag: 'UploadQueue'),
    );

    UploadEngine engine;
    if (Platform.isAndroid || Platform.isIOS) {
      engine = NativeBackgroundEngine(config);
      _nativeEngine = engine as NativeBackgroundEngine;
    } else {
      engine = DartHttpEngine(config);
    }

    _queue = UploadQueue(config: engine.config, engine: engine);
    _updateSub = _queue.onUpdate.listen((_) => notifyListeners());
  }

  @override
  Future<void> dispose() async {
    _updateSub?.cancel();
    await _queue.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────
  //  Init Body Builder (per upload type)
  // ──────────────────────────────────────────────

  Map<String, dynamic> _buildInitBody(
    String fileName,
    Map<String, dynamic>? extraFields,
  ) {
    final type = extraFields?['uploadType'] as String? ?? 'video_post';
    switch (type) {
      case 'course':
      case 'course_thumb':
        _pendingCourseAssetKey = 'thumbnail';
        return {
          'thumbnailFilename': fileName,
          'thumbnailContentType': _inferImageContentType(fileName),
          if (extraFields?['fileSize'] != null)
            'thumbnailFileSize': extraFields!['fileSize'],
        };
      case 'course_intro':
        _pendingCourseAssetKey = 'video';
        return {
          'thumbnailFilename': 'keep.jpg',
          'thumbnailContentType': 'image/jpeg',
          'thumbnailFileSize': 0,
          'videoFilename': fileName,
          'videoContentType': _inferVideoContentType(fileName),
          if (extraFields?['fileSize'] != null)
            'videoFileSize': extraFields!['fileSize'],
        };
      case 'module_lesson':
        return {
          'videoFilename': fileName,
          'videoContentType': _inferVideoContentType(fileName),
          'videoFileSize': extraFields?['fileSize'] ?? 0,
          if (extraFields?['moduleId'] != null)
            'moduleID': extraFields!['moduleId'],
        };
      case 'resource':
        final ct =
            extraFields?['contentType'] as String? ??
            'application/octet-stream';
        return {'filename': fileName, 'contentType': ct};
      default: // video_post
        return {
          'videoFilename': fileName,
          'videoContentType': _inferVideoContentType(fileName),
          if (extraFields?['fileSize'] != null)
            'videoFileSize': extraFields!['fileSize'],
        };
    }
  }

  // ──────────────────────────────────────────────
  //  Response Parsers (handles nested course format)
  // ──────────────────────────────────────────────

  InitUploadResponse _parseInitResponse(Map<String, dynamic> json) {
    final d = json['data'] is Map ? json['data'] as Map<String, dynamic> : json;
    final nested = d['data'] as Map<String, dynamic>?;
    if (nested != null &&
        (nested.containsKey('thumbnail') || nested.containsKey('video'))) {
      final section =
          nested[_pendingCourseAssetKey ?? 'thumbnail']
              as Map<String, dynamic>?;
      if (section != null) return InitUploadResponse.fromJson(section);
    }
    return InitUploadResponse.fromJson(json);
  }

  String? _parseCompleteResponse(Map<String, dynamic> json) {
    final d = json['data'] is Map ? json['data'] as Map<String, dynamic> : json;
    return d['fileUrl'] as String?;
  }

  // ──────────────────────────────────────────────
  //  Complete-Multipart Extra Fields
  //  The shared /video-post/upload/complete endpoint expects exactly
  //  {key, uploadId, parts}. The `key` is injected by the queue from the
  //  persisted S3 key, so no per-type extras are needed here. Kept as a hook
  //  in case a future asset type needs additional context on completion.
  // ──────────────────────────────────────────────

  Map<String, dynamic> _buildCompleteExtraFields(UploadTask task) => const {};

  // ──────────────────────────────────────────────
  //  Callback Builder (per upload type)
  // ──────────────────────────────────────────────

  CallbackRequest _buildCallback(UploadTask task) {
    final type = task.metadata?['uploadType'] as String? ?? 'video_post';
    final idempotencyKey = '${task.id}_callback';
    switch (type) {
      case 'course':
        return CallbackRequest(
          url: Urls.createCourseUrl,
          body: {
            'title': task.metadata?['courseTitle'] ?? task.title,
            'description': task.metadata?['description'] ?? '',
            'shortDescription': task.metadata?['shortDescription'] ?? '',
            'requirements': task.metadata?['requirements'] ?? '',
            'thumbnailUrl': task.fileUrl,
            if (task.metadata?['videoPath'] != null)
              'introVideoUrl': task.metadata!['videoPath'],
            'language': task.metadata?['language'] ?? '',
            'level': (task.metadata?['level'] ?? '').toString().toUpperCase(),
            'type': (task.metadata?['type'] ?? 'FREE').toString().toUpperCase(),
            'price': task.metadata?['price'] ?? 0,
          },
          idempotencyKey: idempotencyKey,
        );
      case 'module_lesson':
        return CallbackRequest(
          url: Urls.courseModuleLessonUrl,
          body: {
            'title': task.metadata?['lessonTitle'] ?? task.title,
            'moduleId': task.metadata?['moduleId'],
            'videoUrl': task.fileUrl,
            'duration': task.metadata?['videoDuration'] ?? 0,
            'fileSize': task.metadata?['fileSize'] ?? 0,
          },
          idempotencyKey: idempotencyKey,
        );
      case 'resource':
        return CallbackRequest(
          url: Urls.courseModuleResourceUrl,
          body: {
            'title': task.metadata?['lessonTitle'] ?? task.title,
            'fileUrl': task.fileUrl,
            'moduleId': task.metadata?['moduleId'],
            'fileType':
                task.metadata?['contentType'] ?? 'application/octet-stream',
            'fileSize': task.metadata?['fileSize'] ?? 0,
          },
          idempotencyKey: idempotencyKey,
        );
      case 'course_intro':
        return CallbackRequest(
          url: Urls.courseAssetsUploadUrl,
          body: {'title': task.title, 'videoUrl': task.fileUrl},
          idempotencyKey: idempotencyKey,
        );
      default: // video_post
        return CallbackRequest(
          url: Urls.videoPostUrl,
          body: {
            'title': task.title,
            'videoUrl': task.fileUrl,
            'duration': task.metadata?['videoDuration'] ?? 0,
            'fileSize': task.metadata?['fileSize'] ?? 0,
          },
          idempotencyKey: idempotencyKey,
        );
    }
  }

  // ──────────────────────────────────────────────
  //  Public Queue Methods
  // ──────────────────────────────────────────────

  Future<bool> addToQueue(File file, String title) async {
    debugPrint('[addToQueue] start file=${file.path} title=$title');
    try {
      if (await _hasInFlightFile(file.path)) {
        debugPrint('[addToQueue] file already in flight');
        ToastService.showError('This file is already being uploaded');
        return false;
      }
      debugPrint('[addToQueue] no duplicate found');

      final duration = await VideoMetadataHelper.getDurationSeconds(file.path);
      final fileSize = await VideoMetadataHelper.getFileSizeBytes(file.path);
      debugPrint('[addToQueue] duration=$duration fileSize=$fileSize');

      final permission = await _ensureNotificationPermission();
      debugPrint('[addToQueue] notification permission=$permission');
      if (!permission) {
        ToastService.showError('Notification permission required to upload');
        return false;
      }

      debugPrint('[addToQueue] calling _queue.add()');
      await _queue.add(
        file: file,
        title: title,
        metadata: {
          'uploadType': 'video_post',
          'videoDuration': duration,
          'fileSize': fileSize,
          'initEndpoint': Urls.videoPostAssetsUploadUrl,
        },
      );
      debugPrint('[addToQueue] _queue.add() completed');
      ToastService.showSuccess('Video queued for upload');
      return true;
    } catch (e) {
      debugPrint('[addToQueue] exception: $e');
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
    debugPrint(
      '[addModuleLessonToQueue] start path=$videoPath title=$lessonTitle moduleId=$moduleId',
    );
    try {
      if (_adding) {
        debugPrint('[addModuleLessonToQueue] _adding=true, returning 0');
        return 0;
      }
      if (!File(videoPath).existsSync()) {
        debugPrint('[addModuleLessonToQueue] file not found: $videoPath');
        ToastService.showError('Video file not found');
        return 0;
      }
      debugPrint('[addModuleLessonToQueue] file exists');

      if (await _hasInFlightFile(videoPath, uploadType: 'module_lesson')) {
        debugPrint('[addModuleLessonToQueue] file already in flight');
        ToastService.showError('This video is already in the upload queue');
        return 0;
      }
      debugPrint('[addModuleLessonToQueue] no duplicate');

      final permission = await _ensureNotificationPermission();
      debugPrint(
        '[addModuleLessonToQueue] notification permission=$permission',
      );
      if (!permission) {
        ToastService.showError('Notification permission required to upload');
        return 0;
      }

      if (await _hasInFlightFile(videoPath, uploadType: 'module_lesson')) {
        debugPrint('[addModuleLessonToQueue] file already in flight (check 2)');
        ToastService.showError('This video is already in the upload queue');
        return 0;
      }

      _adding = true;
      final videoFile = File(videoPath);
      final fileSize = await videoFile.length();
      final duration = await VideoMetadataHelper.getDurationSeconds(videoPath);
      debugPrint(
        '[addModuleLessonToQueue] fileSize=$fileSize duration=$duration',
      );

      debugPrint('[addModuleLessonToQueue] calling _queue.add()');
      final task = await _queue.add(
        file: videoFile,
        title: lessonTitle,
        metadata: {
          'uploadType': 'module_lesson',
          'moduleId': moduleId,
          'courseId': courseId,
          'lessonId': lessonId,
          'lessonTitle': lessonTitle,
          'videoDuration': duration,
          'fileSize': fileSize,
          'initEndpoint': Urls.courseModuleUploadUrl,
        },
      );
      debugPrint(
        '[addModuleLessonToQueue] _queue.add() returned task.id=${task.id}',
      );
      ToastService.showSuccess('Your video is being uploaded');
      return task.id;
    } catch (e) {
      debugPrint('[addModuleLessonToQueue] exception: $e');
      AppLogger.e('addModuleLessonToQueue error: $e');
      ToastService.showError('Failed to queue video lesson');
      return 0;
    } finally {
      _adding = false;
      debugPrint('[addModuleLessonToQueue] finished');
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
    try {
      if (_adding) return 0;
      if (!File(filePath).existsSync()) {
        ToastService.showError('Resource file not found');
        return 0;
      }

      if (await _hasInFlightFile(filePath, uploadType: 'resource')) {
        ToastService.showError('This resource is already in the upload');
        return 0;
      }

      final permission = await _ensureNotificationPermission();
      if (!permission) {
        ToastService.showError('Notification permission required to upload');
        return 0;
      }

      if (await _hasInFlightFile(filePath, uploadType: 'resource')) {
        ToastService.showError('This resource is already in the upload');
        return 0;
      }

      _adding = true;
      final resourceFile = File(filePath);
      final fileSize = await resourceFile.length();

      final task = await _queue.add(
        file: resourceFile,
        title: lessonTitle,
        metadata: {
          'uploadType': 'resource',
          'moduleId': moduleId,
          'courseId': courseId,
          'lessonId': lessonId,
          'lessonTitle': lessonTitle,
          'contentType': contentType,
          'fileSize': fileSize,
          'initEndpoint': Urls.courseModuleResourceUploadUrl,
        },
      );
      ToastService.showSuccess('Your Resource is being uploaded');
      return task.id;
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
    try {
      if (_adding) return 0;

      if (await _hasInFlightFile(thumbnailPath, uploadType: 'course')) {
        ToastService.showError('This thumbnail is already uploading');
        return 0;
      }

      final permission = await _ensureNotificationPermission();
      if (!permission) {
        ToastService.showError('Notification permission required to upload');
        return 0;
      }

      if (await _hasInFlightFile(thumbnailPath, uploadType: 'course')) {
        ToastService.showError('This thumbnail is already uploading');
        return 0;
      }

      _adding = true;
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

      final thumbFile = File(thumbnailPath);
      final thumbSize = await thumbFile.length();

      final task = await _queue.add(
        file: thumbFile,
        title: 'Course: $title',
        metadata: {
          'uploadType': 'course',
          ...meta.toJson(),
          'fileSize': thumbSize,
          'initEndpoint': Urls.courseAssetsUploadUrl,
        },
      );
      final id = task.id;

      if (introVideoUrl == null && videoPath != null) {
        await _queue.add(
          file: File(videoPath),
          title: 'Course intro video: $title',
          metadata: {
            'uploadType': 'course_intro',
            'videoPath': videoPath,
            'initEndpoint': Urls.courseAssetsUploadUrl,
          },
        );
      }

      ToastService.showSuccess('Course upload queued');
      return id;
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
    try {
      if (await _hasInFlightFile(filePath)) {
        ToastService.showError('This video is already queued');
        return null;
      }

      final permission = await _ensureNotificationPermission();
      if (!permission) {
        ToastService.showError('Notification permission required to upload');
        return null;
      }

      final file = File(filePath);
      final fileSize = await file.length();

      final task = await _queue.add(
        file: file,
        title: title,
        metadata: {
          'uploadType': 'course_intro',
          'fileSize': fileSize,
          'initEndpoint': Urls.courseAssetsUploadUrl,
        },
      );
      ToastService.showSuccess('Intro video queued');
      return task.fileUrl;
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

    try {
      final permission = await _ensureNotificationPermission();
      if (!permission) {
        ToastService.showError('Notification permission required to upload');
        return null;
      }

      if (thumbnailPath != null) {
        if (await _hasInFlightFile(thumbnailPath, uploadType: 'course_thumb')) {
          ToastService.showError('This thumbnail is already uploading');
          return null;
        }
        final thumbFile = File(thumbnailPath);
        await _queue.add(
          file: thumbFile,
          title: 'Course thumbnail: $courseTitle',
          metadata: {
            'uploadType': 'course_thumb',
            'initEndpoint': Urls.courseAssetsUploadUrl,
          },
        );
      }

      if (videoPath != null) {
        if (await _hasInFlightFile(videoPath, uploadType: 'course_intro')) {
          ToastService.showError('This intro video is already uploading');
          return null;
        }
        final videoFile = File(videoPath);
        await _queue.add(
          file: videoFile,
          title: 'Course intro: $courseTitle',
          metadata: {
            'uploadType': 'course_intro',
            'initEndpoint': Urls.courseAssetsUploadUrl,
          },
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

  Future<void> cancelTask(int queueId) async {
    await _queue.cancel(queueId);
    ToastService.showInfo('Upload cancelled');
  }

  Future<void> retryFailed(int queueId) async {
    await _queue.retry(queueId);
    ToastService.showInfo('Retrying upload');
  }

  Future<void> removeTask(int queueId) async {
    await _queue.remove(queueId);
  }

  Future<void> pauseQueue() async {
    ToastService.showInfo(
      'Resource management handled by system notifications',
    );
  }

  Future<void> resumeQueue() async {
    ToastService.showInfo('Upload assets resumed');
  }

  // ──────────────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────────────

  Future<bool> _hasInFlightFile(String filePath, {String? uploadType}) async {
    final normalized = File(filePath).absolute.path;
    return _queue.tasks.any((t) {
      if (File(t.filePath).absolute.path != normalized) return false;
      if (t.state == UploadState.completed ||
          t.state == UploadState.failed ||
          t.state == UploadState.cancelled) {
        return false;
      }
      if (uploadType != null && t.metadata?['uploadType'] != uploadType) {
        return false;
      }
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

    final shouldRetry = await _showPermissionDialog(
      title: 'Notification Permission Required',
      content:
          'Background uploads need notification permission to show progress and keep the upload alive.',
      confirmText: 'Grant',
      cancelText: 'Not Now',
    );
    if (shouldRetry != true) return false;

    final second =
        await UploadNotificationService.requestNotificationPermission();
    if (second) return true;

    final openSettings = await _showPermissionDialog(
      title: 'Permission Permanently Denied',
      content:
          'Please enable notifications in System Settings to use background uploads.',
      confirmText: 'Open Settings',
      cancelText: 'Cancel',
    );
    if (openSettings == true) {
      await _openNotificationSettings();
    }
    return false;
  }

  Future<void> _openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    const url = 'android.settings.APPLICATION_DETAILS_SETTINGS';
    try {
      final exec = Platform.resolvedExecutable;
      final segments = exec.split('/');
      String? packageName;
      for (final segment in segments.reversed) {
        if (segment.contains('.') && !segment.startsWith('~~')) {
          packageName = segment.split('-').first;
          break;
        }
      }
      if (packageName != null && packageName.isNotEmpty) {
        await Process.run('am', [
          'start',
          '-a',
          url,
          '-d',
          'package:$packageName',
        ]);
      }
    } catch (e) {
      AppLogger.e('_openNotificationSettings error: $e');
    }
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

  String _inferVideoContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
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

  String _inferImageContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
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
}
