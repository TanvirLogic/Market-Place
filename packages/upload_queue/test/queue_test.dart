import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:upload_queue/src/dart_http_engine.dart';
import 'package:upload_queue/src/engine.dart';
import 'package:upload_queue/src/models/upload_config.dart';
import 'package:upload_queue/src/models/upload_task.dart';
import 'package:upload_queue/src/persistence.dart';
import 'package:upload_queue/src/queue.dart';

class MockEngine extends Mock implements UploadEngine {}

void main() {
  late Persistence persistence;
  late String dbPath;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registerFallbackValue(CallbackRequest(
      url: 'https://api.example.com/callback',
      body: {},
    ));
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('upload_queue_test_');
    dbPath = '${tempDir.path}\\test.db';
    persistence = Persistence(customDbPath: dbPath);
  });

  tearDown(() async {
    await persistence.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Lock', () {
    test('acquire returns true when unlocked', () async {
      final lock = Lock();
      expect(await lock.acquire(), isTrue);
    });

    test('acquire returns false when already locked', () async {
      final lock = Lock();
      await lock.acquire();
      expect(await lock.acquire(), isFalse);
    });

    test('acquire returns true after release', () async {
      final lock = Lock();
      await lock.acquire();
      lock.release();
      expect(await lock.acquire(), isTrue);
    });

    test('isLocked reflects state', () async {
      final lock = Lock();
      expect(lock.isLocked, isFalse);
      await lock.acquire();
      expect(lock.isLocked, isTrue);
      lock.release();
      expect(lock.isLocked, isFalse);
    });
  });

  group('UploadQueue', () {
    late File testFile;

    /// Helper: creates a queue with a mock engine that fails init.
    /// This prevents the queue from processing any tasks during setup.
    Future<UploadQueue> _createQueue({UploadConfig? cfg}) async {
      cfg ??= UploadConfig(
        initUploadEndpoint: 'https://api.example.com/init',
        tokenProvider: () => 'test-token',
        logger: (_) {},
      );
      final engine = MockEngine();
      when(() => engine.initUpload(
        filePath: any(named: 'filePath'),
        extraFields: any(named: 'extraFields'),
      )).thenAnswer((_) async => null);
      when(() => engine.cancelUpload(any())).thenAnswer((_) async {});
      when(() => engine.abortMultipart(
        any(),
        endpoint: any(named: 'endpoint'),
        s3Key: any(named: 's3Key'),
      )).thenAnswer((_) async => true);

      final q = UploadQueue(
        config: cfg,
        engine: engine,
        persistence: persistence,
      );
      await Future.delayed(const Duration(milliseconds: 100));
      return q;
    }

    setUp(() {
      testFile = File('${tempDir.path}\\test_video.mp4');
      testFile.writeAsBytesSync(List.filled(1024 * 50, 0x41));
    });

    test('add inserts task and returns it', () async {
      final queue = await _createQueue();
      final task = await queue.add(
        file: testFile,
        title: 'Test Video',
        metadata: {'uploadType': 'test'},
      );

      expect(task.title, 'Test Video');
      expect(task.filePath, testFile.path);
      expect(task.id, greaterThan(0));

      await queue.dispose();
    });

    test('add with file not found marks failed', () async {
      final queue = await _createQueue();
      final missingFile = File('${tempDir.path}\\nonexistent.mp4');

      await queue.add(file: missingFile, title: 'Missing');
      await Future.delayed(const Duration(milliseconds: 200));

      final failed = queue.tasks.where((t) => t.title == 'Missing').firstOrNull;
      expect(failed?.state, UploadState.failed);

      await queue.dispose();
    });

    test('remove deletes task from queue', () async {
      final queue = await _createQueue();
      final task = await queue.add(file: testFile, title: 'To Remove');
      await queue.remove(task.id);

      expect(queue.tasks.where((t) => t.id == task.id), isEmpty);
      await queue.dispose();
    });

    test('cancel marks task cancelled', () async {
      final queue = await _createQueue();
      final id = await persistence.insert(
        filePath: testFile.path,
        title: 'To Cancel',
      );

      await queue.cancel(id);

      final fromDb = await persistence.getById(id);
      expect(fromDb?.state, UploadState.cancelled);
      await queue.dispose();
    });

    test('dispose stops all activity', () async {
      final queue = await _createQueue();
      await queue.dispose();
      expect(queue.tasks, isA<List<UploadTask>>());
    });

    test('onUpdate stream emits on state changes', () async {
      final queue = await _createQueue();
      final updates = <List<UploadTask>>[];
      final sub = queue.onUpdate.listen((tasks) => updates.add(tasks));

      await queue.add(file: testFile, title: 'Stream Test');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(updates, isNotEmpty);
      await sub.cancel();
      await queue.dispose();
    });

    test('add after dispose throws StateError', () async {
      final queue = await _createQueue();
      await queue.dispose();

      expect(
        () => queue.add(file: testFile, title: 'After Dispose'),
        throwsStateError,
      );
    });

    test('cancel non-existent task is no-op', () async {
      final queue = await _createQueue();
      await queue.cancel(999);
      await queue.dispose();
    });
  });

  group('UploadQueue with real engine', () {
    late File testFile;

    setUp(() {
      testFile = File('${tempDir.path}\\test_video.mp4');
      testFile.writeAsBytesSync(List.filled(1024 * 50, 0x41));
    });

    test('queues multiple tasks sequentially', () async {
      final engine = DartHttpEngine(
        UploadConfig(
          initUploadEndpoint: 'https://api.example.com/init',
          tokenProvider: () => 'test-token',
          logger: (_) {},
        ),
      );
      final queue = UploadQueue(
        config: UploadConfig(
          initUploadEndpoint: 'https://api.example.com/init',
          tokenProvider: () => 'test-token',
          logger: (_) {},
        ),
        engine: engine,
        persistence: persistence,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final t1 = await queue.add(
        file: testFile,
        title: 'Task 1',
        metadata: {'seq': 1},
      );
      final t2 = await queue.add(
        file: testFile,
        title: 'Task 2',
        metadata: {'seq': 2},
      );

      expect(t1.id, lessThan(t2.id));
      await queue.dispose();
    });

    test('claims tasks in FIFO order (oldest id first)', () async {
      // Track the order in which initUpload is called — that's the order
      // the queue actually starts processing videos. It must match insertion
      // (FIFO) order, one at a time.
      final startedOrder = <int>[];
      final engine = MockEngine();
      when(() => engine.initUpload(
            filePath: any(named: 'filePath'),
            extraFields: any(named: 'extraFields'),
          )).thenAnswer((invocation) async {
        final extra = invocation.namedArguments[#extraFields]
            as Map<String, dynamic>?;
        final seq = extra?['seq'] as int?;
        if (seq != null) startedOrder.add(seq);
        // Return null so the task fails fast and the processor advances to
        // the next one; we only care about ordering here.
        return null;
      });

      final queue = UploadQueue(
        config: UploadConfig(
          initUploadEndpoint: 'https://api.example.com/init',
          tokenProvider: () => 'test-token',
          logger: (_) {},
        ),
        engine: engine,
        persistence: persistence,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      await queue.add(file: testFile, title: 'A', metadata: {'seq': 1});
      await queue.add(file: testFile, title: 'B', metadata: {'seq': 2});
      await queue.add(file: testFile, title: 'C', metadata: {'seq': 3});

      // Give the serial processor time to walk all three.
      await Future.delayed(const Duration(milliseconds: 400));

      expect(startedOrder, [1, 2, 3]);
      await queue.dispose();
    });
  });
}
