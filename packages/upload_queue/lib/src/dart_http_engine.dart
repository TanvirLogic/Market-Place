import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'engine.dart';
import 'models/models.dart';

/// Default [UploadEngine] implementation using `package:http`.
///
/// Works in the foreground only. For true background upload (survive app
/// kill), build a [NativeBackgroundEngine] and inject it into [UploadQueue].
class DartHttpEngine extends UploadEngine {
  DartHttpEngine(super.config, {http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// Default init body builder — available for reuse by custom engines.
  static Map<String, dynamic> defaultInitBody(
    String fileName,
    Map<String, dynamic>? extraFields,
  ) {
    final ext = fileName.split('.').last.toLowerCase();
    return {
      'filename': fileName,
      'contentType': _defaultContentType(ext),
      if (extraFields != null) ...extraFields,
    };
  }

  /// Default complete body builder — available for reuse by custom engines.
  static Map<String, dynamic> defaultCompleteBody(
    String s3UploadId,
    List<PartETag> parts,
  ) =>
      {
        'uploadId': s3UploadId,
        'parts': parts.map((p) => p.toJson()).toList(),
      };

  /// Default complete response parser — available for reuse by custom engines.
  static String? defaultParseComplete(Map<String, dynamic> json) {
    final d = json['data'] is Map
        ? json['data'] as Map<String, dynamic>
        : json;
    return d['fileUrl'] as String?;
  }

  /// Default abort body builder — available for reuse by custom engines.
  static Map<String, dynamic> defaultAbortBody(String s3UploadId) =>
      {'uploadId': s3UploadId};

  /// Default ETag extractor — available for reuse by custom engines.
  ///
  /// Returns the ETag header value **verbatim**, preserving S3's canonical
  /// surrounding quotes (e.g. `"abc123"`). The backend's complete-multipart
  /// endpoint expects the raw header value as received from S3.
  static String? defaultExtractETag(Map<String, String> headers) {
    return headers['etag'] ?? headers['Etag'];
  }

  static String _defaultContentType(String ext) {
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

  @override
  void dispose() {
    _client.close();
  }

  void _log(String msg) => config.logger?.call(msg);

  Map<String, String> _authHeaders() => {
    'content-type': 'application/json',
    'Authorization': 'Bearer ${config.tokenProvider()}',
  };

  // ── Defaulted hooks ──

  String _initEndpoint(Map<String, dynamic>? extraFields) =>
      config.buildInitEndpoint?.call(extraFields) ?? config.initUploadEndpoint;

  Map<String, dynamic> _buildInitBody(
    String fileName,
    Map<String, dynamic>? extraFields,
  ) =>
      config.buildInitBody?.call(fileName, extraFields) ??
      defaultInitBody(fileName, extraFields);

  InitUploadResponse _parseInit(Map<String, dynamic> json) =>
      config.parseInitResponse?.call(json) ?? InitUploadResponse.fromJson(json);

  Map<String, dynamic> _buildCompleteBody(
    String s3UploadId,
    List<PartETag> parts,
  ) =>
      config.buildCompleteBody?.call(s3UploadId, parts) ??
      defaultCompleteBody(s3UploadId, parts);

  String? _parseComplete(Map<String, dynamic> json) =>
      config.parseCompleteResponse?.call(json) ?? defaultParseComplete(json);

  Map<String, dynamic> _buildAbortBody(String s3UploadId, {String? s3Key}) {
    final base = config.buildAbortBody?.call(s3UploadId) ??
        defaultAbortBody(s3UploadId);
    if (s3Key != null && s3Key.isNotEmpty) {
      return {...base, 'key': s3Key};
    }
    return base;
  }

  String? _extractETag(Map<String, String> headers) =>
      config.extractETag?.call(headers) ?? defaultExtractETag(headers);

  // ──────────────────────────────────────────────
  //  Public API
  // ──────────────────────────────────────────────

  @override
  Future<InitUploadResponse?> initUpload({
    required String filePath,
    Map<String, dynamic>? extraFields,
  }) async {
    final token = config.tokenProvider();
    if (token.isEmpty) {
      _log('[DartHttpEngine] No auth token');
      return null;
    }

    final fileName = filePath.split(Platform.pathSeparator).last;
    final payload = _buildInitBody(fileName, extraFields);
    final endpoint = _initEndpoint(extraFields);

    for (int retry = 0; retry < 3; retry++) {
      try {
        _log(
          '[DartHttpEngine] initUpload attempt ${retry + 1}: POST $endpoint',
        );
        _log('[DartHttpEngine] initUpload body: ${jsonEncode(payload)}');
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: _authHeaders(),
              body: jsonEncode(payload),
            )
            .timeout(config.apiTimeout);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          return _parseInit(decoded);
        }
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      } on SocketException {
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      } on http.ClientException {
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      }
    }
    _log('[DartHttpEngine] initUpload failed after 3 retries');
    return null;
  }

  @override
  Future<bool> directUpload({
    required String filePath,
    required String uploadUrl,
    void Function(double progress)? onProgress,
    int? dbTaskId,
  }) async {
    try {
      final file = File(filePath);
      final fileSize = await file.length();
      final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
      request.contentLength = fileSize;

      final stream = file.openRead();
      final stopwatch = Stopwatch();
      if (config.maxBytesPerSecond > 0) stopwatch.start();
      int bytesSent = 0;
      await for (final chunk in stream) {
        request.sink.add(chunk);
        bytesSent += chunk.length;
        onProgress?.call(fileSize > 0 ? bytesSent / fileSize : 0);

        if (config.maxBytesPerSecond > 0) {
          final int elapsed = stopwatch.elapsedMilliseconds;
          final int expected = (bytesSent * 1000) ~/ config.maxBytesPerSecond;
          final int delay = expected - elapsed;
          if (delay > 0) await Future.delayed(Duration(milliseconds: delay));
        }
      }
      await request.sink.close();

      final response = await _client.send(request).timeout(config.partUploadTimeout);
      return response.statusCode == 200;
    } catch (e) {
      _log('[DartHttpEngine] directUpload error: $e');
      return false;
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
    final file = File(filePath);
    final fileSize = await file.length();
    final results = <PartUploadResult>[];

    final sorted = List<PartPresignedUrl>.from(parts)
      ..sort((a, b) => a.partNumber.compareTo(b.partNumber));

    for (int i = 0; i < sorted.length; i += config.maxConcurrentParts) {
      final batch = sorted.skip(i).take(config.maxConcurrentParts).toList();
      final batchFutures = batch.map((part) => _uploadSinglePart(
            file: file,
            fileSize: fileSize,
            partNumber: part.partNumber,
            uploadUrl: part.uploadUrl,
            partSize: partSize,
          ));
      final batchResults = await Future.wait(batchFutures);
      for (final result in batchResults) {
        results.add(result);
      }
      onProgress?.call(results.length, sorted.length);
    }
    return results;
  }

  Future<PartUploadResult> _uploadSinglePart({
    required File file,
    required int fileSize,
    required int partNumber,
    required String uploadUrl,
    required int partSize,
  }) async {
    for (int attempt = 0; attempt < config.maxPartRetries; attempt++) {
      try {
        final startByte = (partNumber - 1) * partSize;
        final endByte = min(startByte + partSize, fileSize);
        final partLength = endByte - startByte;

        // Stream the file directly — O(1) memory, no RAM spike
        var stream = file.openRead(startByte, endByte);
        final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
        request.contentLength = partLength;

        // Apply bandwidth throttle if configured
        if (config.maxBytesPerSecond > 0) {
          stream = stream.transform(_throttleTransformer());
        }
        await stream.pipe(request.sink);

        final response =
            await _client.send(request).timeout(config.partUploadTimeout);

        if (response.statusCode == 200) {
          final eTag = _extractETag(response.headers);
          return PartUploadResult(
            partNumber: partNumber,
            success: true,
            eTag: eTag,
          );
        }

        // 403 = presigned URL expired — don't waste retries
        if (response.statusCode == 403) {
          _log('[DartHttpEngine] part #$partNumber URL expired (403)');
          return PartUploadResult(
            partNumber: partNumber,
            success: false,
            errorMessage: 'Presigned URL expired',
            isUrlExpired: true,
          );
        }
      } catch (e) {
        _log('[DartHttpEngine] part #$partNumber attempt ${attempt + 1} failed: $e');
        if (attempt < config.maxPartRetries - 1) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
    }
    return PartUploadResult(
      partNumber: partNumber,
      success: false,
      errorMessage: 'Failed after ${config.maxPartRetries} retries',
    );
  }

  @override
  Future<String?> completeMultipart({
    required String s3UploadId,
    required List<PartETag> parts,
    String? endpoint,
    Map<String, dynamic>? extraFields,
  }) async {
    final token = config.tokenProvider();
    if (token.isEmpty) return null;

    final url = endpoint ?? config.initUploadEndpoint;

    for (int retry = 0; retry < 3; retry++) {
      try {
        final baseBody = _buildCompleteBody(s3UploadId, parts);
        final merged = extraFields == null
            ? baseBody
            : {...baseBody, ...extraFields};
        final body = jsonEncode(merged);
        _log('[DartHttpEngine] completeMultipart attempt ${retry + 1}: POST $url');
        _log('[DartHttpEngine] completeMultipart body: $body');
        final response = await _client
            .post(
              Uri.parse(url),
              headers: _authHeaders(),
              body: body,
            )
            .timeout(config.apiTimeout);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final fileUrl = _parseComplete(decoded);
          if (fileUrl != null) return fileUrl;
        }
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      } catch (e) {
        _log('[DartHttpEngine] completeMultipart attempt ${retry + 1} error: $e');
        if (retry < 2) {
          await Future.delayed(Duration(seconds: 2 * (retry + 1)));
        }
      }
    }
    return null;
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
        final body = jsonEncode(_buildAbortBody(s3UploadId, s3Key: s3Key));
        _log('[DartHttpEngine] abortMultipart attempt ${retry + 1}: POST $url');
        _log('[DartHttpEngine] abortMultipart body: $body');
        final response = await _client
            .post(
              Uri.parse(url),
              headers: _authHeaders(),
              body: body,
            )
            .timeout(config.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return true;
        }
        _log('[DartHttpEngine] abortMultipart attempt ${retry + 1} status=${response.statusCode}');
      } catch (e) {
        _log('[DartHttpEngine] abortMultipart attempt ${retry + 1} error: $e');
      }
      if (retry < 2) {
        await Future.delayed(Duration(seconds: retry + 1));
      }
    }
    return false;
  }

