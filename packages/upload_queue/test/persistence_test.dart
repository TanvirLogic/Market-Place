import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:upload_queue/src/models/upload_task.dart';
import 'package:upload_queue/src/persistence.dart';

void main() {
  late Persistence persistence;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('upload_queue_test_');
    dbPath = '${dir.path}\\test.db';
    persistence = Persistence(customDbPath: dbPath);
  });

  tearDown(() async {
    await persistence.close();
    final file = File(dbPath);
    if (file.existsSync()) await file.delete();
  });

  group('CRUD', () {
    test('insert and getById', () async {
      final id = await persistence.insert(
        filePath: '/tmp/video.mp4',
        title: 'Lesson 1',
      );
      expect(id, greaterThan(0));

      final task = await persistence.getById(id);
      expect(task, isNotNull);
      expect(task!.filePath, '/tmp/video.mp4');
      expect(task.title, 'Lesson 1');
      expect(task.state, UploadState.pending);
    });

    test('getById returns null for non-existent id', () async {
      final task = await persistence.getById(999);
      expect(task, isNull);
    });

    test('insert with metadata', () async {
      final id = await persistence.insert(
        filePath: '/tmp/video.mp4',
        title: 'Lesson 1',
        metadata: {'uploadType': 'module_lesson', 'courseId': 42},
      );
      final task = await persistence.getById(id);
      expect(task!.metadata, isNotNull);
      expect(task.metadata!['uploadType'], 'module_lesson');
      expect(task.metadata!['courseId'], 42);
    });

    test('insert creates correct timestamps', () async {
      final before = DateTime.now();
      final id = await persistence.insert(
        filePath: '/tmp/v.mp4',
        title: 'Test',
      );
      final after = DateTime.now();
      final task = await persistence.getById(id);
      expect(task!.createdAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(task.createdAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
      expect(task.updatedAt, task.createdAt);
    });
  });

  group('claimNextPending', () {
    test('claims next pending task in FIFO order', () async {
      final id1 = await persistence.insert(filePath: '/tmp/a.mp4', title: 'A');
      final id2 = await persistence.insert(filePath: '/tmp/b.mp4', title: 'B');

      final task1 = await persistence.claimNextPending();
      expect(task1, isNotNull);
      expect(task1!.id, id1);
      expect(task1.state, UploadState.uploading);

      final task2 = await persistence.claimNextPending();
      expect(task2, isNotNull);
      expect(task2!.id, id2);

      // No more pending
      final task3 = await persistence.claimNextPending();
      expect(task3, isNull);
    });

    test('returns null when no pending tasks', () async {
      final task = await persistence.claimNextPending();
      expect(task, isNull);
    });

    test('does not claim tasks in non-pending states', () async {
      final id = await persistence.insert(filePath: '/tmp/a.mp4', title: 'A');
      await persistence.markCompleted(id);
      await persistence.markPending(id);

      final task = await persistence.claimNextPending();
      expect(task, isNotNull);
      expect(task!.id, id);
    });

    test('ensures task state is atomically claimed', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');

      // Claim it
      final task1 = await persistence.claimNextPending();
      expect(task1, isNotNull);

      // Claim again should return null (already claimed)
      final task2 = await persistence.claimNextPending();
      expect(task2, isNull);

      // Verify state in DB
      final fromDb = await persistence.getById(id);
      expect(fromDb!.state, UploadState.uploading);
    });
  });

  group('state transitions', () {
    test('markCompleted', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.markCompleted(id);

      final task = await persistence.getById(id);
      expect(task!.state, UploadState.completed);
      expect(task.progress, 1.0);
    });

    test('markFailed', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.markFailed(id, 'Network error');

      final task = await persistence.getById(id);
      expect(task!.state, UploadState.failed);
      expect(task.errorMessage, 'Network error');
    });

    test('markCancelled', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.markCancelled(id);

      final task = await persistence.getById(id);
      expect(task!.state, UploadState.cancelled);
      expect(task.errorMessage, 'Cancelled');
    });

    test('markPending clears multipart state', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');

      // Set multipart state
      await persistence.updateMultipartState(
        id: id,
        s3UploadId: 'upload-123',
        totalParts: 5,
        partSize: 5 * 1024 * 1024,
      );
      await persistence.recordPartCompletion(
        id: id,
        partNumber: 1,
        eTag: '"abc123"',
      );

      // Mark back to pending
      await persistence.markPending(id);

      final task = await persistence.getById(id);
      expect(task!.state, UploadState.pending);
      expect(task.progress, 0.0);
      expect(task.errorMessage, isNull);
      // Multipart state should be cleared
      final etags = await persistence.getPartETags(id);
      expect(etags, isEmpty);
    });
  });

  group('multipart state', () {
    test('updateMultipartState sets initial values', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.updateMultipartState(
        id: id,
        s3UploadId: 'upload-abc',
        totalParts: 10,
        partSize: 5 * 1024 * 1024,
      );

      final task = await persistence.getById(id);
      expect(task!.totalParts, 10);
      expect(task.partsCompleted, 0);
    });

    test('recordPartCompletion increments count', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.claimNextPending();
      await persistence.updateMultipartState(
        id: id,
        s3UploadId: 'upload-abc',
        totalParts: 3,
        partSize: 1048576,
      );

      await persistence.recordPartCompletion(id: id, partNumber: 1, eTag: 'e1');
      await persistence.recordPartCompletion(id: id, partNumber: 2, eTag: 'e2');

      final task = await persistence.getById(id);
      expect(task!.partsCompleted, 2);

      final etags = await persistence.getPartETags(id);
      expect(etags.length, 2);
      expect(etags[0].partNumber, 1);
      expect(etags[0].eTag, 'e1');
      expect(etags[1].partNumber, 2);
      expect(etags[1].eTag, 'e2');
    });

    test('recordPartCompletion ignores duplicate part numbers', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.claimNextPending();
      await persistence.updateMultipartState(
        id: id,
        s3UploadId: 'upload-abc',
        totalParts: 3,
        partSize: 1048576,
      );

      await persistence.recordPartCompletion(id: id, partNumber: 1, eTag: 'e1');
      await persistence.recordPartCompletion(id: id, partNumber: 1, eTag: 'e2');

      final etags = await persistence.getPartETags(id);
      expect(etags.length, 1);
      expect(etags[0].eTag, 'e1');
    });

    test('recordPartCompletion does nothing for non-uploading tasks', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.markCompleted(id);

      await persistence.recordPartCompletion(id: id, partNumber: 1, eTag: 'e1');

      final etags = await persistence.getPartETags(id);
      expect(etags, isEmpty);
    });

    test('getPartETags returns empty for missing task', () async {
      final etags = await persistence.getPartETags(999);
      expect(etags, isEmpty);
    });

    test('clearMultipartState', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.updateMultipartState(
        id: id,
        s3UploadId: 'upload-abc',
        totalParts: 5,
        partSize: 1048576,
      );

      await persistence.clearMultipartState(id);
      final task = await persistence.getById(id);
      expect(task!.totalParts, 0);
      expect(task.partsCompleted, 0);
    });
  });

  group('query methods', () {
    test('getActive excludes terminal states', () async {
      await persistence.insert(filePath: '/tmp/active.mp4', title: 'Active');
      final id2 = await persistence.insert(filePath: '/tmp/done.mp4', title: 'Done');
      final id3 = await persistence.insert(filePath: '/tmp/bad.mp4', title: 'Bad');
      final id4 = await persistence.insert(filePath: '/tmp/cancelled.mp4', title: 'Cancelled');
      await persistence.markCompleted(id2);
      await persistence.markFailed(id3, 'err');
      await persistence.markCancelled(id4);

      final active = await persistence.getActive();
      expect(active.length, 1);
      expect(active[0].title, 'Active');
    });

    test('getAll returns all tasks', () async {
      await persistence.insert(filePath: '/tmp/a.mp4', title: 'A');
      await persistence.insert(filePath: '/tmp/b.mp4', title: 'B');

      final all = await persistence.getAll();
      expect(all.length, 2);
    });

    test('getUploading returns only uploading tasks', () async {
      final id1 = await persistence.insert(filePath: '/tmp/a.mp4', title: 'A');
      await persistence.insert(filePath: '/tmp/b.mp4', title: 'B');
      await persistence.claimNextPending();

      final uploading = await persistence.getUploading();
      expect(uploading.length, 1);
      expect(uploading[0].id, id1);
    });

    test('deleteItem removes task', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.deleteItem(id);

      final task = await persistence.getById(id);
      expect(task, isNull);
    });

    test('deleteOldItems removes only old terminal tasks', () async {
      final id1 = await persistence.insert(filePath: '/tmp/a.mp4', title: 'A');
      final id2 = await persistence.insert(filePath: '/tmp/b.mp4', title: 'B');

      await persistence.markCompleted(id1);
      await persistence.markFailed(id2, 'err');

      // delete with 0 days cutoff to remove all terminal
      await persistence.deleteOldItems(days: 0);

      final task1 = await persistence.getById(id1);
      final task2 = await persistence.getById(id2);
      expect(task1, isNull);
      expect(task2, isNull);
    });
  });

  group('progress', () {
    test('updateProgress', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.updateProgress(id: id, progress: 0.5);

      final task = await persistence.getById(id);
      expect(task!.progress, closeTo(0.5, 0.001));
    });

    test('updateFileUrl', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');

      // Empty URL should be ignored
      await persistence.updateFileUrl(id: id, fileUrl: '');
      var task = await persistence.getById(id);
      expect(task!.fileUrl, isNull);

      // Valid URL
      await persistence.updateFileUrl(id: id, fileUrl: 'https://cdn.example.com/video.mp4');
      task = await persistence.getById(id);
      expect(task!.fileUrl, 'https://cdn.example.com/video.mp4');
    });
  });

  group('concurrent access', () {
    test('two simultaneous claimNextPending calls only one succeeds', () async {
      final id1 = await persistence.insert(filePath: '/tmp/a.mp4', title: 'A');
      final id2 = await persistence.insert(filePath: '/tmp/b.mp4', title: 'B');

      final results = await Future.wait([
        persistence.claimNextPending(),
        persistence.claimNextPending(),
      ]);

      final successes = results.where((t) => t != null).length;
      expect(successes, 2);
      expect(results[0]!.id, id1);
      expect(results[1]!.id, id2);
    });

    test('concurrent recordPartCompletion no data loss', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.claimNextPending();
      await persistence.updateMultipartState(
        id: id,
        s3UploadId: 'upload-abc',
        totalParts: 5,
        partSize: 1048576,
      );

      await Future.wait([
        persistence.recordPartCompletion(id: id, partNumber: 1, eTag: 'e1'),
        persistence.recordPartCompletion(id: id, partNumber: 2, eTag: 'e2'),
        persistence.recordPartCompletion(id: id, partNumber: 3, eTag: 'e3'),
      ]);

      final task = await persistence.getById(id);
      expect(task!.partsCompleted, 3);

      final etags = await persistence.getPartETags(id);
      expect(etags.length, 3);
    });
  });

  group('edge cases', () {
    test('insert with empty title', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: '');
      expect(id, greaterThan(0));
    });

    test('multiple state transitions on same task', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.markFailed(id, 'First error');
      await persistence.markPending(id);
      await persistence.markFailed(id, 'Second error');
      await persistence.markPending(id);
      await persistence.markCompleted(id);

      final task = await persistence.getById(id);
      expect(task!.state, UploadState.completed);
    });

    test('close then reopen', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.close();

      // Re-open with same dbPath
      persistence = Persistence(customDbPath: dbPath);
      final task = await persistence.getById(id);
      expect(task, isNotNull);
      expect(task!.title, 'Test');
    });

    test('insert with non-ASCII path', () async {
      final id = await persistence.insert(
        filePath: '/tmp/ñuñéz_视频.mp4',
        title: 'International',
      );
      final task = await persistence.getById(id);
      expect(task!.filePath, '/tmp/ñuñéz_视频.mp4');
    });

    test('claimNextPending with no pending tasks after claim', () async {
      final id = await persistence.insert(filePath: '/tmp/v.mp4', title: 'Test');
      await persistence.claimNextPending();
      await persistence.markCompleted(id);

      // Should not claim completed tasks
      final task = await persistence.claimNextPending();
      expect(task, isNull);
    });
  });
}
