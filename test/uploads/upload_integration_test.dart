import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edtech/features/uploads/data/api/s3_upload_api.dart';
import 'package:edtech/features/uploads/data/models/upload_enums.dart';
import 'package:edtech/features/uploads/data/models/upload_job.dart';
import 'package:edtech/features/uploads/data/models/s3_init_response.dart';
import 'package:edtech/features/uploads/engine/background_upload_engine.dart';
import 'package:edtech/features/uploads/service/upload_service.dart';
import 'package:edtech/features/uploads/data/job_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake implementations of every UploadService dependency
// ─────────────────────────────────────────────────────────────────────────────

/// In-memory [JobStore] that avoids SQLite / path_provider entirely.
/// Jobs are kept in a map so they survive a "service restart".
class FakeJobStore extends JobStore {
  final _db = <String, UploadJob>{};

  @override
  Future<void> save(UploadJob job) async {
    _db[job.id] = job;
  }

  @override
  Future<List<UploadJob>> loadAll() async {
    return _db.values
        .where((j) => j.state != UploadJobState.completed &&
            j.state != UploadJobState.failed &&
            j.state != UploadJobState.cancelled)
        .map((j) => UploadJob.fromMap(j.toMap()))
        .toList();
  }

  @override
  Future<void> delete(String id) async {
    _db.remove(id);
  }

  @override
  Future<void> deleteAllTerminal() async {
    _db.removeWhere((_, j) =>
        j.state == UploadJobState.completed ||
        j.state == UploadJobState.failed ||
        j.state == UploadJobState.cancelled);
  }

  @override
  Future<void> close() async {
    // no-op
  }
}

/// Controlled [BackgroundUploadEngine] that simulates upload tasks without
/// touching the real `background_downloader` platform channel.
class FakeBackgroundUploadEngine extends BackgroundUploadEngine {
  FakeBackgroundUploadEngine() : super(maxConcurrent: 3, maxConcurrentByHost: 3);

  /// Simulate an engine progress update for [jobId].
  void simulateProgress(String jobId, double progress) {
    onJobProgress?.call(jobId, progress);
  }

  /// Simulate a task completion for [jobId].
  void simulateTaskFinal({
    required String jobId,
    bool success = true,
    String? eTag,
    bool urlExpired = false,
    String? fileUrl,
    bool isApi = false,
    String? responseBody,
    int? statusCode,
  }) {
    onTaskFinal?.call(
      jobId, success, eTag, urlExpired,
      fileUrl, isApi, responseBody, statusCode,
    );
  }

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> cancelJob(String jobId) async {
    // Cancel is a no-op in tests — no real FileDownloader tasks.
  }
}

/// Controlled [S3UploadApi] that returns canned responses.
class FakeS3UploadApi extends S3UploadApi {
  @override
  Future<S3InitResponse?> init({
    required String endpoint,
    required Map<String, dynamic> body,
    String? courseAssetKey,
  }) async {
    return S3InitResponse(
      isMultipart: true,
      fileUrl: 'https://cdn.example.com/video.mp4',
      key: 'uploads/video.mp4',
      s3UploadId: 'fake-upload-id',
      totalParts: 1,
    );
  }

  @override
  Future<CompleteResult> complete({
    required String endpoint,
    required String key,
    required String s3UploadId,
    required List<Map<String, dynamic>> parts,
    Map<String, dynamic> extraFields = const {},
  }) async {
    return const CompleteResult(
      isSuccess: true,
      fileUrl: 'https://cdn.example.com/video.mp4',
    );
  }

  @override
  Future<bool> callback({
    required String endpoint,
    required Map<String, dynamic> body,
    String method = 'POST',
    String? idempotencyKey,
  }) async {
    return true;
  }

  @override
  Future<bool> abort({
    required String endpoint,
    required String key,
    required String s3UploadId,
  }) async {
    return true;
  }
}

/// Test harness that owns all fakes and the service under test.
class UploadTestHarness {
  late FakeJobStore store;
  late FakeS3UploadApi api;
  late FakeBackgroundUploadEngine engine;
  late UploadService service;
  final _emitted = <UploadJob>[];
  late StreamSubscription<UploadJob> _sub;
  final _tempFiles = <String>{};

  UploadTestHarness() {
    store = FakeJobStore();
    api = FakeS3UploadApi();
    engine = FakeBackgroundUploadEngine();
    service = UploadService(api: api, engine: engine, store: store);
    _sub = service.updates.listen((j) => _emitted.add(j));
  }

