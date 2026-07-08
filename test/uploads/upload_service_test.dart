import 'dart:async';

import 'package:edtech/features/uploads/data/models/upload_enums.dart';
import 'package:edtech/features/uploads/data/models/upload_job.dart';
import 'package:edtech/features/uploads/service/upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal fake that extends [UploadService] but avoids platform I/O by
/// storing jobs in-memory and providing a controlled stream.
///
/// Because we can't override private methods like `_onEngineProgress` or
/// `_recoverJobs` from a different file, this fake focuses on the public API
/// contract. The private-method behaviours (progress cap, native polling,
/// recovery) are validated through model-level tests and integration tests.
class FakeUploadService extends UploadService {
  final _jobsInternal = <String, UploadJob>{};
  final _updatesController = StreamController<UploadJob>.broadcast();

  @override
  Stream<UploadJob> get updates => _updatesController.stream;

  @override
  List<UploadJob> get jobs => _jobsInternal.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  UploadJob? job(String id) => _jobsInternal[id];

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<UploadJob> enqueue({
    required String id,
    required String filePath,
    required UploadAssetType type,
    required String title,
    required int fileSize,
    Map<String, dynamic> metadata = const {},
  }) async {
    final job = UploadJob(
      id: id,
      filePath: filePath,
      type: type,
      title: title,
      fileSize: fileSize,
      metadata: Map<String, dynamic>.from(metadata),
    );
    _jobsInternal[id] = job;
    _updatesController.add(job);
    return job;
  }

  @override
  Future<void> cancel(String id) async {
    _jobsInternal.remove(id);
  }

  @override
  Future<void> remove(String id) async {
    _jobsInternal.remove(id);
  }

  @override
  Future<void> retry(String id) async {
    final job = _jobsInternal[id];
    if (job != null) {
      job.state = UploadJobState.pending;
      job.progress = 0.0;
      _updatesController.add(job);
    }
  }

  @override
  Future<void> dispose() async {
    await _updatesController.close();
  }
}

void main() {
  group('UploadService job lifecycle (via FakeUploadService)', () {
    late FakeUploadService service;

    setUp(() {
      service = FakeUploadService();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('enqueue creates and stores a job in pending state', () async {
      await service.enqueue(
        id: 'lifecycle_1',
        filePath: '/tmp/file.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'Lifecycle Test',
        fileSize: 1024,
      );
      final job = service.job('lifecycle_1');
      expect(job, isNotNull);
      expect(job!.state, UploadJobState.pending);
      expect(job.progress, 0.0);
      expect(job.type, UploadAssetType.moduleLesson);
    });

    test('enqueue emits a job update on the stream', () async {
      UploadJob? emitted;
      service.updates.listen((j) => emitted = j);

      await service.enqueue(
        id: 'stream_1',
        filePath: '/tmp/s.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'Stream Test',
        fileSize: 1,
      );
      await Future.delayed(const Duration(milliseconds: 10));
      expect(emitted, isNotNull);
      expect(emitted!.id, 'stream_1');
    });

    test('jobs are sorted by creation time (insertion order)', () async {
      await Future.wait([
        service.enqueue(
          id: 'j3',
          filePath: '/tmp/c.mp4',
          type: UploadAssetType.moduleLesson,
          title: 'C',
          fileSize: 1,
        ),
        service.enqueue(
          id: 'j1',
          filePath: '/tmp/a.mp4',
          type: UploadAssetType.moduleLesson,
          title: 'A',
          fileSize: 1,
        ),
        service.enqueue(
          id: 'j2',
          filePath: '/tmp/b.mp4',
          type: UploadAssetType.moduleLesson,
          title: 'B',
          fileSize: 1,
        ),
      ]);
      await Future.delayed(const Duration(milliseconds: 50));
      final jobs = service.jobs;
      expect(jobs.length, 3);
      expect(jobs[0].id, 'j3');
      expect(jobs[1].id, 'j1');
      expect(jobs[2].id, 'j2');
    });

    test('cancel removes the job', () async {
      await service.enqueue(
        id: 'cancel_1',
        filePath: '/tmp/v.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'Cancel Me',
        fileSize: 1,
      );
      await service.cancel('cancel_1');
      expect(service.job('cancel_1'), isNull);
    });

    test('retry resets a terminal job to pending', () async {
      await service.enqueue(
        id: 'retry_1',
        filePath: '/tmp/v.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'Retry Me',
        fileSize: 1,
      );
      // Mark terminal (simulating upstream set).
      final job = service.job('retry_1')!;
      job.state = UploadJobState.failed;
      job.progress = 0.5;

      await service.retry('retry_1');
      final rest = service.job('retry_1');
      expect(rest!.state, UploadJobState.pending);
      expect(rest.progress, 0.0);
    });

    test('remove cleans up the job', () async {
      await service.enqueue(
        id: 'rm_1',
        filePath: '/tmp/r.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'Remove Me',
        fileSize: 1,
      );
      expect(service.job('rm_1'), isNotNull);
      await service.remove('rm_1');
      expect(service.job('rm_1'), isNull);
    });
  });
}