  @override
  Future<InitUploadResponse?> refreshPresignedUrls({
    required String filePath,
    required String s3UploadId,
    required List<int> partNumbers,
    Map<String, dynamic>? extraFields,
  }) async {
    // Pass the existing s3UploadId to the backend so it can return
    // fresh presigned URLs for the same multipart session.
    final refreshFields = <String, dynamic>{
      if (extraFields != null) ...extraFields,
      's3UploadId': s3UploadId,
      'refreshParts': partNumbers,
    };
    return initUpload(filePath: filePath, extraFields: refreshFields);
  }

  @override
  Future<bool> sendCallback(CallbackRequest callback, {int? dbTaskId}) async {
    for (int retry = 0; retry < 3; retry++) {
      try {
        final token = config.tokenProvider();
        if (token.isEmpty) return false;

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        };
        if (callback.idempotencyKey != null) {
          headers['Idempotency-Key'] = callback.idempotencyKey!;
        }
        final body = jsonEncode(callback.body);
        _log('[DartHttpEngine] sendCallback attempt ${retry + 1}: POST ${callback.url}');
        _log('[DartHttpEngine] sendCallback body: $body');
        final response = await _client
            .post(
              Uri.parse(callback.url),
              headers: headers,
              body: body,
            )
            .timeout(config.apiTimeout);
        final ok = response.statusCode == 200 ||
            response.statusCode == 201 ||
            response.statusCode == 409;
        if (ok) return true;
        _log('[DartHttpEngine] sendCallback attempt ${retry + 1} status=${response.statusCode}');
      } catch (e) {
        _log('[DartHttpEngine] sendCallback attempt ${retry + 1} error: $e');
      }
      if (retry < 2) {
        await Future.delayed(Duration(seconds: retry + 1));
      }
    }
    return false;
  }

  /// Returns a [StreamTransformer] that paces bytes according to
  /// [config.maxBytesPerSecond]. The transformer measures elapsed time
  /// and inserts delays between chunks to stay within the rate limit.
  StreamTransformer<List<int>, List<int>> _throttleTransformer() {
    int bytesSinceLastDelay = 0;
    int lastReportMs = 0;
    return StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) async {
        sink.add(data);
        bytesSinceLastDelay += data.length;
        if (config.maxBytesPerSecond <= 0) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - lastReportMs;
        final allowedBytes = (config.maxBytesPerSecond * elapsed) ~/ 1000;
        if (bytesSinceLastDelay > allowedBytes) {
          final excessBytes = bytesSinceLastDelay - allowedBytes;
          final extraMs = (excessBytes * 1000) ~/ config.maxBytesPerSecond;
          if (extraMs > 0) {
            await Future.delayed(Duration(milliseconds: extraMs.clamp(1, 5000)));
          }
        }
      },
    );
  }
}
