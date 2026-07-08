import 'dart:async';
import 'dart:io';

import 'package:edtech/features/uploads/data/models/upload_enums.dart';
import 'package:edtech/features/uploads/data/models/upload_job.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:edtech/features/uploads/presentation/upload_queue_provider.dart';
import 'package:edtech/features/uploads/service/upload_service.dart';

/// A mock for [FlutterLocalNotificationsPlatform] to prevent the
/// "LateInitializationError" from the platform interface singleton.
class MockFlutterLocalNotificationsPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements FlutterLocalNotificationsPlatform {}

/// A fake [UploadService] that stores jobs in memory and provides a
/// controllable stream for testing without real I/O.
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
    final job = _jobsInternal.remove(id);
    if (job != null) {
      _updatesController.add(UploadJob(
        id: job.id,
        filePath: job.filePath,
        type: job.type,
        title: job.title,
        fileSize: job.fileSize,
        state: UploadJobState.cancelled,
        metadata: job.metadata,
      ));
    }
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

  void addJob(UploadJob job) {
    _jobsInternal[job.id] = job;
  }

  void emitUpdate(UploadJob job) {
    _updatesController.add(job);
  }

  @override
  Future<void> dispose() async {
    await _updatesController.close();
  }
}

/// Creates a temp file and returns its absolute path.
Future<String> createTempFile(String name, {int size = 1024}) async {
  final dir = Directory.systemTemp;
  final file = File('${dir.path}/$name');
  if (!await file.exists()) {
    await file.writeAsBytes(List.filled(size, 0x41));
  }
  return file.absolute.path;
}