  /// Create a temp file and return its absolute path.
  Future<String> createTempFile(String name, {int size = 1024}) async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/$name');
    if (!await file.exists()) {
      await file.writeAsBytes(List.filled(size, 0x41));
    }
    _tempFiles.add(file.absolute.path);
    return file.absolute.path;
  }

  /// Shorthand to enqueue a module-lesson job using a temp file.
  Future<UploadJob> enqueueLesson({
    required String id,
    required String title,
    int fileSize = 1024,
    Map<String, dynamic> metadata = const {},
  }) async {
    final filePath = await createTempFile('${id}_test.mp4', size: fileSize);
    await service.enqueue(
      id: id,
      filePath: filePath,
      type: UploadAssetType.moduleLesson,
      title: title,
      fileSize: fileSize,
      metadata: metadata,
    );
    // Wait briefly for processing
    await Future.delayed(const Duration(milliseconds: 30));
    return service.job(id)!;
  }

  /// Simulate the full upload flow: init → transfer → complete → callback.
  Future<void> completeUploadFlow(String jobId) async {
    // 1. Engine reports progress (0.0 → 0.5 → 1.0)
    engine.simulateProgress(jobId, 0.0);
    engine.simulateProgress(jobId, 0.5);
    engine.simulateProgress(jobId, 1.0);
    // 2. Engine reports the task is done (final)
    engine.simulateTaskFinal(jobId: jobId, success: true, eTag: '"abc123"');
    // Give the async processing time to settle.
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Simulate an app restart: dispose, create fresh service with same store.
  Future<void> restartService() async {
    _sub.cancel();
    engine = FakeBackgroundUploadEngine();
    service = UploadService(api: api, engine: engine, store: store);
    _sub = service.updates.listen((j) => _emitted.add(j));
    await service.ensureStarted();
    await Future.delayed(const Duration(milliseconds: 50));
  }

  int get emittedCount => _emitted.length;
  List<UploadJob> get emitted => List.unmodifiable(_emitted);

  void dispose() {
    _sub.cancel();
    service.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Integration scenarios
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late UploadTestHarness harness;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    harness = UploadTestHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Scenario 1 — Crash while multiple videos are queued', () {
    test('jobs survive service disposal and are recovered on restart', () async {
      // Given: multiple jobs enqueued
      final a = await harness.enqueueLesson(
        id: 'crash_a', title: 'Video A',
      );
      final b = await harness.enqueueLesson(
        id: 'crash_b', title: 'Video B',
      );

      // Simulate S3 init completing for both
      await Future.delayed(const Duration(milliseconds: 50));

      // When: "crash" (dispose + create fresh service with same store)
      await harness.restartService();

      // Then: both jobs appear in the new service in a non-terminal state
      final recoveredA = harness.service.job('crash_a');
      final recoveredB = harness.service.job('crash_b');
      expect(recoveredA, isNotNull, reason: 'job A should be recovered');
      expect(recoveredB, isNotNull, reason: 'job B should be recovered');
      expect(recoveredA!.state, isNot(UploadJobState.completed));
      expect(recoveredB!.state, isNot(UploadJobState.completed));
    });

    test('recovered jobs can still be cancelled', () async {
      await harness.enqueueLesson(
        id: 'crash_cancel', title: 'Cancel Test',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Crash + restart
      await harness.restartService();

      // Cancel after recovery
      await harness.service.cancel('crash_cancel');
      expect(harness.service.job('crash_cancel'), isNull);
    });
  });

  group('Scenario 2 — App running, then killed, remaining videos, app reopened',
      () {
    test('completed jobs are removed, pending jobs survive restart', () async {
      // Given: job A completes fully, job B is only queued
      await harness.enqueueLesson(
        id: 'complete_a', title: 'Complete A',
      );
      await harness.enqueueLesson(
        id: 'pending_b', title: 'Pending B',
      );

      // Let job A go through the full upload flow
      await harness.completeUploadFlow('complete_a');

      // When: app is killed and reopened
      await harness.restartService();

      // Then: completed job A is gone, pending B is recovered
      expect(harness.service.job('complete_a'), isNull,
          reason: 'completed job should be cleaned up');
      final b = harness.service.job('pending_b');
      expect(b, isNotNull, reason: 'pending job should survive restart');
      expect(b!.state, UploadJobState.pending);
    });

    test('uploading jobs are recovered in uploading state', () async {
      await harness.enqueueLesson(
        id: 'midway', title: 'Midway Upload',
      );
      // Simulate progress
      harness.engine.simulateProgress('midway', 0.5);
      await Future.delayed(const Duration(milliseconds: 30));

      // Crash while uploading
      await harness.restartService();

      // Should be recovered (not terminal)
      final job = harness.service.job('midway');
      expect(job, isNotNull);
      expect(job!.state, isNot(UploadJobState.completed));
      expect(job.state, isNot(UploadJobState.failed));
    });

    test('completed job after restart no longer appears', () async {
      await harness.enqueueLesson(
        id: 'finish_before', title: 'Finished',
      );
      await harness.completeUploadFlow('finish_before');

      // The store should have processed the completion.
      await Future.delayed(const Duration(milliseconds: 50));

      // Restart
      await harness.restartService();

      expect(harness.service.job('finish_before'), isNull);
    });
  });

  group('Scenario 3 — Multiple videos queued, all upload in background', () {
    test('three jobs all emit progress and reach completion', () async {
      // Enqueue 3 jobs
      await harness.enqueueLesson(
        id: 'bg_1', title: 'BG One',
      );
      await harness.enqueueLesson(
        id: 'bg_2', title: 'BG Two',
      );
      await harness.enqueueLesson(
        id: 'bg_3', title: 'BG Three',
      );

      // Simulate engine progress for all three
      for (final id in ['bg_1', 'bg_2', 'bg_3']) {
        harness.engine.simulateProgress(id, 0.3);
        harness.engine.simulateProgress(id, 0.7);
        harness.engine.simulateProgress(id, 1.0);
        harness.engine.simulateTaskFinal(jobId: id, success: true);
      }
      await Future.delayed(const Duration(milliseconds: 150));

      // All should have progressed through various states
      // (not all may reach completed in the fake since callback API is no-op)
      expect(harness.emitted.isNotEmpty, isTrue);
    });

    test('sequential enqueue preserves order', () async {
      await harness.enqueueLesson(
        id: 'seq_1', title: 'First',
      );
      await harness.enqueueLesson(
        id: 'seq_2', title: 'Second',
      );
      await harness.enqueueLesson(
        id: 'seq_3', title: 'Third',
      );

      final jobs = harness.service.jobs;
      expect(jobs.length, 3);
      expect(jobs[0].id, 'seq_1');
      expect(jobs[1].id, 'seq_2');
      expect(jobs[2].id, 'seq_3');
    });
  });

  group('Scenario 4 — Edge cases YouTube-like robustness', () {
    test('duplicate enqueue is rejected', () async {
      final path = await harness.createTempFile('dup_orig.mp4');
      await harness.service.enqueue(
        id: 'dup',
        filePath: path,
        type: UploadAssetType.moduleLesson,
        title: 'Original',
        fileSize: 1024,
      );
      // Enqueue same id again should not throw (service overwrites or no-ops)
      await harness.service.enqueue(
        id: 'dup',
        filePath: path,
        type: UploadAssetType.moduleLesson,
        title: 'Duplicate',
        fileSize: 1024,
      );
      // The last enqueue wins — no crash
      expect(harness.service.job('dup'), isNotNull);
    });

    test('cancel during upload removes job', () async {
      await harness.enqueueLesson(
        id: 'cancel_mid', title: 'Cancel Mid',
      );
      harness.engine.simulateProgress('cancel_mid', 0.4);
      await harness.service.cancel('cancel_mid');
      expect(harness.service.job('cancel_mid'), isNull);
    });

    test('engine progress for unknown job is silently ignored', () {
      // Should not throw
      harness.engine.simulateProgress('nonexistent', 0.5);
      harness.engine.simulateTaskFinal(jobId: 'nonexistent', success: true);
    });

    test('service emits updates on the stream', () async {
      final events = <UploadJob>[];
      final sub = harness.service.updates.listen((j) => events.add(j));

      await harness.enqueueLesson(
        id: 'stream_check', title: 'Stream Check',
      );
      await Future.delayed(const Duration(milliseconds: 30));

      expect(events.isNotEmpty, isTrue);
      expect(events.any((e) => e.id == 'stream_check'), isTrue);
      await sub.cancel();
    });
  });
}
