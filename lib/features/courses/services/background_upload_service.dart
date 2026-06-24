import 'dart:convert';
import 'dart:io';

import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/native_upload_bridge.dart';
import 'package:edtech/global/core/services/upload_path_storage.dart';
import 'package:http/http.dart' as http;

class BackgroundUploadService {
  static const int maxRetries = 3;
  static String? _authToken;

  static Map<String, String> _authHeaders() {
    return {
      'content-type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
  }

  static void updateToken(String? token) {
    _authToken = token;
  }

  /// Fetch a presigned S3 upload URL from the server.
  /// Returns {uploadUrl, fileUrl} or null on failure.
  static Future<Map<String, String>?> fetchPresignedUrl({
    required String filePath,
    required String endpoint,
    required Map<String, dynamic> Function(String fileName) buildPayload,
    Map<String, dynamic> extraFields = const {},
  }) async {
    final token = AuthController.accessToken;
    if (token == null) {
      AppLogger.e('fetchPresignedUrl: no auth token');
      return null;
    }
    _authToken = token;

    for (int retry = 0; retry < maxRetries; retry++) {
      try {
        final fileName = filePath.split(Platform.pathSeparator).last;
        final payload = {
          ...buildPayload(fileName),
          ...extraFields,
        };
        final response = await http.post(
          Uri.parse(endpoint),
          headers: _authHeaders(),
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final data = decoded['data'] as Map<String, dynamic>?;
          if (data != null) {
            final uploadUrl = data['uploadUrl'] as String?;
            final fileUrl = data['fileUrl'] as String?;
            if (uploadUrl != null && fileUrl != null) {
              return {'uploadUrl': uploadUrl, 'fileUrl': fileUrl};
            }
          }
        }
      } on SocketException {
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
      } on http.ClientException {
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
      }
    }
    AppLogger.e('fetchPresignedUrl: failed after $maxRetries retries');
    return null;
  }

  /// Sync the full SQLite queue to the native state file and start the
  /// native :upload process. Each item should already have its presigned URL.
  static Future<bool> syncAndStartNative() async {
    try {
      final itemsJson = await UploadPathStorage.getAtomicQueueJson();
      if (itemsJson == '[]') return true;

      await NativeUploadBridge.syncQueueToNative(itemsJson);
      await NativeUploadBridge.startQueueProcessing();
      AppLogger.i('BackgroundUploadService: synced and started native queue');
      return true;
    } catch (e) {
      AppLogger.e('BackgroundUploadService: syncAndStartNative error — $e');
      return false;
    }
  }

  /// Sync a single item with a presigned URL to the native layer.
  /// Returns true if the item was saved successfully.
  static Future<bool> syncItemToNative({
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
    return NativeUploadBridge.startNativeUpload(
      filePath: filePath,
      uploadUrl: uploadUrl,
      fileUrl: fileUrl,
      title: title,
      contentType: contentType,
      uploadType: uploadType,
      authToken: authToken,
      callbackUrl: callbackUrl,
      callbackBody: callbackBody,
      metadata: metadata,
      itemId: itemId,
    );
  }

  /// Start the native :upload process with the persisted queue.
  static Future<bool> startNativeProcessing() async {
    try {
      await NativeUploadBridge.startQueueProcessing();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String inferVideoContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4': return 'video/mp4';
      case 'mov': case 'quicktime': return 'video/quicktime';
      case 'mkv': case 'x-matroska': return 'video/x-matroska';
      case 'webm': return 'video/webm';
      default: return 'video/mp4';
    }
  }

  static String inferImageContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'avif': return 'image/avif';
      default: return 'image/jpeg';
    }
  }
}
