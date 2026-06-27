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
import 'package:flutter/material.dart';

class UnifiedUploadQueueProvider extends ChangeNotifier {
  List<UploadQueueItem> _queue = [];
  UploadQueueItem? _activeItem;
  int _activeProgress = 0;
  Timer? _heartbeatTimer;
  int _missedHeartbeats = 0;
  static const int _maxMissedHeartbeats = 3;

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

  void _startHeartbeatPolling() {
    _heartbeatTimer?.cancel();
    _missedHeartbeats = 0;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final alive = await NativeUploadBridge.ping();
        if (alive) {
          _missedHeartbeats = 0;
          await _updateHeartbeats();
          await _processCompletedManifest();
          await _periodicCheckpoint();
          return;
        }
      } catch (_) {}
      _missedHeartbeats++;
      if (_missedHeartbeats >= _maxMissedHeartbeats) {
        AppLogger.w('Heartbeat: native service appears dead, triggering recovery');
        _missedHeartbeats = 0;
        await _recoverFromHeartbeatFailure();
      }
    });
  }

  /// Periodic storage maintenance:
  ///   - WAL checkpoint every ~5 min (30 ticks)
  ///   - Full cleanup (old items + orphaned cache) every ~8 min (50 ticks)
  int _heartbeatTick = 0;
  Future<void> _periodicCheckpoint() async {
    _heartbeatTick++;
    if (_heartbeatTick >= 50) {
      _heartbeatTick = 0;
      await UploadQueueRepository.runStartupCleanup();
    } else if (_heartbeatTick % 30 == 0) {
      await UploadQueueRepository.checkpointWal();
    }
  }

  Future<void> _updateHeartbeats() async {
    try {
      final uploading = await UploadQueueRepository.getByStatus('uploading');
      for (final item in uploading) {
        await UploadQueueRepository.updateHeartbeat(item.id!);
      }
    } catch (_) {}
  }

  Future<void> _processCompletedManifest() async {
    try {
      final markers = await NativeUploadBridge.getCompletedItems();
      if (markers.isEmpty) return;
      bool updated = false;
      bool hasCompleted = false;
      for (final entry in markers) {
        final itemId = entry['id'] as int?;
        final error = entry['error'] as String?;
        final fileUrl = entry['fileUrl'] as String?;
        if (itemId == null) continue;
        final idx = _queue.indexWhere((item) => item.id == itemId);
        if (idx < 0) continue;
        if (error != null) {
          if (_queue[idx].status != 'completed' && _queue[idx].status != 'failed' && _queue[idx].status != 'cancelled') {
            await UploadQueueRepository.markFailed(itemId, error);
            _queue[idx] = _queue[idx].copyWith(status: 'failed', errorMessage: error);
            updated = true;
          }
        } else {
          if (_queue[idx].status != 'completed' && _queue[idx].status != 'failed' && _queue[idx].status != 'cancelled') {
            await UploadQueueRepository.markCompleted(itemId);
            await _cleanupCachedFile(_queue[idx].filePath);
            _queue[idx] = _queue[idx].copyWith(
              status: 'completed',
              fileUrl: fileUrl ?? _queue[idx].fileUrl,
            );
            if (_activeItem?.id == itemId) {
              _activeItem = null;
              _activeProgress = 0;
            }
            updated = true;
            hasCompleted = true;
          }
        }
      }
      if (updated) {
        await NativeUploadBridge.acknowledgeCompletedItems();
        notifyListeners();
        if (hasCompleted) ToastService.showSuccess('Upload completed');
      }
    } catch (_) {}
  }

  DateTime _lastRecovery = DateTime(2000);
  static const Duration _recoveryCooldown = Duration(seconds: 30);

  Future<void> _recoverFromHeartbeatFailure() async {
    // Backoff: don't cascade recoveries within the cooldown window
    final sinceLast = DateTime.now().difference(_lastRecovery);
    if (sinceLast < _recoveryCooldown) return;
    _lastRecovery = DateTime.now();

    try {
      // Process any completion markers first
      await _processCompletedManifest();
      // Reset stale uploading items — heartbeatMs ensures only truly dead items
      await UploadQueueRepository.resetStaleUploading();
      _queue = await UploadQueueRepository.getActive();
      // Re-sync all pending items to the native service (which restarts fresh)
      final pendingItems = await UploadQueueRepository.getByStatus('pending');
      if (pendingItems.isNotEmpty) {
        final nativeQueueJson = jsonEncode(pendingItems.map((item) => {
          'id': item.id,
          'filePath': item.filePath,
          'title': item.title,
          'uploadUrl': item.uploadUrl,
          'fileUrl': item.fileUrl,
          'contentType': _inferContentType(item.filePath),
          'uploadType': item.uploadType,
          'metadata': item.metadata,
          'uploadId': item.uploadId,
        }).toList());
        await NativeUploadBridge.syncQueueToNative(nativeQueueJson);
        await NativeUploadBridge.startQueueProcessing();
      }
      notifyListeners();
    } catch (e) {
      AppLogger.e('Heartbeat recovery failed: $e');
    }
  }

  String _inferContentType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'mkv': return 'video/x-matroska';
      case 'webm': return 'video/webm';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'pdf': return 'application/pdf';
      default: return 'application/octet-stream';
    }
  }

  void _stopHeartbeatPolling() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Checks if same filePath has any pending/uploading item (in-flight dedup).
  bool _hasInFlightFile(List<UploadQueueItem> items, String filePath) {
    return items.any((item) =>
        item.filePath == filePath &&
        (item.status == 'pending' || item.status == 'uploading'));
  }

  // ──────────────────────────────────────────────
  //  Public queue methods
  // ──────────────────────────────────────────────

  /// Video post: queue -> fetch presigned URL -> sync to native -> start.
  Future<bool> addToQueue(File file, String title) async {
    try {
      final allItems = await UploadQueueRepository.getAll();
      if (_hasInFlightFile(allItems, file.path)) {
        ToastService.showError('This file is already being uploaded');
        return false;
      }

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

      final insertResult = await UploadQueueRepository.insert(item);
      final id = insertResult['id'] as int;
      final uploadId = insertResult['uploadId'] as String;
      _queue = await UploadQueueRepository.getActive();
      _checkNextActive();
      notifyListeners();

      final ok = await _fetchAndSyncVideoPost(file, title, duration, fileSize, id, uploadId: uploadId);
      if (ok) {
        ToastService.showSuccess('Video queued for upload');
        _startHeartbeatPolling();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.e('addToQueue error - $e');
      return false;
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

    final insertResult = await UploadQueueRepository.insert(item);
    final id = insertResult['id'] as int;
    _queue = await UploadQueueRepository.getActive();
    _checkNextActive();
    notifyListeners();

    final permission = await _ensureNotificationPermission();
    if (!permission) {
      ToastService.showSuccess('Course saved. Enable notifications to start upload.');
      return id;
    }

    final bool externalIntro = introVideoUrl != null;
    final String? effectiveVideoPath = externalIntro ? null : videoPath;

    final urls = await BackgroundUploadService.fetchCoursePresignedUrls(
      thumbnailPath: thumbnailPath,
      videoPath: effectiveVideoPath,
    );

    if (urls == null) {
      await _cleanupFailedUpload(id, thumbnailPath);
      ToastService.showError('Failed to get upload URLs');
      return 0;
    }

    final thumbnailUploadUrl = urls['thumbnailUploadUrl']!;
    final thumbnailFileUrl = urls['thumbnailFileUrl']!;

    final authToken = AuthController.accessToken;

    if (!externalIntro && videoPath != null) {
      final videoUploadUrl = urls['videoUploadUrl'];
      final videoFileUrl = urls['videoFileUrl'];
      if (videoUploadUrl != null && videoFileUrl != null) {
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
    }

    final resolvedIntroUrl = externalIntro
        ? introVideoUrl
        : urls['videoFileUrl'];

    final callbackBody = jsonEncode({
      'title': meta.courseTitle,
      'description': meta.description,
      'shortDescription': meta.shortDescription,
      'requirements': meta.requirements,
      'thumbnailUrl': thumbnailFileUrl,
      if (resolvedIntroUrl != null) 'introVideoUrl': resolvedIntroUrl,
      'language': meta.language,
      'level': meta.level.toUpperCase(),
      'type': meta.type.toUpperCase(),
      'price': meta.price,
    });

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
    _startHeartbeatPolling();
    return id;
  }

  Future<String?> addCourseIntroVideo({
    required String filePath,
    required String title,
  }) async {
    try {
      final allItems = await UploadQueueRepository.getAll();
      if (_hasInFlightFile(allItems, filePath)) {
        ToastService.showError('This video is already queued');
        return null;
      }

      final file = File(filePath);
      final fileSize = await file.length();

      final item = UploadQueueItem(
        filePath: filePath,
        title: title,
        fileSize: fileSize,
        status: 'pending',
        uploadType: 'course_intro',
      );

      final insertResult = await UploadQueueRepository.insert(item);
      final id = insertResult['id'] as int;
      _queue = await UploadQueueRepository.getActive();
      _checkNextActive();
      notifyListeners();

      final permission = await _ensureNotificationPermission();
      if (!permission) {
        ToastService.showSuccess('Video saved. Enable notifications to start upload.');
        return null;
      }

      final urls = await BackgroundUploadService.fetchCoursePresignedUrls(
        thumbnailPath: filePath,
        videoPath: filePath,
      );

      if (urls == null) {
        await _cleanupFailedUpload(id, filePath);
        ToastService.showError('Failed to get upload URL');
        return null;
      }

      final videoUploadUrl = urls['videoUploadUrl'];
      final videoFileUrl = urls['videoFileUrl'];
      if (videoUploadUrl == null || videoFileUrl == null) {
        await _cleanupFailedUpload(id, filePath);
        ToastService.showError('Server did not provide a video upload URL');
        return null;
      }

      final authToken = AuthController.accessToken;

      final syncOk = await NativeUploadBridge.startNativeUpload(
        filePath: filePath,
        uploadUrl: videoUploadUrl,
        fileUrl: videoFileUrl,
        title: 'Course intro: $title',
        contentType: BackgroundUploadService.inferVideoContentType(filePath),
        uploadType: 'course_intro',
        authToken: authToken,
      );
      if (!syncOk) {
        await _cleanupFailedUpload(id, filePath);
        ToastService.showError('Failed to sync video to native layer');
        return null;
      }

      await UploadQueueRepository.updateUrls(id: id, uploadUrl: videoUploadUrl, fileUrl: videoFileUrl);

      final started = await NativeUploadBridge.startQueueProcessing();
      if (!started) {
        await _cleanupFailedUpload(id, filePath);
        ToastService.showError('Failed to start native upload service');
        return null;
      }
      ToastService.showSuccess('Intro video queued');
      _startHeartbeatPolling();
      return videoFileUrl;
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
      final urls = await BackgroundUploadService.fetchCoursePresignedUrls(
        thumbnailPath: thumbnailPath ?? videoPath!,
        videoPath: videoPath,
      );

      if (urls == null) {
        ToastService.showError('Failed to get upload URLs');
        return null;
      }

      final authToken = AuthController.accessToken;
      bool anyQueued = false;

      if (thumbnailPath != null) {
        final thumbUploadUrl = urls['thumbnailUploadUrl'];
        final thumbFileUrl = urls['thumbnailFileUrl'];
        if (thumbUploadUrl != null && thumbFileUrl != null) {
          final ok = await NativeUploadBridge.startNativeUpload(
            filePath: thumbnailPath,
            uploadUrl: thumbUploadUrl,
            fileUrl: thumbFileUrl,
            title: 'Course thumbnail: $courseTitle',
            contentType: BackgroundUploadService.inferImageContentType(thumbnailPath),
            uploadType: 'course_thumb',
            authToken: authToken,
          );
          anyQueued = ok || anyQueued;
        }
      }

      if (videoPath != null) {
        final videoUploadUrl = urls['videoUploadUrl'];
        final videoFileUrl = urls['videoFileUrl'];
        if (videoUploadUrl != null && videoFileUrl != null) {
          final ok = await NativeUploadBridge.startNativeUpload(
            filePath: videoPath,
            uploadUrl: videoUploadUrl,
            fileUrl: videoFileUrl,
            title: 'Course intro: $courseTitle',
            contentType: BackgroundUploadService.inferVideoContentType(videoPath),
            uploadType: 'course_intro',
            authToken: authToken,
          );
          anyQueued = ok || anyQueued;
        }
      }

      if (!anyQueued) {
        ToastService.showError('Failed to queue any assets');
        return null;
      }

      final started = await NativeUploadBridge.startQueueProcessing();
      if (!started) {
        ToastService.showError('Failed to start native upload service');
        return null;
      }

      _startHeartbeatPolling();
      ToastService.showSuccess('Assets queued for upload');

      return {
        'thumbnailFileUrl': urls['thumbnailFileUrl'],
        'videoFileUrl': urls['videoFileUrl'],
      };
    } catch (e) {
      AppLogger.e('queueCourseEditAssets error: $e');
      ToastService.showError('Failed to queue course assets');
      return null;
    }
  }

  /// Video lesson: queue -> fetch presigned URL -> sync native -> start.
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

    final allItems = await UploadQueueRepository.getAll();
    if (_hasInFlightFile(allItems, videoPath)) {
      AppLogger.w('addModuleLessonToQueue: file already queued at $videoPath');
      ToastService.showError('This video is already in the upload queue');
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

    final permission = await _ensureNotificationPermission();
    if (!permission) {
      ToastService.showError('Notification permission required to upload');
      return 0;
    }

    final insertResult = await UploadQueueRepository.insert(item);
    final id = insertResult['id'] as int;
    final uploadId = insertResult['uploadId'] as String;
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
      uploadId: uploadId,
    );
    if (!syncOk) {
      await _cleanupFailedUpload(id, videoPath);
      ToastService.showError('Failed to sync lesson to native layer');
      return 0;
    }

    await UploadQueueRepository.updateUrls(
      id: id,
      uploadUrl: urls['uploadUrl']!,
      fileUrl: urls['fileUrl']!,
    );

    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      await _cleanupFailedUpload(id, videoPath);
      ToastService.showError('Failed to start native upload service');
      return 0;
    }
    ToastService.showSuccess('Video lesson queued');
    _startHeartbeatPolling();
    return id;
  }

  /// Resource: queue -> fetch presigned URL -> sync native -> start.
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

    final allItems = await UploadQueueRepository.getAll();
    if (_hasInFlightFile(allItems, filePath)) {
      AppLogger.w('addResourceToQueue: file already queued at $filePath');
      ToastService.showError('This resource is already in the upload queue');
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

    final permission = await _ensureNotificationPermission();
    if (!permission) {
      ToastService.showError('Notification permission required to upload');
      return 0;
    }

    final insertResult = await UploadQueueRepository.insert(item);
    final id = insertResult['id'] as int;
    final uploadId = insertResult['uploadId'] as String;
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
      uploadId: uploadId,
    );
    if (!syncOk) {
      await _cleanupFailedUpload(id, filePath);
      ToastService.showError('Failed to sync resource to native layer');
      return 0;
    }

    await UploadQueueRepository.updateUrls(
      id: id,
      uploadUrl: urls['uploadUrl']!,
      fileUrl: urls['fileUrl']!,
    );

    final started = await NativeUploadBridge.startQueueProcessing();
    if (!started) {
      await _cleanupFailedUpload(id, filePath);
      ToastService.showError('Failed to start native upload service');
      return 0;
    }
    ToastService.showSuccess('Resource queued');
    _startHeartbeatPolling();
    return id;
  }

  // ──────────────────────────────────────────────
  //  Presigned URL fetch + native sync (video_post)
  // ──────────────────────────────────────────────

  Future<void> _cleanupFailedUpload(int id, String filePath) async {
    await UploadQueueRepository.markFailed(id, 'Upload setup failed');
    await UploadQueueRepository.cleanupFileIfCached(filePath);
    _queue = await UploadQueueRepository.getActive();
    notifyListeners();
  }

  Future<bool> _fetchAndSyncVideoPost(File file, String title, int duration, int fileSize, int id, {String? uploadId}) async {
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
      uploadId: uploadId,
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
  //  Queue management
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
    final item = _queue.firstWhere(
      (i) => i.id == queueId,
      orElse: () => _queue.isNotEmpty ? _queue[0] : UploadQueueItem(filePath: '', title: '', status: '', uploadType: ''),
    );
    if (item.filePath.isEmpty) return;

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
    await UploadQueueRepository.incrementRetryCount(queueId);
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
      case 'course_intro':
        endpoint = Urls.courseAssetsUploadUrl;
        callbackUrl = null;
        buildPayload = (name) => {
          'thumbnailFilename': 'keep.jpg',
          'thumbnailContentType': 'image/jpeg',
          'videoFilename': name,
          'videoContentType': BackgroundUploadService.inferVideoContentType(name),
        };
        inferContentType = BackgroundUploadService.inferVideoContentType;
        buildCallbackBody = (_) => {};
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

  void onNativeUploadCompleted(int id, String fileUrl) {
    UploadQueueRepository.markCompleted(id);
    final idx = _queue.indexWhere((item) => item.id == id);
    if (idx >= 0) {
      _queue[idx] = _queue[idx].copyWith(
        status: 'completed',
        fileUrl: fileUrl,
      );
      _cleanupCachedFile(_queue[idx].filePath);
    }
    if (_activeItem?.id == id) {
      _activeItem = null;
      _activeProgress = 0;
    }
    notifyListeners();
    ToastService.showSuccess('Upload completed');
  }

  /// Delete local video file if it was copied to our cache/temp dir
  /// (e.g. by ImagePicker). Keeps gallery-original files untouched.
  Future<void> _cleanupCachedFile(String filePath) async {
    await UploadQueueRepository.cleanupFileIfCached(filePath);
  }

  void onNativeUploadFailed(int id, String error) {
    UploadQueueRepository.markFailed(id, error);
    final idx = _queue.indexWhere((item) => item.id == id);
    if (idx >= 0) {
      _queue[idx] = _queue[idx].copyWith(
        status: 'failed',
        errorMessage: error,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopHeartbeatPolling();
    super.dispose();
  }
}
