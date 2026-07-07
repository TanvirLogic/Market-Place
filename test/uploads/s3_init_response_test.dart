import 'package:edtech/features/uploads/data/models/s3_init_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('S3InitResponse.fromEnvelope — direct', () {
    test('parses a direct (single PUT) response', () {
      final json = {
        'data': {
          'isMultipart': false,
          'uploadUrl': 'https://s3/put',
          'fileUrl': 'https://cdn/file.jpg',
          'key': 'images/file.jpg',
          'expiresIn': '24 hours',
        }
      };
      final r = S3InitResponse.fromEnvelope(json);
      expect(r.isMultipart, isFalse);
      expect(r.uploadUrl, 'https://s3/put');
      expect(r.fileUrl, 'https://cdn/file.jpg');
      expect(r.key, 'images/file.jpg');
      expect(r.s3UploadId, isNull);
      expect(r.parts, isEmpty);
    });
  });

  group('S3InitResponse.fromEnvelope — multipart', () {
    test('parses parts, uploadId and totalParts', () {
      final json = {
        'data': {
          'isMultipart': true,
          'fileUrl': 'https://cdn/video.mp4',
          'key': 'videos/video.mp4',
          'uploadId': 'abc123',
          'totalParts': 3,
          'parts': [
            {'partNumber': 1, 'uploadUrl': 'https://s3/p1'},
            {'partNumber': 2, 'uploadUrl': 'https://s3/p2'},
            {'partNumber': 3, 'uploadUrl': 'https://s3/p3'},
          ],
        }
      };
      final r = S3InitResponse.fromEnvelope(json);
      expect(r.isMultipart, isTrue);
      expect(r.s3UploadId, 'abc123');
      expect(r.totalParts, 3);
      expect(r.parts.map((p) => p.partNumber), [1, 2, 3]);
      expect(r.parts[1].uploadUrl, 'https://s3/p2');
    });

    test('falls back to parts.length when totalParts missing', () {
      final json = {
        'data': {
          'isMultipart': true,
          'fileUrl': 'https://cdn/v.mp4',
          'uploadId': 'x',
          'parts': [
            {'partNumber': 1, 'uploadUrl': 'u1'},
            {'partNumber': 2, 'uploadUrl': 'u2'},
          ],
        }
      };
      final r = S3InitResponse.fromEnvelope(json);
      expect(r.totalParts, 2);
    });
  });

  group('S3InitResponse.fromEnvelope — nested course shape', () {
    final json = {
      'data': {
        'data': {
          'thumbnail': {
            'isMultipart': false,
            'uploadUrl': 'https://s3/thumb',
            'fileUrl': 'https://cdn/thumb.jpg',
            'key': 'thumb.jpg',
          },
          'video': {
            'isMultipart': true,
            'fileUrl': 'https://cdn/intro.mp4',
            'key': 'intro.mp4',
            'uploadId': 'vid1',
            'parts': [
              {'partNumber': 1, 'uploadUrl': 'https://s3/vp1'},
            ],
          },
        }
      }
    };

    test('selects the thumbnail section', () {
      final r = S3InitResponse.fromEnvelope(json, courseAssetKey: 'thumbnail');
      expect(r.isMultipart, isFalse);
      expect(r.uploadUrl, 'https://s3/thumb');
      expect(r.key, 'thumb.jpg');
    });

    test('selects the video section', () {
      final r = S3InitResponse.fromEnvelope(json, courseAssetKey: 'video');
      expect(r.isMultipart, isTrue);
      expect(r.s3UploadId, 'vid1');
      expect(r.parts.single.uploadUrl, 'https://s3/vp1');
    });
  });
}
