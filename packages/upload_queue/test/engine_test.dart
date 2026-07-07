import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:upload_queue/src/dart_http_engine.dart';
import 'package:upload_queue/src/engine.dart';
import 'package:upload_queue/src/models/upload_config.dart';
import 'package:upload_queue/src/models/upload_response.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  http.Response _jsonResponse(Map<String, dynamic> body, int status) =>
      http.Response(jsonEncode(body), status);

  http.Response _emptyJson(int status) => http.Response('{}', status);

  UploadConfig _config({
    String Function()? tokenProvider,
    String? initEndpoint,
    void Function(String)? logger,
  }) {
    return UploadConfig(
      initUploadEndpoint: initEndpoint ?? 'https://api.example.com/init',
      tokenProvider: tokenProvider ?? (() => 'test-token'),
      logger: logger ?? ((_) {}),
    );
  }

  group('initUpload', () {
    test('returns InitUploadResponse on 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://api.example.com/init');
        expect(request.headers['Authorization'], 'Bearer test-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect((body['filename'] as String).endsWith('video.mp4'), isTrue);
        return _jsonResponse({
          'isMultipart': true,
          'fileUrl': 'https://cdn.example.com/video.mp4',
          'uploadId': 'upload-123',
          'totalParts': 3,
          'parts': [
            {'partNumber': 1, 'uploadUrl': 'https://s3.example.com/part1'},
            {'partNumber': 2, 'uploadUrl': 'https://s3.example.com/part2'},
          ],
        }, 200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.initUpload(filePath: '/path/to/video.mp4');
      expect(result, isNotNull);
      expect(result!.isMultipart, isTrue);
      expect(result.fileUrl, 'https://cdn.example.com/video.mp4');
      expect(result.s3UploadId, 'upload-123');
      expect(result.parts.length, 2);
    });

    test('returns null on empty token', () async {
      final client = MockClient((_) async => _emptyJson(200));
      final engine = DartHttpEngine(
        _config(tokenProvider: () => ''),
        httpClient: client,
      );
      final result = await engine.initUpload(filePath: '/path/to/v.mp4');
      expect(result, isNull);
    });

    test('retries on 500 then succeeds', () async {
      int callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (callCount == 1) return _emptyJson(500);
        return _jsonResponse({
          'isMultipart': false,
          'fileUrl': 'https://cdn.example.com/v.mp4',
          'uploadUrl': 'https://s3.example.com/put',
        }, 200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.initUpload(filePath: '/path/to/v.mp4');
      expect(result, isNotNull);
      expect(callCount, 2);
    });

    test('returns null after all retries fail', () async {
      final client = MockClient((_) async => _emptyJson(500));
      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.initUpload(filePath: '/path/to/v.mp4');
      expect(result, isNull);
    });

    test('returns null on SocketException retries', () async {
      int callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        throw const SocketException('Connection refused');
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.initUpload(filePath: '/path/to/v.mp4');
      expect(result, isNull);
      expect(callCount, 3);
    });

    test('custom buildInitEndpoint is used', () async {
      String? usedEndpoint;
      final client = MockClient((request) async {
        usedEndpoint = request.url.toString();
        return _jsonResponse({
          'isMultipart': false,
          'fileUrl': 'https://cdn.example.com/v.mp4',
        }, 200);
      });

      final engine = DartHttpEngine(
        UploadConfig(
          initUploadEndpoint: 'https://api.example.com/default',
          tokenProvider: () => 'test-token',
          buildInitEndpoint: (extra) => 'https://custom.example.com/init',
          logger: (_) {},
        ),
        httpClient: client,
      );
      await engine.initUpload(
        filePath: '/path/to/v.mp4',
        extraFields: {'uploadType': 'custom'},
      );
      expect(usedEndpoint, 'https://custom.example.com/init');
    });
  });

  group('completeMultipart', () {
    test('returns fileUrl on success', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['uploadId'], 'upload-123');
        expect((body['parts'] as List).length, 2);
        return _jsonResponse({
          'fileUrl': 'https://cdn.example.com/final.mp4',
        }, 200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.completeMultipart(
        s3UploadId: 'upload-123',
        parts: [
          PartETag(partNumber: 1, eTag: 'e1'),
          PartETag(partNumber: 2, eTag: 'e2'),
        ],
      );
      expect(result, 'https://cdn.example.com/final.mp4');
    });

    test('merges key + extraFields into complete body', () async {
      Map<String, dynamic>? sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _jsonResponse({'fileUrl': 'https://cdn.example.com/f.mp4'}, 200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      await engine.completeMultipart(
        s3UploadId: 'upload-123',
        parts: [PartETag(partNumber: 1, eTag: 'e1')],
        extraFields: {'key': 'videos/uuid.mp4'},
      );

      expect(sentBody?['uploadId'], 'upload-123');
      expect(sentBody?['key'], 'videos/uuid.mp4');
      expect((sentBody?['parts'] as List).length, 1);
    });

    test('abort body includes key and uploadId', () async {
      Map<String, dynamic>? sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _emptyJson(200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      final ok = await engine.abortMultipart(
        'upload-123',
        s3Key: 'videos/uuid.mp4',
      );

      expect(ok, isTrue);
      expect(sentBody?['uploadId'], 'upload-123');
      expect(sentBody?['key'], 'videos/uuid.mp4');
    });

    test('returns null on empty token', () async {
      final client = MockClient((_) async => _emptyJson(200));
      final engine = DartHttpEngine(
        _config(tokenProvider: () => ''),
        httpClient: client,
      );
      final result = await engine.completeMultipart(
        s3UploadId: 'upload-123',
        parts: [],
      );
      expect(result, isNull);
    });

    test('returns null on 500', () async {
      final client = MockClient((_) async => _emptyJson(500));
      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.completeMultipart(
        s3UploadId: 'upload-123',
        parts: [],
      );
      expect(result, isNull);
    });
  });

  group('abortMultipart', () {
    test('returns true on 200', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        return _emptyJson(200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.abortMultipart('upload-123');
      expect(result, isTrue);
    });

    test('returns false on empty token', () async {
      final client = MockClient((_) async => _emptyJson(200));
      final engine = DartHttpEngine(
        _config(tokenProvider: () => ''),
        httpClient: client,
      );
      final result = await engine.abortMultipart('upload-123');
      expect(result, isFalse);
    });

    test('uses custom endpoint', () async {
      String? usedUrl;
      final client = MockClient((request) async {
        usedUrl = request.url.toString();
        return _emptyJson(200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      await engine.abortMultipart(
        'upload-123',
        endpoint: 'https://custom.example.com/abort',
      );
      expect(usedUrl, 'https://custom.example.com/abort');
    });
  });

  group('sendCallback', () {
    test('returns true on 200', () async {
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.headers['Idempotency-Key'], isNull);
        return _emptyJson(200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.sendCallback(
        CallbackRequest(
          url: 'https://api.example.com/callback',
          body: {'videoUrl': 'https://cdn.example.com/v.mp4'},
        ),
      );
      expect(result, isTrue);
    });

    test('sends idempotency key when provided', () async {
      String? sentKey;
      final client = MockClient((request) async {
        sentKey = request.headers['Idempotency-Key'];
        return _emptyJson(200);
      });

      final engine = DartHttpEngine(_config(), httpClient: client);
      await engine.sendCallback(
        CallbackRequest(
          url: 'https://api.example.com/callback',
          body: {},
          idempotencyKey: 'unique-key-123',
        ),
      );
      expect(sentKey, 'unique-key-123');
    });

    test('accepts 409 as success (already processed)', () async {
      final client = MockClient((_) async => _emptyJson(409));

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.sendCallback(
        CallbackRequest(url: 'https://api.example.com/callback', body: {}),
      );
      expect(result, isTrue);
    });

    test('returns false after retries fail', () async {
      final client = MockClient((_) async => _emptyJson(500));

      final engine = DartHttpEngine(_config(), httpClient: client);
      final result = await engine.sendCallback(
        CallbackRequest(url: 'https://api.example.com/callback', body: {}),
      );
      expect(result, isFalse);
    });

    test('returns false on empty token', () async {
      final client = MockClient((_) async => _emptyJson(200));
      final engine = DartHttpEngine(
        _config(tokenProvider: () => ''),
        httpClient: client,
      );
      final result = await engine.sendCallback(
        CallbackRequest(url: 'https://api.example.com/callback', body: {}),
      );
      expect(result, isFalse);
    });
  });

  group('computePartSize', () {
    test('returns 5MB default for zero totalParts', () {
      expect(UploadEngine.computePartSize(1024 * 1024 * 100, 0),
          5 * 1024 * 1024);
    });

    test('divides file size by total parts', () {
      expect(UploadEngine.computePartSize(1000, 5), 200);
    });

    test('rounds up to ensure all bytes covered', () {
      expect(UploadEngine.computePartSize(1001, 5), 201);
    });
  });

  group('defaultExtractETag', () {
    test('preserves S3 canonical quotes verbatim', () {
      expect(
        DartHttpEngine.defaultExtractETag({'etag': '"abc123def456"'}),
        '"abc123def456"',
      );
    });

    test('reads capitalized Etag header too', () {
      expect(
        DartHttpEngine.defaultExtractETag({'Etag': '"xyz"'}),
        '"xyz"',
      );
    });

    test('returns null when absent', () {
      expect(DartHttpEngine.defaultExtractETag({}), isNull);
    });
  });
}
