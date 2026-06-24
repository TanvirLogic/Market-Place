import 'dart:io';

import 'package:edtech/features/courses/data/repositories/upload_queue_repository.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/native_upload_bridge.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:edtech/global/core/services/upload_path_storage.dart';
import 'package:media_kit/media_kit.dart';

Future<void> initPlatformServices() async {
  MediaKit.ensureInitialized();
  await UploadNotificationService.init();

  // Initialize native upload bridge (WorkManager + BootReceiver)
  await NativeUploadBridge.ensureInitialized();

  // Phase 0: Try to get notification permission early (before user starts an upload)
  // On Android 13+, this shows the system permission dialog at startup.
  // On Android 12 and below, this is a no-op (returns true).
  await _requestNotificationPermissionEarly();

  // Phase 1: Recover from FlutterSecureStorage (user may have killed app mid-flow)
  await _recoverPendingUploads();

  // Phase 2: Recover from native JSON state (native :upload process may have
  // completed some items while the app was dead)
  await _recoverNativeOrphans();

  // Phase 3: Clear stale locks so user can instantly restart
  await _clearStaleLocks();

  // Phase 4: If there are still pending items in SQLite, auto-start the queue
  await _autoResumeIfNeeded();
}

/// Try to get notification permission early at startup.
/// This is best-effort — the full blocking dialog happens when the user uploads.
Future<void> _requestNotificationPermissionEarly() async {
  try {
    if (!await UploadNotificationService.hasNotificationPermission()) {
      await UploadNotificationService.requestNotificationPermission();
    }
  } catch (_) {}
}

/// Phase 1: Recover pending uploads from FlutterSecureStorage into SQLite.
/// This handles the case where the user picked files, saved them to FSS,
/// but the app was killed before the queue started processing.
Future<void> _recoverPendingUploads() async {
  try {
    await UploadNotificationService.cancel();
    await UploadQueueRepository.resetStaleUploading();

    final pendingPaths = await UploadPathStorage.getAllPendingPaths();
    if (pendingPaths.isEmpty) return;

    int recovered = 0;
    for (final entry in pendingPaths) {
      if (!entry.fileExists) {
        await UploadPathStorage.removePath(entry.key);
        continue;
      }

      final activeItems = await UploadQueueRepository.getActive();
      final alreadyQueued = activeItems.any(
        (item) => item.filePath == entry.filePath && item.status == 'pending',
      );
      if (alreadyQueued) {
        await UploadPathStorage.removePath(entry.key);
        continue;
      }

      final item = UploadQueueItem(
        filePath: entry.filePath,
        title: entry.title,
        status: 'pending',
        uploadType: entry.uploadType,
        metadata: entry.metadata,
      );
      await UploadQueueRepository.insert(item);
      await UploadPathStorage.removePath(entry.key);
      recovered++;
    }

    if (recovered > 0) {
      AppLogger.i('UploadRecovery: recovered $recovered pending upload(s) from FSS');
    }
  } catch (e) {
    AppLogger.e('UploadRecovery: error during FSS recovery — $e');
  }
}

/// Phase 2: Recover from native JSON state file.
/// This handles the case where the native :upload process completed or failed
/// some items while the app was dead. We sync this state back into SQLite.
Future<void> _recoverNativeOrphans() async {
  try {
    final nativeItems = await NativeUploadBridge.getPendingUploads();
    if (nativeItems.isEmpty) return;

    int recovered = 0;
    int completed = 0;
    final completedFilePaths = <String>[];

    for (final item in nativeItems) {
      final filePath = item['filePath'] as String?;
      final title = item['title'] as String? ?? 'Upload';
      final uploadType = item['uploadType'] as String? ?? 'video_post';
      final metadata = item['metadata'] as String?;
      final status = item['status'] as String? ?? 'pending';
      final uploadUrl = item['uploadUrl'] as String?;

      if (filePath == null) continue;

      // If the native layer already completed this item, mark it in SQLite
      if (status == 'completed') {
        completed++;
        completedFilePaths.add(filePath);
        continue;
      }

      // If the native layer already failed this item, mark it in SQLite
      if (status == 'failed') {
        await _markItemFailedInQueue(filePath, 'Native: ${item['errorMessage'] ?? 'Upload failed'}');
        continue;
      }

      // If it's still pending/uploading, check if file exists
      final file = Uri.tryParse(filePath)?.path ?? filePath;
      if (!File(file).existsSync()) continue;

      // Check if it's already in the SQLite queue
      final activeItems = await UploadQueueRepository.getActive();
      final alreadyQueued = activeItems.any(
        (q) => q.filePath == filePath && q.status == 'pending',
      );
      if (alreadyQueued) continue;

      // Recover as pending with uploadUrl if available
      final queueItem = UploadQueueItem(
        filePath: filePath,
        title: title,
        status: 'pending',
        uploadType: uploadType,
        metadata: metadata,
        uploadUrl: uploadUrl,
      );
      await UploadQueueRepository.insert(queueItem);
      recovered++;
    }

    // Remove completed items from FlutterSecureStorage
    if (completedFilePaths.isNotEmpty) {
      await UploadPathStorage.removeCompletedPaths(completedFilePaths);
    }

    // Clear the native state file now that we've recovered
    await NativeUploadBridge.clearState();

    if (recovered > 0) {
      AppLogger.i('NativeRecovery: recovered $recovered orphaned upload(s) from native layer');
    }
    if (completed > 0) {
      AppLogger.i('NativeRecovery: $completed items already completed by native layer');
    }
  } catch (e) {
    AppLogger.e('NativeRecovery: error recovering native orphans — $e');
  }
}

/// Phase 3: Clear stale locks so user can restart immediately.
/// Resets items stuck in 'uploading' status for more than 30 minutes.
Future<void> _clearStaleLocks() async {
  try {
    await UploadQueueRepository.resetStaleUploading(olderThan: const Duration(minutes: 30));
  } catch (e) {
    AppLogger.e('StaleLockClear: error — $e');
  }
}

/// Phase 4: Auto-resume the queue if there are pending items.
/// After reconciliation, if items remain in the queue, automatically restart
/// the native and Dart processors so uploads continue seamlessly.
Future<void> _autoResumeIfNeeded() async {
  try {
    final pendingCount = await UploadQueueRepository.countPending();
    if (pendingCount == 0) return;

    AppLogger.i('AutoResume: $pendingCount pending item(s) found, auto-starting queue');

    // First, check if native layer is already processing
    final nativeStatus = await NativeUploadBridge.getNativeQueueStatus();
    final isNativeAlreadyRunning = (nativeStatus['isUploading'] as bool?) ?? false;

    if (!isNativeAlreadyRunning) {
      // Sync the queue to native and start processing
      final itemsJson = await UploadPathStorage.getAtomicQueueJson();
      await NativeUploadBridge.syncQueueToNative(itemsJson);
      await NativeUploadBridge.startQueueProcessing();
    }
  } catch (e) {
    AppLogger.e('AutoResume: error — $e');
  }
}

Future<void> _markItemFailedInQueue(String filePath, String errorMessage) async {
  try {
    final active = await UploadQueueRepository.getActive();
    for (final item in active) {
      if (item.filePath == filePath && item.status == 'pending') {
        await UploadQueueRepository.markFailed(item.id!, errorMessage);
        break;
      }
    }
  } catch (_) {}
}
