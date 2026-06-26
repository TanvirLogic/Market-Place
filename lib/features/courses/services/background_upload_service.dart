import 'dart:convert';
import 'dart:io';

import 'package:edtech/app/urls.dart';
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
        // Backoff on HTTP errors too (server 500s, etc.)
        if (retry < maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
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

  /// Fetch presigned URLs for course asset upload (thumbnail + optional video).
  ///
  /// The endpoint returns a nested response:
  /// ```json
  /// { "data": { "data": {
  ///     "thumbnail": { "uploadUrl": "...", "fileUrl": "..." },
  ///     "video": { "uploadUrl": "...", "fileUrl": "..." }
  /// }}}
  /// ```
  ///
  /// Returns a map with keys: `thumbnailUploadUrl`, `thumbnailFileUrl`,
  /// `videoUploadUrl` (nullable), `videoFileUrl` (nullable).
  static Future<Map<String, String?>?> fetchCoursePresignedUrls({
    required String thumbnailPath,
    String? videoPath,
  }) async {
    final token = AuthController.accessToken;
    if (token == null) {
      AppLogger.e('fetchCoursePresignedUrls: no auth token');
      return null;
    }
    _authToken = token;

    final thumbName = thumbnailPath.split(Platform.pathSeparator).last;
    final payload = <String, dynamic>{
      'thumbnailFilename': thumbName,
      'thumbnailContentType': inferImageContentType(thumbName),
    };

    if (videoPath != null) {
      final videoName = videoPath.split(Platform.pathSeparator).last;
      payload['videoFilename'] = videoName;
      payload['videoContentType'] = inferVideoContentType(videoName);
    }

    for (int retry = 0; retry < maxRetries; retry++) {
      try {
        final response = await http.post(
          Uri.parse(Urls.courseAssetsUploadUrl),
          headers: _authHeaders(),
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final outerData = decoded['data'] as Map<String, dynamic>?;
          final innerData = outerData?['data'] as Map<String, dynamic>?;

          if (innerData == null) {
            if (retry < maxRetries - 1) {
              await Future.delayed(Duration(seconds: 2 * (retry + 1)));
              continue;
            }
            AppLogger.e('fetchCoursePresignedUrls: nested data is null');
            return null;
          }

          final thumb = innerData['thumbnail'] as Map<String, dynamic>?;
          final video = innerData['video'] as Map<String, dynamic>?;

          final thumbUploadUrl = thumb?['uploadUrl'] as String?;
          final thumbFileUrl = thumb?['fileUrl'] as String?;

          if (thumbUploadUrl == null || thumbFileUrl == null) {
            if (retry < maxRetries - 1) {
              await Future.delayed(Duration(seconds: 2 * (retry + 1)));
              continue;
            }
            AppLogger.e('fetchCoursePresignedUrls: thumbnail URLs missing');
            return null;
          }

          return {
            'thumbnailUploadUrl': thumbUploadUrl,
            'thumbnailFileUrl': thumbFileUrl,
            'videoUploadUrl': video?['uploadUrl'] as String?,
            'videoFileUrl': video?['fileUrl'] as String?,
          };
        }
        if (retry < maxRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      } on SocketException {
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
      } on http.ClientException {
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
      }
    }
    AppLogger.e('fetchCoursePresignedUrls: failed after $maxRetries retries');
    return null;
  }

  /// Upload a file to S3 via presigned URL using HTTP PUT with streaming.
  /// Uses chunked streaming to avoid OOM on large files (3-4GB).
  static Future<bool> uploadFileToS3({
    required String filePath,
    required String uploadUrl,
    required String contentType,
    Duration timeout = const Duration(minutes: 30),
    void Function(double progress)? onProgress,
  }) async {
    try {
      final file = File(filePath);
      final fileSize = await file.length();
      final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
      request.headers['Content-Type'] = contentType;
      request.contentLength = fileSize;

      final stream = file.openRead();
      int bytesSent = 0;
      await for (final chunk in stream) {
        request.sink.add(chunk);
        bytesSent += chunk.length;
        onProgress?.call(bytesSent / fileSize);
      }
      await request.sink.close();

      final response = await request.send().timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.e('uploadFileToS3 error: $e');
      return false;
    }
  }
}
