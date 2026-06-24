import 'dart:convert';

import 'package:edtech/global/core/services/logger_service.dart';
import 'package:flutter/services.dart';

class NativeUploadBridge {
  static const _channel = MethodChannel('eduverse/upload_bridge');

  /// Best-effort WorkManager initialization. Failure does NOT disable
  /// the critical path (startNativeUpload / startQueueProcessing).
  static Future<void> ensureInitialized() async {
    try {
      await _channel.invokeMethod('scheduleWorkManager');
    } catch (e) {
      AppLogger.w('ensureInitialized failed — $e');
    }
  }

  /// Sync the full queue from FlutterSecureStorage to the native layer.
  /// The native layer persists this to its own state file (native_uploads.json)
  /// which the :upload process can read even after app kill.
  static Future<bool> syncQueueToNative(String itemsJson) async {
    try {
      await _channel.invokeMethod('syncQueueToNative', {
        'itemsJson': itemsJson,
      });
      return true;
    } catch (e) {
      AppLogger.w('syncQueueToNative failed — $e');
      return false;
    }
  }

  /// Start the native service to process the full queue sequentially.
  /// This runs in a separate :upload process and survives app kill.
  static Future<bool> startQueueProcessing() async {
    try {
      await _channel.invokeMethod('startQueueProcessing');
      return true;
    } catch (e) {
      AppLogger.w('startQueueProcessing failed — $e');
      return false;
    }
  }

  /// Get the current queue status from native layer.
  /// Returns a map with: totalItems, pending, uploading, completed, failed, isUploading.
  static Future<Map<String, dynamic>> getNativeQueueStatus() async {
    try {
      final result = await _channel.invokeMethod<String>('getNativeQueueStatus');
      if (result == null) return _emptyStatus();
      return jsonDecode(result) as Map<String, dynamic>;
    } catch (_) {
      return _emptyStatus();
    }
  }

  static Map<String, dynamic> _emptyStatus() => {
    'totalItems': 0,
    'pending': 0,
    'uploading': 0,
    'completed': 0,
    'failed': 0,
    'isUploading': false,
  };

  /// Pass upload info to the native layer for crash survival.
  /// The native layer persists this to a shared JSON file and
  /// starts its own foreground service to perform the actual S3 PUT.
  static Future<bool> startNativeUpload({
    required String filePath,
    required String uploadUrl,
    String? fileUrl,
    required String title,
    String contentType = 'video/mp4',
    String uploadType = 'video_post',
    String? authToken,
    String? callbackUrl,
    String? callbackBody,
    String? metadata,
    int itemId = -1,
  }) async {
    try {
      await _channel.invokeMethod('startNativeUpload', {
        'filePath': filePath,
        'uploadUrl': uploadUrl,
        'fileUrl': fileUrl,
        'title': title,
        'contentType': contentType,
        'uploadType': uploadType,
        'authToken': authToken,
        'callbackUrl': callbackUrl,
        'callbackBody': callbackBody,
        'metadata': metadata,
        'itemId': itemId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get any pending uploads that survived an app force-kill.
  static Future<List<Map<String, dynamic>>> getPendingUploads() async {
    try {
      final result = await _channel.invokeMethod<String>('getNativePendingUploads');
      if (result == null) return [];
      final list = jsonDecode(result) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Get the full list of queue items with their status and progress.
  /// Returns a map with: items (list), isUploading (bool).
  static Future<Map<String, dynamic>> getQueueItems() async {
    try {
      final result = await _channel.invokeMethod<String>('getNativeQueueItems');
      if (result == null) return {'items': <Map<String, dynamic>>[], 'isUploading': false};
      return jsonDecode(result) as Map<String, dynamic>;
    } catch (_) {
      return {'items': <Map<String, dynamic>>[], 'isUploading': false};
    }
  }

  /// Clear the native upload state file.
  static Future<void> clearState() async {
    try {
      await _channel.invokeMethod('clearNativeState');
    } catch (_) {}
  }

  /// Open system notification settings for this app.
  /// On Android, opens the app's notification settings page.
  /// On iOS, opens the app's settings page in the Settings app.
  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  /// Tell the native service to process any pending queue items.
  static Future<void> processPendingQueue() async {
    try {
      await _channel.invokeMethod('processPendingQueue');
    } catch (_) {}
  }

  /// Cancel any active native upload.
  static Future<void> cancelNativeUpload() async {
    try {
      await _channel.invokeMethod('cancelNativeUpload');
    } catch (_) {}
  }

  /// Start the native foreground service to perform an upload.
  /// This is used by WorkManager when orphaned uploads are detected.
  static Future<void> startServiceForUpload({
    String? filePath,
    String? uploadUrl,
    String? title,
    String? contentType,
    String? uploadType,
    String? metadata,
    int? itemId,
  }) async {
    try {
      final args = <String, dynamic>{};
      if (filePath != null) args['filePath'] = filePath;
      if (uploadUrl != null) args['uploadUrl'] = uploadUrl;
      if (title != null) args['title'] = title;
      if (contentType != null) args['contentType'] = contentType;
      if (uploadType != null) args['uploadType'] = uploadType;
      if (metadata != null) args['metadata'] = metadata;
      if (itemId != null) args['itemId'] = itemId;
      await _channel.invokeMethod('startServiceForUpload', args);
    } catch (_) {}
  }
}
