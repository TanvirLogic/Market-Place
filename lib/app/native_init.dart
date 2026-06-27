import 'dart:convert';

import 'package:edtech/features/courses/data/repositories/upload_queue_repository.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/native_upload_bridge.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:media_kit/media_kit.dart';

Future<void> initPlatformServices() async {
  MediaKit.ensureInitialized();
  await UploadNotificationService.init();

  await NativeUploadBridge.ensureInitialized();
  await _requestNotificationPermissionEarly();

  // Startup storage cleanup: delete old rows, orphaned cache files, trim WAL
  await UploadQueueRepository.runStartupCleanup();

  // Check if native service is alive. If alive, just reset stale locks.
  final nativeAlive = await _checkNativeAlive();
  if (nativeAlive) {
    AppLogger.i('Recovery: native service is alive, skipping full recovery');
    await _resetStaleLocks();
    return;
  }

  // Phase 2: Process completion markers (items that finished while Flutter was away)
  await _processCompletionMarkers();

  // Phase 3: Reset stale uploading items.
  await _resetStaleLocks();

  // Phase 4: Auto-resume any pending items — sync from SQLite and restart service.
  await _autoResumeIfNeeded();
}

Future<void> _requestNotificationPermissionEarly() async {
  try {
    if (!await UploadNotificationService.hasNotificationPermission()) {
      await UploadNotificationService.requestNotificationPermission();
    }
  } catch (_) {}
}

/// Check if the native :upload process is alive via ping.
Future<bool> _checkNativeAlive() async {
  try {
    return await NativeUploadBridge.ping();
  } catch (_) {
    return false;
  }
}



/// Process completion markers written by the :upload process.
/// Marks items as completed/failed in SQLite, then acknowledges (deletes) the markers.
Future<void> _processCompletionMarkers() async {
  try {
    final markers = await NativeUploadBridge.getCompletedItems();
    if (markers.isEmpty) return;
    int completedCount = 0;
    int failedCount = 0;
    for (final entry in markers) {
      final itemId = entry['id'] as int?;
      final error = entry['error'] as String?;
      if (itemId == null) continue;
      try {
        final all = await UploadQueueRepository.getAll();
        final dbItem = all.cast<UploadQueueItem?>().firstWhere(
          (i) => i!.id == itemId,
          orElse: () => null,
        );
        if (dbItem == null) continue;
        if (error != null) {
          if (dbItem.status != 'completed' && dbItem.status != 'failed' && dbItem.status != 'cancelled') {
            await UploadQueueRepository.markFailed(itemId, error);
            failedCount++;
          }
        } else {
          if (dbItem.status != 'completed' && dbItem.status != 'failed' && dbItem.status != 'cancelled') {
            await UploadQueueRepository.markCompleted(itemId);
            await UploadQueueRepository.cleanupFileIfCached(dbItem.filePath);
            completedCount++;
          }
        }
      } catch (_) {}
    }
    if (completedCount > 0) {
      AppLogger.i('Recovery: marked $completedCount item(s) completed from markers');
    }
    if (failedCount > 0) {
      AppLogger.i('Recovery: marked $failedCount item(s) failed from markers');
    }
    await NativeUploadBridge.acknowledgeCompletedItems();
  } catch (e) {
    AppLogger.e('Recovery: error processing completion markers - $e');
  }
}

/// Reset stale uploading items immediately (no 30-min window).
Future<void> _resetStaleLocks() async {
  try {
    await UploadQueueRepository.resetStaleUploading(
      heartbeatTimeout: const Duration(minutes: 2),
      fallbackTimeout: const Duration(minutes: 5),
    );
  } catch (e) {
    AppLogger.e('Recovery: error resetting stale locks - $e');
  }
}

/// Auto-resume pending items by syncing to native and starting the service.
Future<void> _autoResumeIfNeeded() async {
  try {
    final pendingCount = await UploadQueueRepository.countPending();
    if (pendingCount == 0) {
      AppLogger.i('AutoResume: no pending items');
      return;
    }

    AppLogger.i('AutoResume: $pendingCount pending item(s) found, syncing from SQLite');

    final pendingItems = await UploadQueueRepository.getByStatus('pending');
    if (pendingItems.isEmpty) return;

    final nativeQueueJson = jsonEncode(pendingItems.map((item) => {
      'id': item.id,
      'filePath': item.filePath,
      'title': item.title,
      'uploadUrl': item.uploadUrl,
      'fileUrl': item.fileUrl,
      'contentType': _inferContentType(item.filePath),
      'uploadType': item.uploadType,
      'metadata': item.metadata,
      'uploadId': item.uploadId,
    }).toList());

    await NativeUploadBridge.syncQueueToNative(nativeQueueJson);
    final started = await NativeUploadBridge.startQueueProcessing();
    if (started) {
      AppLogger.i('AutoResume: native service started with $pendingCount items');
    } else {
      AppLogger.w('AutoResume: failed to start native service');
    }
  } catch (e) {
    AppLogger.e('AutoResume: error - $e');
  }
}

String _inferContentType(String filePath) {
  final ext = filePath.split('.').last.toLowerCase();
  switch (ext) {
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}
