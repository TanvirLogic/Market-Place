import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edtech/app/urls.dart';
import 'package:edtech/features/courses/data/repositories/upload_queue_repository.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;

class _StreamedProgressRequest extends http.BaseRequest {
  final Stream<List<int>> _stream;

  _StreamedProgressRequest(super.method, super.url, this._stream);

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_stream);
  }
}

class BackgroundUploadService {
  static const int maxRetries = 3;

  static bool _isRunning = false;
  static bool _paused = false;
  static String? _authToken;

  static bool get isRunning => _isRunning;
  static bool get isPaused => _paused;

  static void registerBackgroundHandler() {
    FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        autoStartOnBoot: false,
        notificationChannelId: 'upload_foreground',
        initialNotificationTitle: 'Upload in progress',
        initialNotificationContent: '',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Map<String, String> _authHeaders() {
    return {
      'content-type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) {
    AppLogger.i('BackgroundUploadService: background isolate started');

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Upload in progress',
        content: '',
      );
    }

    service.on('startQueue').listen((data) async {
      AppLogger.i('BackgroundUploadService: startQueue command received');
      _authToken = data?['token'] as String?;
      if (!_isRunning) {
        _paused = false;
        unawaited(_runQueueLoop(service));
      }
    });

    service.on('pauseQueue').listen((data) {
      AppLogger.i('BackgroundUploadService: pauseQueue command received');
      _paused = true;
    });

    service.on('resumeQueue').listen((data) async {
      AppLogger.i('BackgroundUploadService: resumeQueue command received');
      final token = (data is Map<String, dynamic>) ? data['token'] as String? : null;
      if (token != null) _authToken = token;
      if (_paused) {
        _paused = false;
        if (!_isRunning) {
          unawaited(_runQueueLoop(service));
        }
      }
    });

    service.on('cancelItem').listen((data) async {
      final queueId = data?['queueId'] as int?;
      if (queueId != null) {
        AppLogger.i('BackgroundUploadService: cancelItem queueId=$queueId');
        await UploadQueueRepository.markFailed(queueId, 'Cancelled by user');
      }
    });

    service.on('stopService').listen((_) {
      AppLogger.i('BackgroundUploadService: stop command received');
      _isRunning = false;
      _paused = false;
      service.stopSelf();
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }

  static Future<void> _runQueueLoop(ServiceInstance service) async {
    _isRunning = true;

    try {
      while (!_paused) {
        final next = await UploadQueueRepository.getNextPending();
        if (next == null) {
          AppLogger.i('BackgroundUploadService: no pending items, stopping');
          break;
        }

        await UploadNotificationService.showProgress(
          notificationId: next.id!,
          progress: 0,
          total: 100,
          title: 'Preparing ${next.title}',
        );

        await _processItem(service, next);

        if (_paused) break;
      }
    } catch (e) {
      AppLogger.e('BackgroundUploadService: queue loop error — $e');
    }

    _isRunning = false;

    if (!_paused) {
      final queueDoneId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await UploadNotificationService.showSuccess(
        notificationId: queueDoneId,
        title: 'All Uploads Complete',
        body: 'All videos in the queue have been processed.',
      );
      await UploadNotificationService.stopService();
    }
  }

  static Future<void> _processItem(ServiceInstance service, UploadQueueItem item) async {
    try {
      final urls = await _getPresignedUrl(service, item);
      if (urls == null) return;

      final uploadUrl = urls['uploadUrl']!;
      final fileUrl = urls['fileUrl']!;

      await UploadQueueRepository.updateUrls(
        id: item.id!,
        uploadUrl: uploadUrl,
        fileUrl: fileUrl,
      );

      await _uploadToS3(service, item, uploadUrl);

      await _createVideoPost(service, item, fileUrl);

      await UploadQueueRepository.markCompleted(item.id!);
      await _sendProgress(service, item.id!, 'completed', 100);

      await UploadNotificationService.showSuccess(
        notificationId: item.id!,
        title: item.title,
        body: 'Upload complete',
      );
    } catch (e) {
      AppLogger.e('BackgroundUploadService: item error — $e');

      final isNetworkError = e is SocketException || e is TimeoutException;
      final errorMsg = isNetworkError ? 'Network paused' : e.toString();

      await UploadQueueRepository.markFailed(item.id!, errorMsg);
      await _sendProgress(service, item.id!, 'failed', 0);

      if (isNetworkError) {
        await UploadNotificationService.showError(
          notificationId: item.id!,
          title: item.title,
          body: 'Network paused',
        );
      } else {
        await UploadNotificationService.showError(
          notificationId: item.id!,
          title: item.title,
          body: 'Upload failed',
        );
      }
    }
  }

  static Future<Map<String, String>?> _getPresignedUrl(
    ServiceInstance service,
    UploadQueueItem item,
  ) async {
    for (int retry = 0; retry < maxRetries; retry++) {
      try {
        final videoName = item.filePath.split(Platform.pathSeparator).last;
        final contentType = _inferVideoContentType(videoName);

        final payload = jsonEncode({
          'videoFilename': videoName,
          'videoContentType': contentType,
        });

        final response = await http.post(
          Uri.parse(Urls.videoPostAssetsUploadUrl),
          headers: _authHeaders(),
          body: payload,
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
          AppLogger.e('BackgroundUploadService: invalid presigned URL response — $decoded');
        } else {
          AppLogger.e('BackgroundUploadService: presigned URL failed ${response.statusCode}');
        }
      } on SocketException {
        AppLogger.w('BackgroundUploadService: presigned URL network error, retry=$retry');
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
      } on TimeoutException {
        AppLogger.w('BackgroundUploadService: presigned URL timeout, retry=$retry');
        await Future.delayed(Duration(seconds: 2 * (retry + 1)));
      }
    }

    await UploadQueueRepository.markFailed(item.id!, 'Failed to get upload URL');
    await _sendProgress(service, item.id!, 'failed', 0);
    await UploadNotificationService.showError(
      notificationId: item.id!,
      title: item.title,
      body: 'Failed to get upload URL',
    );
    return null;
  }

  static Future<void> _uploadToS3(
    ServiceInstance service,
    UploadQueueItem item,
    String uploadUrl,
  ) async {
    final file = File(item.filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', item.filePath);
    }

    final total = await file.length();
    if (total == 0) {
      throw Exception('File is empty');
    }

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      final client = http.Client();
      try {
        int sent = 0;
        int lastReportedPct = -1;

        final stream = file.openRead();
        final progressStream = stream.transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              sent += chunk.length;
              final pct = total > 0 ? (sent * 100 ~/ total) : 0;
              if (pct != lastReportedPct) {
                lastReportedPct = pct;
                _sendProgress(service, item.id!, 'uploading', pct);
                UploadNotificationService.showProgress(
                  notificationId: item.id!,
                  progress: sent,
                  total: total,
                  title: item.title,
                );
              }
              sink.add(chunk);
            },
          ),
        );

        final request = _StreamedProgressRequest('PUT', Uri.parse(uploadUrl), progressStream);
        request.headers['Content-Type'] = 'application/octet-stream';
        request.contentLength = total;

        final response = await client.send(request).timeout(const Duration(hours: 6));
        if (response.statusCode == 200) {
          await UploadQueueRepository.updateProgress(
            id: item.id!,
            bytesUploaded: total,
          );
          return;
        }
        AppLogger.w('BackgroundUploadService: S3 upload status=${response.statusCode}, attempt=$attempt');
        if (attempt >= maxRetries) {
          throw HttpException('S3 upload failed with status ${response.statusCode}');
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      } on SocketException {
        AppLogger.w('BackgroundUploadService: S3 network error, attempt=$attempt');
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      } on TimeoutException {
        AppLogger.w('BackgroundUploadService: S3 timeout, attempt=$attempt');
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      } finally {
        client.close();
      }
    }
  }

  static Future<void> _createVideoPost(
    ServiceInstance service,
    UploadQueueItem item,
    String fileUrl,
  ) async {
    final payload = jsonEncode({
      'title': item.title,
      'videoUrl': fileUrl,
      'duration': item.videoDuration,
      'fileSize': item.fileSize,
    });

    final response = await http.post(
      Uri.parse(Urls.videoPostUrl),
      headers: _authHeaders(),
      body: payload,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      AppLogger.w('BackgroundUploadService: create post status ${response.statusCode}');
      throw HttpException('Failed to create video post: ${response.statusCode}');
    }

    AppLogger.i('BackgroundUploadService: video post created successfully');
  }

  static String _inferVideoContentType(String filename) {
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

  static Future<void> _sendProgress(
    ServiceInstance service,
    int queueId,
    String status,
    int progress,
  ) async {
    try {
      service.invoke('uploadProgress', {
        'queueId': queueId,
        'status': status,
        'progress': progress,
      });
    } catch (_) {}
  }

  static Future<void> startQueue({String? token}) async {
    final svc = FlutterBackgroundService();
    final running = await svc.isRunning();
    if (!running) {
      await svc.startService();
    }
    await Future.delayed(const Duration(milliseconds: 300));
    svc.invoke('startQueue', {'token': token});
  }

  static Future<void> pauseQueue() async {
    _paused = true;
    FlutterBackgroundService().invoke('pauseQueue');
  }

  static Future<void> resumeQueue({String? token}) async {
    _paused = false;
    final svc = FlutterBackgroundService();
    final running = await svc.isRunning();
    if (!running) {
      await svc.startService();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    svc.invoke('resumeQueue', {'token': token});
  }

  static Future<void> cancelItem(int queueId) async {
    FlutterBackgroundService().invoke('cancelItem', {'queueId': queueId});
  }

  static Future<void> stopService() async {
    _isRunning = false;
    _paused = false;
    final svc = FlutterBackgroundService();
    final running = await svc.isRunning();
    if (running) {
      svc.invoke('stopService');
    }
  }
}
