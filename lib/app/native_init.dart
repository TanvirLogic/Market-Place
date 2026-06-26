import 'dart:convert';
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

  await NativeUploadBridge.ensureInitialized();
  await _requestNotificationPermissionEarly();

  // Phase 1: Recover from FlutterSecureStorage
  await _recoverPendingUploads();

  // Phase 2: Recover from native JSON state — syncs completed/failed items
  // back into SQLite so we don't re-upload what's already done.
  await _recoverNativeOrphans();

  // Phase 3: Clear stale locks so user can instantly restart
  await _clearStaleLocks();

  // Phase 4: If there are still pending items in SQLite, auto-start the queue
  await _autoResumeIfNeeded();
}

Future<void> _requestNotificationPermissionEarly() async {
  try {
    if (!await UploadNotificationService.hasNotificationPermission()) {
      await UploadNotificationService.requestNotificationPermission();
    }
  } catch (_) {}
}

/// Phase 1: Recover pending uploads from FlutterSecureStorage into SQLite.
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
        (item) => item.filePath == entry.filePath &&
            item.status != 'completed' &&
            item.status != 'failed',
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
///
/// When the native :upload process completes an item, it marks it 'completed'
/// in native_uploads.json and then DELETES the file. So if the state file
/// still exists, any 'completed' items in it were finished while we were away.
///
/// CRITICAL: We must mark these items as 'completed' in SQLite too, otherwise
/// _clearStaleLocks will reset them to 'pending' after 30 minutes, and
/// _autoResumeIfNeeded will re-upload them — causing duplicates on the server.
Future<void> _recoverNativeOrphans() async {
  try {
    final nativeItems = await NativeUploadBridge.getPendingUploads();
    final hadNativeState = nativeItems.isNotEmpty;

    int recovered = 0;
    int completed = 0;
    int failed = 0;
    bool hasStillUploading = false;

    for (final item in nativeItems) {
      final filePath = item['filePath'] as String?;
      final title = item['title'] as String? ?? 'Upload';
      final uploadType = item['uploadType'] as String? ?? 'video_post';
      final metadata = item['metadata'] as String?;
      final status = item['status'] as String? ?? 'pending';
      final uploadUrl = item['uploadUrl'] as String?;
      final fileUrl = item['fileUrl'] as String?;
      final itemId = item['id'] as int?;

      if (filePath == null) continue;

      // Native says completed → mark SQLite item as completed (prevents re-upload)
      if (status == 'completed') {
        if (itemId != null) {
          await UploadQueueRepository.markCompleted(itemId);
        } else {
          await _markItemCompletedInQueue(filePath);
        }
        completed++;
        continue;
      }

      // Native says failed → mark SQLite item as failed
      if (status == 'failed') {
        if (itemId != null) {
          await UploadQueueRepository.markFailed(
              itemId, 'Native: ${item['errorMessage'] ?? 'Upload failed'}');
        } else {
          await _markItemFailedInQueue(
              filePath, 'Native: ${item['errorMessage'] ?? 'Upload failed'}');
        }
        failed++;
        continue;
      }

      // Track if any items are still actively uploading
      if (status == 'uploading') {
        hasStillUploading = true;
      }

      // If it's still pending/uploading, check if file exists
      final file = Uri.tryParse(filePath)?.path ?? filePath;
      if (!File(file).existsSync()) continue;

      // Check if it's already in the SQLite queue (any active status)
      final activeItems = await UploadQueueRepository.getActive();
      final alreadyQueued = activeItems.any(
        (q) => q.filePath == filePath &&
            q.status != 'completed' &&
            q.status != 'failed',
      );
      if (alreadyQueued) continue;

      // Recover as pending with uploadUrl and fileUrl if available
      final queueItem = UploadQueueItem(
        filePath: filePath,
        title: title,
        status: 'pending',
        uploadType: uploadType,
        metadata: metadata,
        uploadUrl: uploadUrl,
        fileUrl: fileUrl,
      );
      await UploadQueueRepository.insert(queueItem);
      recovered++;
    }

    // Only clear native state if nothing is still actively uploading.
    if (!hasStillUploading) {
      await NativeUploadBridge.clearState();

      // If native state had no items (was already cleared by native's finally
      // block after completing all uploads), any 'uploading' items left in
      // SQLite with fileUrl set were completed successfully. Mark them
      // 'completed' to prevent Phase 3 from resetting them to 'pending'
      // and causing re-upload duplicates on next app start.
      if (!hadNativeState) {
        final stillUploading = await UploadQueueRepository.getByStatus('uploading');
        for (final item in stillUploading) {
          if (item.fileUrl != null && item.fileUrl!.isNotEmpty) {
            await UploadQueueRepository.markCompleted(item.id!);
          }
        }
      }
    }

    if (recovered > 0) {
      AppLogger.i('NativeRecovery: recovered $recovered orphaned upload(s) from native layer');
    }
    if (completed > 0) {
      AppLogger.i('NativeRecovery: $completed item(s) marked completed from native layer');
    }
    if (failed > 0) {
      AppLogger.i('NativeRecovery: $failed item(s) marked failed from native layer');
    }
  } catch (e) {
    AppLogger.e('NativeRecovery: error recovering native orphans — $e');
  }
}

/// Phase 3: Clear stale locks so user can instantly restart.
Future<void> _clearStaleLocks() async {
  try {
    await UploadQueueRepository.resetStaleUploading(
        olderThan: const Duration(minutes: 30));
  } catch (e) {
    AppLogger.e('StaleLockClear: error — $e');
  }
}

/// Checks native state first — if items already exist there, just restart the
/// native service without overwriting. Only syncs from SQLite when native
/// state is empty, to avoid interrupting mid-upload items or creating duplicates.
Future<void> _autoResumeIfNeeded() async {
  try {
    final nativeItems = await NativeUploadBridge.getPendingUploads();
    final hasNativeItems = nativeItems.isNotEmpty;

    if (hasNativeItems) {
      final hasActiveItems = nativeItems.any((n) {
        final s = n['status'] as String? ?? '';
        return s == 'pending' || s == 'uploading';
      });
      if (hasActiveItems) {
        AppLogger.i('AutoResume: native state has ${nativeItems.length} active item(s), restarting service only');
        await NativeUploadBridge.startQueueProcessing();
        return;
      }
      // Native state has only completed/failed items — clear it and fall
      // through to SQLite-based resume below.
      await NativeUploadBridge.clearState();
    }

    final pendingCount = await UploadQueueRepository.countPending();
    if (pendingCount == 0) return;

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
    }).toList());

    await NativeUploadBridge.syncQueueToNative(nativeQueueJson);
    await NativeUploadBridge.startQueueProcessing();
  } catch (e) {
    AppLogger.e('AutoResume: error — $e');
  }
}

Future<void> _markItemCompletedInQueue(String filePath) async {
  try {
    final active = await UploadQueueRepository.getActive();
    for (final item in active) {
      if (item.filePath == filePath &&
          item.status != 'completed' &&
          item.status != 'failed') {
        await UploadQueueRepository.markCompleted(item.id!);
        break;
      }
    }
  } catch (e) {
    AppLogger.e('MarkCompleted: error — $e');
  }
}

Future<void> _markItemFailedInQueue(String filePath, String errorMessage) async {
  try {
    final active = await UploadQueueRepository.getActive();
    for (final item in active) {
      if (item.filePath == filePath &&
          item.status != 'completed' &&
          item.status != 'failed') {
        await UploadQueueRepository.markFailed(item.id!, errorMessage);
        break;
      }
    }
  } catch (e) {
    AppLogger.e('MarkFailed: error — $e');
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
