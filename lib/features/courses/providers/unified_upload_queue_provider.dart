import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edtech/app/app.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/features/courses/data/helpers/video_metadata_helper.dart';
import 'package:edtech/features/courses/data/models/upload_task.dart';
import 'package:edtech/features/courses/data/repositories/upload_queue_repository.dart';
import 'package:edtech/features/courses/services/background_upload_service.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/native_upload_bridge.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:edtech/global/core/services/upload_path_storage.dart';
import 'package:flutter/material.dart';

class UnifiedUploadQueueProvider extends ChangeNotifier {
  List<UploadQueueItem> _queue = [];
  UploadQueueItem? _activeItem;
  int _activeProgress = 0;
  Timer? _nativeCompletionTimer;
  int _lastNativeTotal = 0;

  List<UploadQueueItem> get queue => List.unmodifiable(_queue);
  UploadQueueItem? get activeItem => _activeItem;
  int get activeProgress => _activeProgress;
  bool get isBackgroundRunning => false;
  bool get isPaused => false;

  int get pendingCount =>
      _queue.where((item) => item.status == 'pending').length;

  int get completedCount =>
      _queue.where((item) => item.status == 'completed').length;

  int get failedCount =>
      _queue.where((item) => item.status == 'failed').length;

  double get totalProgress {
    if (_activeItem == null) return 0.0;
    return _activeProgress / 100.0;
  }

  UnifiedUploadQueueProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadQueue();
  }

  Future<void> _loadQueue() async {
    try {
      _queue = await UploadQueueRepository.getActive();
      final allItems = await UploadQueueRepository.getAll();
      final active = allItems
          .where((item) =>
              item.status == 'uploading' || item.status == 'pending')
          .toList();
      if (active.isNotEmpty) {
        _activeItem = active.first;
      }
      notifyListeners();
    } catch (e) {
      _queue = [];
    }
  }

  void _checkNextActive() {
    if (_activeItem != null) return;
    final next = _queue.where((item) => item.status == 'pending').toList();
    if (next.isNotEmpty) {
      _activeItem = next.first;
      _activeProgress = 0;
    }
  }

  void _startNativeCompletionPolling() {
    _nativeCompletionTimer?.cancel();
    _lastNativeTotal = 1;
    _nativeCompletionTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final status = await NativeUploadBridge.getNativeQueueStatus();
        final total = (status['totalItems'] as num?)?.toInt() ?? 0;
        final completing = (status['completed'] as num?)?.toInt() ?? 0;
        final failed = (status['failed'] as num?)?.toInt() ?? 0;
        if (_lastNativeTotal > 0 && total == 0 && (completing > 0 || failed > 0)) {
          ToastService.showSuccess('Upload completed successfully');
          _nativeCompletionTimer?.cancel();
          _nativeCompletionTimer = null;
        }
        _lastNativeTotal = total;
      } catch (_) {}
    });
  }

  void _stopNativeCompletionPolling() {
    _nativeCompletionTimer?.cancel();
    _nativeCompletionTimer = null;
  }

  // ──────────────────────────────────────────────
  //  Public queue methods
  // ──────────────────────────────────────────────

  /// Video post: queue → fetch presigned URL → sync to native → start upload.
  Future<bool> addToQueue(File file, String title) async {
    try {
      final duration = await VideoMetadataHelper.getDurationSeconds(file.path);
      final fileSize = await VideoMetadataHelper.getFileSizeBytes(file.path);

      final item = UploadQueueItem(
        filePath: file.path,
        title: title,
        videoDuration: duration,
        fileSize: fileSize,
        status: 'pending',
        uploadType: 'video_post',
      );

      await UploadPathStorage.savePath(
        filePath: file.path,
        uploadType: 'video_post',
        title: title,
      );

      final id = await UploadQueueRepository.insert(item);
      _queue = await UploadQueueRepository.getActive();
      _checkNextActive();
      notifyListeners();

      // Fetch presigned URL in main isolate (fast HTTP request)
      final result = await _fetchAndSyncVideoPost(file, title, duration, fileSize, id);
      if (result) {
        ToastService.showSuccess('Video queued for upload');
        _startNativeCompletionPolling();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.e('addToQueue error — $e');
      return false;
    }
  }

  /// Course upload: queue → fetch presigned URLs → sync native → start.
  /// Both thumbnail and video are uploaded by the native :upload process
  /// sequentially, keeping the UI non-blocking.
  Future<int> addCourseToQueue({
    required String thumbnailPath,
    required String? videoPath,
    required String title,
    required String shortDescription,
    required String description,
    required String requirements,
    required String language,
    required String level,
    required String type,
    required double price,
  }) async {
    final meta = CourseUploadMetadata(
      courseTitle: title,
      shortDescription: shortDescription,
      description: description,
      requirements: requirements,
      language: language,
      level: level,
      type: type,
      price: price,
      videoPath: videoPath,
    );

    final metadataJson = jsonEncode(meta.toJson());
    final thumbFile = File(thumbnailPath);
    final thumbSize = await thumbFile.length();

    final item = UploadQueueItem(
      filePath: thumbnailPath,
      title: 'Course: $title',
      fileSize: thumbSize,
      status: 'pending',
      uploadType: 'course',
      metadata: metadataJson,
    );

    await UploadPathStorage.savePath(
      filePath: thumbnailPath,
      uploadType: 'course',
      title: title,
      metadata: metadataJson,
    );

    final id = await UploadQueueRepository.insert(item);
    _queue = await UploadQueueRepository.getActive();
    _checkNextActive();
    notifyListeners();

    final permission = await _ensureNotificationPermission();
    if (!permission) {
      ToastService.showSuccess('Course saved. Enable notifications to start upload.');
      return id;
    }

    // Fetch presigned URLs for both thumbnail and video in one request
    final urls = await BackgroundUploadService.fetchCoursePresignedUrls(
      thumbnailPath: thumbnailPath,
      videoPath: videoPath,
    );

    if (urls == null) {
      await _cleanupFailedUpload(id, thumbnailPath);
      ToastService.showError('Failed to get upload URLs');
      return 0;
    }

    final thumbnailUploadUrl = urls['thumbnailUploadUrl']!;
    final thumbnailFileUrl = urls['thumbnailFileUrl']!;
    final videoUploadUrl = urls['videoUploadUrl'];
    final videoFileUrl = urls['videoFileUrl'];

    final authToken = AuthController.accessToken;

    // Queue video to native for background upload (no callback — just upload to S3)
    if (videoPath != null && videoUploadUrl != null) {
      await NativeUploadBridge.startNativeUpload(
        filePath: videoPath,
        uploadUrl: videoUploadUrl,
        fileUrl: videoFileUrl,
        title: 'Course intro video: $title',
        contentType: BackgroundUploadService.inferVideoContentType(videoPath),
        uploadType: 'course_video',
        authToken: authToken,
        metadata: metadataJson,
      );
    }

    // Build callback body with S3 URLs (video URL known from presigned response)
    final callbackBody = jsonEncode({
      'title': meta.courseTitle,
      'description': meta.description,
      'shortDescription': meta.shortDescription,
      'requirements': meta.requirements,
      'thumbnailUrl': thumbnailFileUrl,
      if (videoFileUrl != null) 'introVideoUrl': videoFileUrl,
      'language': meta.language,
      'level': meta.level.toUpperCase(),
      'type': meta.type.toUpperCase(),
      'price': meta.price,
    });

    // Queue thumbnail to native (with callback that creates the course)
    final syncOk = await NativeUploadBridge.startNativeUpload(
      filePath: thumbnailPath,
      uploadUrl: thumbnailUploadUrl,
      fileUrl: thumbnailFileUrl,
      title: 'Course thumbnail: $title',
      contentType: BackgroundUploadService.inferImageContentType(thumbnailPath),
      uploadType: 'course',
      authToken: authToken,
      callbackUrl: Urls.createCourseUrl,
      callbackBody: callbackBody,
      metadata: metadataJson,
      itemId: id,
    );
    if (!syncOk) {
      await _cleanupFailedUpload(id, thumbnailPath);
      ToastService.showError('Failed to sync course to native layer');
      return 0;
    }

    await UploadQueueRepository.updateUrls(id: id, uploadUrl: thumbnailUploadUrl, fileUrl: thumbnailFileUrl);

    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      await _cleanupFailedUpload(id, thumbnailPath);
      ToastService.showError('Failed to start native upload service');
      return 0;
    }
    ToastService.showSuccess('Course upload queued');
    _startNativeCompletionPolling();
    return id;
  }

  /// Video lesson: queue → fetch presigned URL → sync native → start.
  Future<int> addModuleLessonToQueue({
    required String videoPath,
    required String lessonTitle,
    required int moduleId,
    required int courseId,
    int? lessonId,
  }) async {
    if (!File(videoPath).existsSync()) {
      AppLogger.w('addModuleLessonToQueue: file not found at $videoPath');
      ToastService.showError('Video file not found');
      return 0;
    }
    final meta = ModuleLessonMetadata(
      moduleId: moduleId,
      courseId: courseId,
      lessonTitle: lessonTitle,
      lessonId: lessonId,
    );

    final metadataJson = jsonEncode(meta.toJson());
    final videoFile = File(videoPath);
    final fileSize = await videoFile.length();
    final duration = await VideoMetadataHelper.getDurationSeconds(videoPath);

    final item = UploadQueueItem(
      filePath: videoPath,
      title: lessonTitle,
      videoDuration: duration,
      fileSize: fileSize,
      status: 'pending',
      uploadType: 'module_lesson',
      metadata: metadataJson,
    );

    await UploadPathStorage.savePath(
      filePath: videoPath,
      uploadType: 'module_lesson',
      title: lessonTitle,
      metadata: metadataJson,
    );

    final permission = await _ensureNotificationPermission();
    if (!permission) {
      await UploadPathStorage.removePathByFilePath(videoPath);
      ToastService.showError('Notification permission required to upload');
      return 0;
    }

    final id = await UploadQueueRepository.insert(item);
    _queue = await UploadQueueRepository.getActive();
    _checkNextActive();
    notifyListeners();

    final urls = await BackgroundUploadService.fetchPresignedUrl(
      filePath: videoPath,
      endpoint: Urls.courseModuleUploadUrl,
      buildPayload: (name) => {
        'videoFilename': name,
        'videoContentType': BackgroundUploadService.inferVideoContentType(name),
      },
      extraFields: {'moduleID': moduleId},
      );

    if (urls == null) {
      await _cleanupFailedUpload(id, videoPath);
      ToastService.showError('Failed to get upload URL');
      return 0;
    }

    final authToken = AuthController.accessToken;
    final callbackBody = jsonEncode({
      'title': meta.lessonTitle,
      'videoUrl': urls['fileUrl'],
      'moduleId': meta.moduleId,
      'duration': duration,
      'fileSize': fileSize,
    });

    final syncOk = await NativeUploadBridge.startNativeUpload(
      filePath: videoPath,
      uploadUrl: urls['uploadUrl']!,
      fileUrl: urls['fileUrl'],
      title: lessonTitle,
      contentType: BackgroundUploadService.inferVideoContentType(videoPath),
      uploadType: 'module_lesson',
      authToken: authToken,
      callbackUrl: Urls.courseModuleLessonUrl,
      callbackBody: callbackBody,
      metadata: metadataJson,
      itemId: id,
    );
    if (!syncOk) {
      await _cleanupFailedUpload(id, videoPath);
      ToastService.showError('Failed to sync lesson to native layer');
      return 0;
    }

    await UploadQueueRepository.updateUrls(id: id, uploadUrl: urls['uploadUrl']!, fileUrl: urls['fileUrl']!);

    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      await _cleanupFailedUpload(id, videoPath);
      ToastService.showError('Failed to start native upload service');
      return 0;
    }
    ToastService.showSuccess('Video lesson queued');
    _startNativeCompletionPolling();
    return id;
  }

  /// Resource: queue → fetch presigned URL → sync native → start.
  Future<int> addResourceToQueue({
    required String filePath,
    required String lessonTitle,
    required int moduleId,
    required int courseId,
    required String contentType,
    int? lessonId,
  }) async {
    if (!File(filePath).existsSync()) {
      AppLogger.w('addResourceToQueue: file not found at $filePath');
      ToastService.showError('Resource file not found');
      return 0;
    }
    final meta = ModuleLessonMetadata(
      moduleId: moduleId,
      courseId: courseId,
      lessonTitle: lessonTitle,
      contentType: contentType,
      lessonId: lessonId,
    );

    final metadataJson = jsonEncode(meta.toJson());
    final resourceFile = File(filePath);
    final fileSize = await resourceFile.length();

    final item = UploadQueueItem(
      filePath: filePath,
      title: lessonTitle,
      fileSize: fileSize,
      status: 'pending',
      uploadType: 'resource',
      metadata: metadataJson,
    );

    await UploadPathStorage.savePath(
      filePath: filePath,
      uploadType: 'resource',
      title: lessonTitle,
      metadata: metadataJson,
    );

    final permission = await _ensureNotificationPermission();
    if (!permission) {
      await UploadPathStorage.removePathByFilePath(filePath);
      ToastService.showError('Notification permission required to upload');
      return 0;
    }

    final id = await UploadQueueRepository.insert(item);
    _queue = await UploadQueueRepository.getActive();
    _checkNextActive();
    notifyListeners();

    final urls = await BackgroundUploadService.fetchPresignedUrl(
      filePath: filePath,
      endpoint: Urls.courseModuleResourceUploadUrl,
      buildPayload: (name) => {
        'filename': name,
        'contentType': contentType,
      },
      extraFields: {'moduleID': moduleId},
    );

    if (urls == null) {
      await _cleanupFailedUpload(id, filePath);
      ToastService.showError('Failed to get upload URL');
      return 0;
    }

    final authToken = AuthController.accessToken;
    final callbackBody = jsonEncode({
      'title': meta.lessonTitle,
      'fileUrl': urls['fileUrl'],
      'moduleID': meta.moduleId,
      'courseID': meta.courseId,
      'contentType': contentType,
      'fileSize': fileSize,
    });

    final syncOk = await NativeUploadBridge.startNativeUpload(
      filePath: filePath,
      uploadUrl: urls['uploadUrl']!,
      fileUrl: urls['fileUrl'],
      title: lessonTitle,
      contentType: contentType,
      uploadType: 'resource',
      authToken: authToken,
      callbackUrl: Urls.courseModuleResourceUrl,
      callbackBody: callbackBody,
      metadata: metadataJson,
      itemId: id,
    );
    if (!syncOk) {
      await _cleanupFailedUpload(id, filePath);
      ToastService.showError('Failed to sync resource to native layer');
      return 0;
    }

    await UploadQueueRepository.updateUrls(id: id, uploadUrl: urls['uploadUrl']!, fileUrl: urls['fileUrl']!);

    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      await _cleanupFailedUpload(id, filePath);
      ToastService.showError('Failed to start native upload service');
      return 0;
    }
    ToastService.showSuccess('Resource queued');
    _startNativeCompletionPolling();
    return id;
  }

  // ──────────────────────────────────────────────
  //  Presigned URL fetch + native sync (video_post)
  // ──────────────────────────────────────────────

  /// Marks the SQLite row as failed and removes the FSS entry so the item
  /// is not picked up by recovery on next app start.
  Future<void> _cleanupFailedUpload(int id, String filePath) async {
    await UploadQueueRepository.markFailed(id, 'Upload setup failed');
    await UploadPathStorage.removePathByFilePath(filePath);
    _queue = await UploadQueueRepository.getActive();
    notifyListeners();
  }

  Future<bool> _fetchAndSyncVideoPost(File file, String title, int duration, int fileSize, int id) async {
    final permission = await _ensureNotificationPermission();
    if (!permission) {
      await _cleanupFailedUpload(id, file.path);
      ToastService.showError('Notification permission required to upload');
      return false;
    }

    final urls = await BackgroundUploadService.fetchPresignedUrl(
      filePath: file.path,
      endpoint: Urls.videoPostAssetsUploadUrl,
      buildPayload: (name) => {
        'videoFilename': name,
        'videoContentType': BackgroundUploadService.inferVideoContentType(name),
      },
    );

    if (urls == null) {
      await _cleanupFailedUpload(id, file.path);
      AppLogger.w('_fetchAndSyncVideoPost: presigned URL fetch returned null');
      ToastService.showError('Failed to get upload URL');
      return false;
    }

    final authToken = AuthController.accessToken;
    final callbackBody = jsonEncode({
      'title': title,
      'videoUrl': urls['fileUrl'],
      'duration': duration,
      'fileSize': fileSize,
    });

    final syncOk = await NativeUploadBridge.startNativeUpload(
      filePath: file.path,
      uploadUrl: urls['uploadUrl']!,
      fileUrl: urls['fileUrl'],
      title: title,
      contentType: BackgroundUploadService.inferVideoContentType(file.path),
      uploadType: 'video_post',
      authToken: authToken,
      callbackUrl: Urls.videoPostUrl,
      callbackBody: callbackBody,
      itemId: id,
    );
    if (!syncOk) {
      await _cleanupFailedUpload(id, file.path);
      AppLogger.w('_fetchAndSyncVideoPost: startNativeUpload returned false');
      ToastService.showError('Failed to sync upload to native layer');
      return false;
    }

    await UploadQueueRepository.updateUrls(id: id, uploadUrl: urls['uploadUrl']!, fileUrl: urls['fileUrl']!);

    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      await _cleanupFailedUpload(id, file.path);
      AppLogger.w('_fetchAndSyncVideoPost: startQueueProcessing returned false');
      ToastService.showError('Failed to start native upload service');
      return false;
    }
    return true;
  }

  // ──────────────────────────────────────────────
  //  Permission helpers
  // ──────────────────────────────────────────────

  Future<bool> _ensureNotificationPermission() async {
    if (await UploadNotificationService.hasNotificationPermission()) return true;

    final first = await UploadNotificationService.requestNotificationPermission();
    if (first) return true;

    final shouldRetry = await _showPermissionDialog(
      title: 'Notification Permission Required',
      content: 'Background uploads need notification permission to show progress and keep the upload alive.',
      confirmText: 'Grant',
      cancelText: 'Not Now',
    );
    if (shouldRetry != true) return false;

    final second = await UploadNotificationService.requestNotificationPermission();
    if (second) return true;

    final openSettings = await _showPermissionDialog(
      title: 'Permission Permanently Denied',
      content: 'Please enable notifications in System Settings to use background uploads.',
      confirmText: 'Open Settings',
      cancelText: 'Cancel',
    );
    if (openSettings == true) {
      await NativeUploadBridge.openNotificationSettings();
    }
    return false;
  }

  Future<bool?> _showPermissionDialog({
    required String title,
    required String content,
    required String confirmText,
    required String cancelText,
  }) {
    // ignore: use_build_context_synchronously
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

  // ──────────────────────────────────────────────
  //  Queue management (kept for backward compatibility)
  // ──────────────────────────────────────────────

  Future<void> pauseQueue() async {
    ToastService.showInfo('Queue management handled by system notifications');
  }

  Future<void> resumeQueue() async {
    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      ToastService.showError('Failed to resume upload service');
      return;
    }
    ToastService.showInfo('Upload queue resumed');
  }

  Future<void> cancelTask(int queueId) async {
    await NativeUploadBridge.cancelNativeUpload();
    await UploadQueueRepository.updateStatus(id: queueId, status: 'cancelled');
    _queue.removeWhere((item) => item.id == queueId);
    if (_activeItem?.id == queueId) {
      _activeItem = null;
      _activeProgress = 0;
    }
    notifyListeners();
    ToastService.showInfo('Upload cancelled');
  }

  Future<void> removeItem(int queueId) async {
    await UploadQueueRepository.deleteItem(queueId);
    _queue.removeWhere((item) => item.id == queueId);
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    await UploadQueueRepository.clearCompleted();
    _queue.removeWhere((item) => item.status == 'completed');
    notifyListeners();
  }

  Future<void> retryFailed(int queueId) async {
    await UploadQueueRepository.updateStatus(
      id: queueId,
      status: 'pending',
      errorMessage: null,
    );
    final idx = _queue.indexWhere((item) => item.id == queueId);
    if (idx >= 0) {
      _queue[idx] = _queue[idx].copyWith(
        status: 'pending',
        errorMessage: null,
      );
    }
    notifyListeners();

    // Re-fetch presigned URL and re-sync to native
    final item = _queue.firstWhere(
      (i) => i.id == queueId,
      orElse: () => _queue.isNotEmpty ? _queue[0] : UploadQueueItem(filePath: '', title: '', status: '', uploadType: ''),
    );
    if (item.filePath.isEmpty) return;

    final result = await _retryItem(item, queueId);
    if (result) {
      ToastService.showInfo('Retrying upload');
    }
  }

  Future<bool> _retryItem(UploadQueueItem item, int queueId) async {
    late String endpoint;
    String? callbackUrl;
    Map<String, dynamic> Function(String) buildPayload = (_) => {};
    Map<String, dynamic> extraFields = {};
    String Function(String) inferContentType = BackgroundUploadService.inferVideoContentType;
    Map<String, dynamic> Function(String fileUrl) buildCallbackBody;

    switch (item.uploadType) {
      case 'course':
        endpoint = Urls.courseAssetsUploadUrl;
        callbackUrl = Urls.createCourseUrl;
        buildPayload = (name) => {
          'thumbnailFilename': name,
          'thumbnailContentType': BackgroundUploadService.inferImageContentType(name),
        };
        inferContentType = BackgroundUploadService.inferImageContentType;
        buildCallbackBody = (fileUrl) {
          final meta = item.metadata != null
              ? CourseUploadMetadata.fromJson(jsonDecode(item.metadata!))
              : null;
          return {
            'title': meta?.courseTitle ?? item.title,
            'description': meta?.description ?? '',
            'shortDescription': meta?.shortDescription ?? '',
            'requirements': meta?.requirements ?? '',
            'thumbnailUrl': fileUrl,
            if (meta?.videoPath != null) 'introVideoUrl': meta!.videoPath,
            'language': meta?.language ?? '',
            'level': (meta?.level ?? '').toUpperCase(),
            'type': (meta?.type ?? 'FREE').toUpperCase(),
            'price': meta?.price ?? 0,
          };
        };
        break;
      case 'module_lesson':
        endpoint = Urls.courseModuleUploadUrl;
        callbackUrl = Urls.courseModuleLessonUrl;
        buildPayload = (name) => {
          'videoFilename': name,
          'videoContentType': BackgroundUploadService.inferVideoContentType(name),
        };
        buildCallbackBody = (fileUrl) {
          final meta = item.metadata != null
              ? ModuleLessonMetadata.fromJson(jsonDecode(item.metadata!))
              : null;
          return {
            'title': meta?.lessonTitle ?? item.title,
            'videoUrl': fileUrl,
            'moduleId': meta?.moduleId,
            'duration': item.videoDuration,
            'fileSize': item.fileSize,
          };
        };
        if (item.metadata != null) {
          final meta = ModuleLessonMetadata.fromJson(jsonDecode(item.metadata!));
          extraFields = {'moduleID': meta.moduleId};
        }
        break;
      case 'resource':
        endpoint = Urls.courseModuleResourceUploadUrl;
        callbackUrl = Urls.courseModuleResourceUrl;
        buildPayload = (name) {
          final ct = item.metadata != null
              ? (jsonDecode(item.metadata!) as Map)['contentType'] ?? 'application/octet-stream'
              : 'application/octet-stream';
          return {'filename': name, 'contentType': ct};
        };
        inferContentType = BackgroundUploadService.inferImageContentType;
        buildCallbackBody = (fileUrl) {
          final meta = item.metadata != null
              ? ModuleLessonMetadata.fromJson(jsonDecode(item.metadata!))
              : null;
          final ct = meta?.contentType ?? 'application/octet-stream';
          return {
            'title': meta?.lessonTitle ?? item.title,
            'fileUrl': fileUrl,
            'moduleID': meta?.moduleId,
            'courseID': meta?.courseId,
            'contentType': ct,
            'fileSize': item.fileSize,
          };
        };
        if (item.metadata != null) {
          final meta = ModuleLessonMetadata.fromJson(jsonDecode(item.metadata!));
          extraFields = {'moduleID': meta.moduleId};
        }
        break;
      default:
        endpoint = Urls.videoPostAssetsUploadUrl;
        callbackUrl = Urls.videoPostUrl;
        buildPayload = (name) => {
          'videoFilename': name,
          'videoContentType': BackgroundUploadService.inferVideoContentType(name),
        };
        buildCallbackBody = (fileUrl) => {
          'title': item.title,
          'videoUrl': fileUrl,
          'duration': item.videoDuration,
          'fileSize': item.fileSize,
        };
    }

    final urls = await BackgroundUploadService.fetchPresignedUrl(
      filePath: item.filePath,
      endpoint: endpoint,
      buildPayload: buildPayload,
      extraFields: extraFields,
    );

    if (urls == null) {
      ToastService.showError('Failed to get upload URL for retry');
      return false;
    }

    final authToken = AuthController.accessToken;
    final callbackBody = jsonEncode(buildCallbackBody(urls['fileUrl']!));

    final syncOk = await NativeUploadBridge.startNativeUpload(
      filePath: item.filePath,
      uploadUrl: urls['uploadUrl']!,
      fileUrl: urls['fileUrl'],
      title: item.title,
      contentType: inferContentType(item.filePath),
      uploadType: item.uploadType,
      authToken: authToken,
      callbackUrl: callbackUrl,
      callbackBody: callbackBody,
      itemId: queueId,
    );
    if (!syncOk) {
      ToastService.showError('Failed to sync retry item to native layer');
      return false;
    }

    await UploadQueueRepository.updateUrls(id: queueId, uploadUrl: urls['uploadUrl']!, fileUrl: urls['fileUrl']!);

    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      ToastService.showError('Failed to start native upload service');
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _stopNativeCompletionPolling();
    super.dispose();
  }
}