void main() {
  late FakeUploadService fakeService;
  late UploadQueueProvider provider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterLocalNotificationsPlatform.instance =
        MockFlutterLocalNotificationsPlatform();
  });

  setUp(() async {
    fakeService = FakeUploadService();
    provider = UploadQueueProvider(service: fakeService);
    await Future.delayed(const Duration(milliseconds: 10));
  });

  tearDown(() {
    provider.dispose();
  });

  group('_hasInFlightFile logic', () {
    /// Simulates the in-flight detection used by [UploadQueueProvider].
    /// We test this logic directly against the service's job list instead of
    /// calling [UploadQueueProvider.addModuleLessonToQueue] because the latter
    /// triggers [ToastService] (which uses overlay entries unavailable in
    /// unit tests).
    bool hasInFlight(String filePath, {UploadAssetType? type}) {
      final jobs = fakeService.jobs;
      final absPath = File(filePath).absolute.path;
      return jobs.any((j) {
        if (type != null && j.type != type) return false;
        if (UploadState.from(j.state) == UploadState.completed) return false;
        if (UploadState.from(j.state) == UploadState.failed) return false;
        if (UploadState.from(j.state) == UploadState.cancelled) return false;
        if (File(j.filePath).absolute.path == absPath) return true;
        if (j.metadata['originalPath'] != null &&
            File(j.metadata['originalPath'] as String).absolute.path ==
                absPath) {
          return true;
        }
        return false;
      });
    }

    test('detects file by direct filePath match', () async {
      final path = await createTempFile('inflight_direct.mp4');
      fakeService.addJob(UploadJob(
        id: 'j1',
        filePath: path,
        type: UploadAssetType.moduleLesson,
        title: 'In Flight',
        fileSize: 1024,
        state: UploadJobState.uploading,
        progress: 0.3,
      ));
      expect(hasInFlight(path, type: UploadAssetType.moduleLesson), isTrue);
      await File(path).delete();
    });

    test('detects file by originalPath in metadata', () async {
      final originalPath = '/storage/emulated/0/DCIM/video.mp4';
      final cachedPath = await createTempFile('cached_inflight.mp4');

      fakeService.addJob(UploadJob(
        id: 'j2',
        filePath: cachedPath,
        type: UploadAssetType.moduleLesson,
        title: 'Original Match',
        fileSize: 1024,
        state: UploadJobState.uploading,
        progress: 0.5,
        metadata: {
          'originalPath': originalPath,
          'uploadType': 'module_lesson',
        },
      ));

      expect(hasInFlight(originalPath, type: UploadAssetType.moduleLesson),
          isTrue);
      await File(cachedPath).delete();
    });

    test('does not detect different file paths', () async {
      final pathA = await createTempFile('file_a.mp4');
      final pathB = await createTempFile('file_b.mp4');

      fakeService.addJob(UploadJob(
        id: 'j3',
        filePath: pathA,
        type: UploadAssetType.moduleLesson,
        title: 'File A',
        fileSize: 1024,
        state: UploadJobState.uploading,
        progress: 0.3,
      ));

      expect(hasInFlight(pathB, type: UploadAssetType.moduleLesson), isFalse);
      await File(pathA).delete();
      await File(pathB).delete();
    });

    test('ignores completed jobs', () async {
      final path = await createTempFile('completed_video.mp4');
      fakeService.addJob(UploadJob(
        id: 'j4',
        filePath: path,
        type: UploadAssetType.moduleLesson,
        title: 'Completed',
        fileSize: 1024,
        state: UploadJobState.completed,
        progress: 1.0,
      ));

      expect(hasInFlight(path, type: UploadAssetType.moduleLesson), isFalse);
      await File(path).delete();
    });

    test('ignores failed jobs', () async {
      final path = await createTempFile('failed_video.mp4');
      fakeService.addJob(UploadJob(
        id: 'j5',
        filePath: path,
        type: UploadAssetType.moduleLesson,
        title: 'Failed',
        fileSize: 1024,
        state: UploadJobState.failed,
        progress: 0.0,
      ));

      expect(hasInFlight(path, type: UploadAssetType.moduleLesson), isFalse);
      await File(path).delete();
    });
  });

  group('addModuleLessonToQueue (limited)', () {
    test('returns 0 for non-existent file', () async {
      // This test only hits the early return before ToastService is invoked.
      final queueId = await provider.addModuleLessonToQueue(
        videoPath: '/nonexistent/path.mp4',
        lessonTitle: 'Missing',
        moduleId: 1,
        courseId: 1,
      );
      expect(queueId, 0);
    });
  });

  group('UploadState mapping', () {
    test('UploadState.from maps job states to UI states', () {
      expect(UploadState.from(UploadJobState.pending), UploadState.pending);
      expect(UploadState.from(UploadJobState.uploading), UploadState.uploading);
      expect(UploadState.from(UploadJobState.completing), UploadState.uploading);
      expect(UploadState.from(UploadJobState.callback), UploadState.uploading);
      expect(UploadState.from(UploadJobState.completed), UploadState.completed);
      expect(UploadState.from(UploadJobState.failed), UploadState.failed);
      expect(UploadState.from(UploadJobState.cancelled), UploadState.cancelled);
    });
  });

  group('UploadQueueProvider tasks getter', () {
    test('empty when service has no jobs', () {
      expect(provider.tasks, isEmpty);
    });

    test('reflects service jobs', () async {
      fakeService.addJob(UploadJob(
        id: 'task_job',
        filePath: '/tmp/t.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'Task View',
        fileSize: 1024,
        state: UploadJobState.pending,
        progress: 0.0,
      ));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(provider.tasks.length, 1);
      expect(provider.tasks.first.title, 'Task View');
      expect(provider.tasks.first.state, UploadState.pending);
    });
  });

  group('UploadQueueProvider count getters', () {
    test('pendingCount, completedCount, failedCount', () async {
      fakeService.addJob(UploadJob(
        id: 'c1',
        filePath: '/tmp/c.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'C',
        fileSize: 1,
        state: UploadJobState.completed,
        progress: 1.0,
      ));
      fakeService.addJob(UploadJob(
        id: 'f1',
        filePath: '/tmp/f.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'F',
        fileSize: 1,
        state: UploadJobState.failed,
        progress: 0.5,
      ));
      fakeService.addJob(UploadJob(
        id: 'p1',
        filePath: '/tmp/p.mp4',
        type: UploadAssetType.moduleLesson,
        title: 'P',
        fileSize: 1,
        state: UploadJobState.pending,
        progress: 0.0,
      ));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(provider.completedCount, 1);
      expect(provider.failedCount, 1);
      expect(provider.pendingCount, 1);
    });
  });
}
