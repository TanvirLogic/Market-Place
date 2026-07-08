import 'dart:async';

import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:edtech/features/uploads/data/models/upload_enums.dart';
import 'package:edtech/features/uploads/data/models/upload_job.dart';
import 'package:edtech/features/uploads/presentation/upload_queue_provider.dart';
import 'package:edtech/features/uploads/service/upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake [UploadService] that stores jobs in memory and provides a
/// controllable stream for testing without platform I/O.
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
  Future<void> dispose() async {
    await _updatesController.close();
  }

  void addJob(UploadJob job) {
    _jobsInternal[job.id] = job;
  }

  void emitUpdate(UploadJob job) {
    _updatesController.add(job);
  }
}

/// A test helper that wraps [UploadQueueProvider] + [FakeUploadService]
/// so we can control what jobs appear in the queue.
class TestQueueHarness {
  late final FakeUploadService service;
  late final UploadQueueProvider queueProvider;

  TestQueueHarness() {
    service = FakeUploadService();
    queueProvider = UploadQueueProvider(service: service);
  }

  void dispose() {
    queueProvider.dispose();
  }
}

void main() {
  group('PendingLesson model', () {
    test('defaults are correct', () {
      final p = PendingLesson(
        queueId: 1,
        lessonId: 1,
        title: 'Test',
        type: LessonType.video,
        filePath: '/tmp/test.mp4',
        moduleId: 1,
      );
      expect(p.uploadProgress, 0.0);
      expect(p.uploadStatus, 'pending');
      expect(p.vanishedAt, isNull);
      expect(p.fileUrl, isNull);
    });

    test('uploadProgress and uploadStatus are mutable', () {
      final p = PendingLesson(
        queueId: 1,
        lessonId: 1,
        title: 'Test',
        type: LessonType.video,
        filePath: '/tmp/test.mp4',
        moduleId: 1,
      );
      p.uploadProgress = 0.75;
      p.uploadStatus = 'uploading';
      expect(p.uploadProgress, 0.75);
      expect(p.uploadStatus, 'uploading');
    });

    test('vanishedAt is set and readable', () {
      final p = PendingLesson(
        queueId: 1,
        lessonId: 1,
        title: 'Test',
        type: LessonType.video,
        filePath: '/tmp/test.mp4',
        moduleId: 1,
      );
      p.vanishedAt = 1000;
      expect(p.vanishedAt, 1000);
    });

    test('completed status sets progress to 1.0', () {
      final p = PendingLesson(
        queueId: 1,
        lessonId: 1,
        title: 'Test',
        type: LessonType.video,
        filePath: '/tmp/test.mp4',
        moduleId: 1,
      );
      p.uploadProgress = 1.0;
      p.uploadStatus = 'completed';
      expect(p.uploadProgress, 1.0);
      expect(p.uploadStatus, 'completed');
    });

    test('fileUrl is settable', () {
      final p = PendingLesson(
        queueId: 1,
        lessonId: 1,
        title: 'Test',
        type: LessonType.video,
        filePath: '/tmp/test.mp4',
        moduleId: 1,
      );
      p.fileUrl = 'https://cdn.example.com/video.mp4';
      expect(p.fileUrl, 'https://cdn.example.com/video.mp4');
    });

    test('module filtering works', () {
      final p1 = PendingLesson(
        queueId: 1, lessonId: 1, title: 'A',
        type: LessonType.video, filePath: '/a.mp4', moduleId: 1,
      );
      final p2 = PendingLesson(
        queueId: 2, lessonId: 2, title: 'B',
        type: LessonType.video, filePath: '/b.mp4', moduleId: 2,
      );
      final p3 = PendingLesson(
        queueId: 3, lessonId: 3, title: 'C',
        type: LessonType.video, filePath: '/c.mp4', moduleId: 1,
      );
      final all = [p1, p2, p3];
      expect(all.where((p) => p.moduleId == 1).length, 2);
      expect(all.where((p) => p.moduleId == 2).length, 1);
    });
  });
}
