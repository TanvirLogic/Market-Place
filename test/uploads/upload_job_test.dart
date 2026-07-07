import 'package:edtech/features/uploads/data/models/s3_init_response.dart';
import 'package:edtech/features/uploads/data/models/upload_enums.dart';
import 'package:edtech/features/uploads/data/models/upload_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('S3 size rule (15 MB)', () {
    test('files below 15 MiB predict direct upload', () {
      final job = _job(fileSize: 15 * 1024 * 1024 - 1);
      expect(job.predictedMultipart, isFalse);
    });

    test('files at or above 15 MiB predict multipart', () {
      final atThreshold = _job(fileSize: 15 * 1024 * 1024);
      final above = _job(fileSize: 500 * 1024 * 1024);
      expect(atThreshold.predictedMultipart, isTrue);
      expect(above.predictedMultipart, isTrue);
    });

    test('threshold constant is exactly 15 MiB', () {
      expect(kMultipartThresholdBytes, 15 * 1024 * 1024);
    });
  });

  group('UploadPart range header', () {
    test('bounded part emits inclusive byte range', () {
      final p = UploadPart(
        partNumber: 1,
        rangeStart: 0,
        rangeEnd: 104857599,
        uploadUrl: 'https://s3/part1',
      );
      expect(p.rangeHeader, 'bytes=0-104857599');
    });

    test('final part (rangeEnd -1) omits the end', () {
      final p = UploadPart(
        partNumber: 5,
        rangeStart: 419430400,
        rangeEnd: -1,
        uploadUrl: 'https://s3/part5',
      );
      expect(p.rangeHeader, 'bytes=419430400-');
    });

    test('done reflects presence of a non-empty eTag', () {
      final p = UploadPart(
          partNumber: 1, rangeStart: 0, rangeEnd: 9, uploadUrl: 'u');
      expect(p.done, isFalse);
      p.eTag = '"abc"';
      expect(p.done, isTrue);
    });
  });

  group('etagPayload', () {
    test('is ordered by part number and preserves quoted ETags', () {
      final job = _job(fileSize: 300 * 1024 * 1024);
      job.parts.addAll([
        UploadPart(
            partNumber: 2,
            rangeStart: 100,
            rangeEnd: 199,
            uploadUrl: 'u2',
            eTag: '"b"'),
        UploadPart(
            partNumber: 1,
            rangeStart: 0,
            rangeEnd: 99,
            uploadUrl: 'u1',
            eTag: '"a"'),
        UploadPart(
            partNumber: 3,
            rangeStart: 200,
            rangeEnd: -1,
            uploadUrl: 'u3'), // not done → excluded
      ]);

      final payload = job.etagPayload;
      expect(payload, [
        {'partNumber': 1, 'eTag': '"a"'},
        {'partNumber': 2, 'eTag': '"b"'},
      ]);
    });
  });

  group('UploadJob serialization', () {
    test('round-trips through toMap/fromMap', () {
      final job = _job(fileSize: 42);
      job.metadata['moduleId'] = 7;
      job.key = 'videos/x.mp4';
      job.s3UploadId = 'uid';
      job.parts.add(UploadPart(
          partNumber: 1,
          rangeStart: 0,
          rangeEnd: -1,
          uploadUrl: 'u',
          eTag: '"e"'));

      final restored = UploadJob.fromMap(job.toMap());
      expect(restored.id, job.id);
      expect(restored.type, job.type);
      expect(restored.key, 'videos/x.mp4');
      expect(restored.metadata['moduleId'], 7);
      expect(restored.parts.single.eTag, '"e"');
    });
  });
}

UploadJob _job({required int fileSize}) => UploadJob(
      id: 'job1',
      filePath: '/tmp/file.mp4',
      type: UploadAssetType.moduleLesson,
      title: 'Test',
      fileSize: fileSize,
    );
