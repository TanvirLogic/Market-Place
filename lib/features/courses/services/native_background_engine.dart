import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:upload_queue/upload_queue.dart';

class NativeBackgroundEngine extends UploadEngine {
  static const _channel = MethodChannel('eduverse/upload_engine');
  static const _events = EventChannel('eduverse/upload_progress');

  final http.Client _client;
  StreamSubscription<dynamic>? _eventSub;

  final Map<int, void Function(double)> _directProgressCallbacks = {};
  final Map<int, void Function(int, int)> _multipartProgressCallbacks = {};

  NativeBackgroundEngine(super.config, {http.Client? httpClient})
    : _client = httpClient ?? http.Client() {
    _eventSub = _events.receiveBroadcastStream().listen(_onNativeEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _client.close();
  }

  void _log(String msg) => config.logger?.call(msg);

  Map<String, String> _authHeaders() => {
    'content-type': 'application/json',
    'Authorization': 'Bearer ${config.tokenProvider()}',
  };

  String _initEndpoint(Map<String, dynamic>? extraFields) =>
      config.buildInitEndpoint?.call(extraFields) ?? config.initUploadEndpoint;

  Map<String, dynamic> _buildInitBody(
    String fileName,
    Map<String, dynamic>? extraFields,
  ) =>
      config.buildInitBody?.call(fileName, extraFields) ??
      DartHttpEngine.defaultInitBody(fileName, extraFields);

  InitUploadResponse _parseInit(Map<String, dynamic> json) =>
      config.parseInitResponse?.call(json) ?? InitUploadResponse.fromJson(json);

  Map<String, dynamic> _buildCompleteBody(
    String s3UploadId,
    List<PartETag> parts, {
    Map<String, dynamic>? extraFields,
  }) {
    final base =
        config.buildCompleteBody?.call(s3UploadId, parts) ??
        DartHttpEngine.defaultCompleteBody(s3UploadId, parts);
    if (extraFields == null || extraFields.isEmpty) return base;
    return {...base, ...extraFields};
  }

  String? _parseComplete(Map<String, dynamic> json) =>
      config.parseCompleteResponse?.call(json) ??
      DartHttpEngine.defaultParseComplete(json);

  Map<String, dynamic> _buildAbortBody(String s3UploadId, {String? s3Key}) {
    final base = config.buildAbortBody?.call(s3UploadId) ??
        DartHttpEngine.defaultAbortBody(s3UploadId);
    if (s3Key != null && s3Key.isNotEmpty) {
      return {...base, 'key': s3Key};
    }
    return base;
  }

  // ── API calls (in Dart — lightweight) ──

  @override
  Future<InitUploadResponse?> initUpload({
    required String filePath,
    Map<String, dynamic>? extraFields,
  }) async {
    final token = config.tokenProvider();
    if (token.isEmpty) {
      debugPrint('[NativeEngine] initUpload: no token');
      return null;
    }

    final fileName = filePath.split(Platform.pathSeparator).last;
    final payload = _buildInitBody(fileName, extraFields);
    final endpoint = _initEndpoint(extraFields);
    debugPrint(
      '[NativeEngine] initUpload endpoint=$endpoint fileName=$fileName payload=$payload',
    );

    for (int retry = 0; retry < 3; retry++) {
      try {
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: _authHeaders(),
              body: jsonEncode(payload),
            )
            .timeout(config.apiTimeout);

        debugPrint(
          '[NativeEngine] initUpload response status=${response.statusCode} body=${response.body}',
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          return _parseInit(jsonDecode(response.body) as Map<String, dynamic>);
        }
        if (retry < 2) {
          debugPrint('[NativeEngine] initUpload retry $retry');
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      } on SocketException catch (e) {
        debugPrint('[NativeEngine] initUpload SocketException: $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      } on http.ClientException catch (e) {
        debugPrint('[NativeEngine] initUpload ClientException: $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      }
    }
    debugPrint('[NativeEngine] initUpload returning null after retries');
    return null;
  }

  // ── File data transfer (in native — survives app kill) ──

  @override
  Future<bool> directUpload({
    required String filePath,
    required String uploadUrl,
    void Function(double progress)? onProgress,
    int? dbTaskId,
  }) async {
    final taskId = dbTaskId ?? DateTime.now().millisecondsSinceEpoch;
    debugPrint(
      '[NativeEngine] directUpload taskId=$taskId filePath=$filePath uploadUrl=$uploadUrl',
    );
    if (onProgress != null) {
      _directProgressCallbacks[taskId] = onProgress;
    }
    try {
      final result = await _channel.invokeMethod<Map>('directUpload', {
        'taskId': taskId,
        'filePath': filePath,
        'uploadUrl': uploadUrl,
        'authToken': config.tokenProvider(),
        'contentType': _inferContentType(filePath),
        'wifiOnly': config.wifiOnly,
      });
      debugPrint('[NativeEngine] directUpload result=$result');
      return result?['success'] == true;
    } on PlatformException catch (e) {
      debugPrint('[NativeEngine] directUpload PlatformException: $e');
      _log('[NativeEngine] directUpload failed: $e');
      return false;
    } finally {
      _directProgressCallbacks.remove(taskId);
    }
  }

  @override
  Future<List<PartUploadResult>> uploadParts({
    required String filePath,
    required List<PartPresignedUrl> parts,
    required int partSize,
    void Function(int completed, int total)? onProgress,
    int? dbTaskId,
  }) async {
    final taskId = dbTaskId ?? DateTime.now().millisecondsSinceEpoch;
    debugPrint(
      '[NativeEngine] uploadParts taskId=$taskId partsCount=${parts.length} partSize=$partSize',
    );
    if (onProgress != null) {
      _multipartProgressCallbacks[taskId] = onProgress;
    }
    try {
      final result = await _channel.invokeMethod<List>('uploadParts', {
        'taskId': taskId,
        'filePath': filePath,
        'parts': parts.map((p) => p.toJson()).toList(),
        'partSize': partSize,
        'authToken': config.tokenProvider(),
        'wifiOnly': config.wifiOnly,
      });
      debugPrint('[NativeEngine] uploadParts result=$result');
      if (result == null) return [];
      return result
          .map(
            (r) => PartUploadResult(
              partNumber: (r['partNumber'] as num).toInt(),
              success: r['success'] as bool? ?? false,
              eTag: r['eTag'] as String?,
              errorMessage: r['errorMessage'] as String?,
              isUrlExpired: r['isUrlExpired'] as bool? ?? false,
            ),
          )
          .toList();
    } on PlatformException catch (e) {
      debugPrint('[NativeEngine] uploadParts PlatformException: $e');
      _log('[NativeEngine] uploadParts failed: $e');
      return parts
          .map(
            (p) => PartUploadResult(
              partNumber: p.partNumber,
              success: false,
              errorMessage: 'Native engine error',
            ),
          )
          .toList();
    } finally {
      _multipartProgressCallbacks.remove(taskId);
    }
  }

  /// Query native background upload status after app restart.
  ///
  /// Returns a map with background session state for the given [taskId].
  /// The native channel checks WorkManager (Android) or background URLSession
  /// state files (iOS) to determine if the upload completed while killed.
  Future<Map<String, dynamic>?> getUploadStatus(int taskId) async {
    try {
      final result = await _channel.invokeMethod<Map>('getUploadStatus', {
        'taskId': taskId,
      });
      return result?.cast<String, dynamic>();
    } on PlatformException catch (e) {
      _log('[NativeEngine] getUploadStatus failed: $e');
      return null;
    }
  }

  @override
  Future<bool?> checkUploadCompleted(int dbTaskId) async {
    final status = await getUploadStatus(dbTaskId);
    if (status == null) return null;
    final allDone = status['allDone'] as bool? ?? false;
    final failed = (status['failed'] as List?)?.isNotEmpty ?? false;
    final totalParts = status['totalParts'] as int? ?? 0;
    if (totalParts == 0) return null; // No WorkManager record — unknown
    if (!allDone) return false;
    if (failed) return false;
    return true;
  }

  @override
  Future<void> cancelUpload(int dbTaskId) async {
    try {
      await _channel.invokeMethod('cancelTask', {'taskId': dbTaskId});
    } on PlatformException catch (e) {
      _log('[NativeEngine] cancelUpload failed: $e');
    }
  }

  @override
  Future<InitUploadResponse?> refreshPresignedUrls({
    required String filePath,
    required String s3UploadId,
    required List<int> partNumbers,
    Map<String, dynamic>? extraFields,
  }) async {
    // Forward existing upload session info to the backend so it returns
    // fresh presigned URLs for the same multipart session, not a new one.
    final refreshFields = <String, dynamic>{
      ...?extraFields,
      's3UploadId': s3UploadId,
      'refreshParts': partNumbers,
    };
    return initUpload(filePath: filePath, extraFields: refreshFields);
  }

  // ── Remaining API calls (Dart — lightweight) ──

  @override
  Future<String?> completeMultipart({
    required String s3UploadId,
    required List<PartETag> parts,
    String? endpoint,
    Map<String, dynamic>? extraFields,
  }) async {
    final token = config.tokenProvider();
    if (token.isEmpty) {
      debugPrint('[NativeEngine] completeMultipart: no token');
      return null;
    }

    final url = endpoint ?? config.initUploadEndpoint;
    debugPrint(
      '[NativeEngine] completeMultipart url=$url partsCount=${parts.length}',
    );

    for (int retry = 0; retry < 3; retry++) {
      try {
        final response = await _client
            .post(
              Uri.parse(url),
              headers: _authHeaders(),
              body: jsonEncode(
                _buildCompleteBody(s3UploadId, parts, extraFields: extraFields),
              ),
            )
            .timeout(config.apiTimeout);

        debugPrint(
          '[NativeEngine] completeMultipart status=${response.statusCode} body=${response.body}',
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          final fileUrl = _parseComplete(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
          if (fileUrl != null) return fileUrl;
        }
        if (retry < 2) {
          debugPrint('[NativeEngine] completeMultipart retry $retry');
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      } catch (e) {
        debugPrint('[NativeEngine] completeMultipart error: $e');
        _log('[NativeEngine] completeMultipart error: $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      }
    }
    debugPrint('[NativeEngine] completeMultipart returning null');
    return null;
  }

  @override
  Future<String?> completeMultipartAndCallback({
    required String s3UploadId,
    required List<PartETag> parts,
    required CallbackRequest callback,
    String? endpoint,
    int? dbTaskId,
    Map<String, dynamic>? completeExtraFields,
  }) async {
    final token = config.tokenProvider();
    if (token.isEmpty) {
      debugPrint('[NativeEngine] completeMultipartAndCallback: no token');
      return null;
    }

    final url = endpoint ?? config.initUploadEndpoint;
    final completeBody = jsonEncode(
      _buildCompleteBody(s3UploadId, parts, extraFields: completeExtraFields),
    );

    // Try native chain first (survives app kill)
    final result = await scheduleCompleteAndCallback(
      taskId: dbTaskId ?? 0,
      completeUrl: url,
      completeBody: completeBody,
      callbackUrl: callback.url,
      callbackBody: callback.body,
      authToken: token,
      idempotencyKey: callback.idempotencyKey,
      refreshEndpoint: config.refreshEndpoint,
      refreshToken: config.refreshTokenProvider?.call(),
    );
    if (result != null) {
      final success = result['success'] == true;
      if (success) {
        final fileUrl = result['fileUrl'] as String?;
        if (fileUrl != null && fileUrl.isNotEmpty) {
          return fileUrl;
        }
        // Backend returned success but no fileUrl — use init fileUrl from callback
        return callback.body['videoUrl'] as String? ?? '';
      }
      return null;
    }

    // Fallback: Dart-based (if native channel unavailable)
    debugPrint(
      '[NativeEngine] completeMultipartAndCallback falling back to Dart',
    );
    return super.completeMultipartAndCallback(
      s3UploadId: s3UploadId,
      parts: parts,
      callback: callback,
      endpoint: endpoint,
      dbTaskId: dbTaskId,
      completeExtraFields: completeExtraFields,
    );
  }

  @override
  Future<bool> abortMultipart(
    String s3UploadId, {
    String? endpoint,
    String? s3Key,
  }) async {
    final token = config.tokenProvider();
    if (token.isEmpty) return false;

    final url = endpoint ?? config.initUploadEndpoint;

    for (int retry = 0; retry < 3; retry++) {
      try {
        final response = await _client
            .post(
              Uri.parse(url),
              headers: _authHeaders(),
              body: jsonEncode(_buildAbortBody(s3UploadId, s3Key: s3Key)),
            )
            .timeout(config.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return true;
        }
      } catch (e) {
        _log('[NativeEngine] abortMultipart error: $e');
      }
      if (retry < 2) {
        await Future.delayed(Duration(seconds: retry + 1));
      }
    }
    return false;
  }

  @override
  Future<bool> sendCallback(CallbackRequest callback, {int? dbTaskId}) async {
    debugPrint(
      '[NativeEngine] sendCallback url=${callback.url} body=${callback.body} idempotencyKey=${callback.idempotencyKey} dbTaskId=$dbTaskId',
    );
    try {
      final token = config.tokenProvider();
      if (token.isEmpty) {
        debugPrint('[NativeEngine] sendCallback: no token');
        return false;
      }

      final result = await _channel.invokeMethod<Map>('scheduleCallback', {
        'taskId': dbTaskId ?? 0,
        'callbackUrl': callback.url,
        'callbackBody': jsonEncode(callback.body),
        'authToken': token,
        if (callback.idempotencyKey != null)
          'idempotencyKey': callback.idempotencyKey,
        if (config.refreshEndpoint != null)
          'refreshEndpoint': config.refreshEndpoint,
        if (config.refreshTokenProvider != null)
          'refreshToken': config.refreshTokenProvider!(),
      });

      final success = result?['success'] == true;
      debugPrint('[NativeEngine] sendCallback native result=$result');
      return success;
    } on PlatformException catch (e) {
      debugPrint('[NativeEngine] sendCallback PlatformException: $e');
      _log('[NativeEngine] sendCallback native failed: $e');
      return false;
    }
  }

  /// Schedule a native chain: CompleteWorker → CallbackWorker.
  /// Both survive app kill. Returns the fileUrl on success, null on failure.
  Future<Map<String, dynamic>?> scheduleCompleteAndCallback({
    required int taskId,
    required String completeUrl,
    required String completeBody,
    required String callbackUrl,
    required Map<String, dynamic> callbackBody,
    required String authToken,
    String? idempotencyKey,
    String? refreshEndpoint,
    String? refreshToken,
  }) async {
    debugPrint(
      '[NativeEngine] scheduleCompleteAndCallback taskId=$taskId completeUrl=$completeUrl callbackUrl=$callbackUrl',
    );
    try {
      final result = await _channel
          .invokeMethod<Map>('scheduleCompleteAndCallback', {
            'taskId': taskId,
            'completeUrl': completeUrl,
            'completeBody': completeBody,
            'callbackUrl': callbackUrl,
            'callbackBody': jsonEncode(callbackBody),
            'authToken': authToken,
            if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
            if (refreshEndpoint != null) 'refreshEndpoint': refreshEndpoint,
            if (refreshToken != null) 'refreshToken': refreshToken,
          });

      debugPrint('[NativeEngine] scheduleCompleteAndCallback result=$result');
      return result?.cast<String, dynamic>();
    } on PlatformException catch (e) {
      debugPrint(
        '[NativeEngine] scheduleCompleteAndCallback PlatformException: $e',
      );
      _log('[NativeEngine] scheduleCompleteAndCallback failed: $e');
      return null;
    }
  }

  /// Query the outcome of the complete+callback chain that ran for [dbTaskId].
  /// Returns a map with `state` (`success`|`failed`|`running`|`unknown`),
  /// optional `fileUrl`, and optional `error`.
  @override
  Future<Map<String, dynamic>?> getChainStatus(int dbTaskId) async {
    try {
      final result = await _channel.invokeMethod<Map>('getChainStatus', {
        'taskId': dbTaskId,
      });
      return result?.cast<String, dynamic>();
    } on PlatformException catch (e) {
      _log('[NativeEngine] getChainStatus failed: $e');
      return null;
    }
  }

  // ── Helpers ──

  void _onNativeEvent(dynamic event) {
    // EventChannel sends Map<Object?, Object?> from Kotlin; cast each
    // key/value individually instead of casting the entire map.
    final map = Map<String, dynamic>.from(event as Map);
    final taskId = map['taskId'] as int;
    final type = map['type'] as String;

    switch (type) {
      case 'directProgress' when _directProgressCallbacks.containsKey(taskId):
        _directProgressCallbacks[taskId]!((map['progress'] as num).toDouble());
      case 'multipartProgress'
          when _multipartProgressCallbacks.containsKey(taskId):
        // Prefer smooth byte-level fraction when the native side provides it
        // (large 2 GB files). Scale to a 0–10000 range so the existing
        // (completed, total) callback yields 0.01%-precision progress without
        // changing the engine interface. Fall back to part counts otherwise.
        final progress = (map['progress'] as num?)?.toDouble();
        if (progress != null) {
          const scale = 10000;
          _multipartProgressCallbacks[taskId]!(
            (progress.clamp(0.0, 1.0) * scale).round(),
            scale,
          );
        } else {
          _multipartProgressCallbacks[taskId]!(
            (map['completed'] as num).toInt(),
            (map['total'] as num).toInt(),
          );
        }
    }
  }

  String _inferContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
      case 'quicktime':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
