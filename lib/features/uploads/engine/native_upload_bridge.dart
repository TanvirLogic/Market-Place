import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:edtech/global/core/services/logger_service.dart';

/// Dart ↔ Android bridge for the native WorkManager upload pipeline.
///
/// On Android the whole upload (init → transfer → complete → callback) runs in
/// a native [UploadWorker] chained via WorkManager, so queued videos upload to
/// the server one-by-one and complete even while the app is killed. This bridge
/// only enqueues jobs, keeps the native auth token in sync, and reads back
/// terminal results for the UI to reconcile.
///
/// On iOS the bridge is a no-op — the `background_downloader` flow is used.
class NativeUploadBridge {
  static const _channel = MethodChannel('eduverse/native_upload');

  /// Whether the current platform uses the native upload pipeline.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Mirror the current access/refresh tokens into native storage so the worker
  /// can authenticate (and refresh) without the Dart isolate being alive.
  static Future<void> syncTokens({
    required String accessToken,
    required String refreshToken,
    required String refreshUrl,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('syncTokens', {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'refreshUrl': refreshUrl,
      });
    } catch (e) {
      AppLogger.e('NativeUploadBridge.syncTokens error: $e');
    }
  }

  /// Append [jobData] to the native upload queue. Returns true if enqueued.
  static Future<bool> enqueueUpload(Map<String, dynamic> jobData) async {
    if (!isSupported) return false;
    try {
      await _channel.invokeMethod('enqueueUpload', {
        'jobData': jsonEncode(jobData),
      });
      return true;
    } catch (e) {
      AppLogger.e('NativeUploadBridge.enqueueUpload error: $e');
      return false;
    }
  }

  /// Return all completed/failed upload results from the native pipeline.
  static Future<List<Map<String, dynamic>>> getCompletedJobs() async {
    if (!isSupported) return [];
    try {
      final list = await _channel.invokeMethod<List>('getCompletedJobs');
      if (list == null) return [];
      return list
          .map((e) => Map<String, dynamic>.from(jsonDecode(e as String)))
          .toList();
    } catch (e) {
      AppLogger.e('NativeUploadBridge.getCompletedJobs error: $e');
      return [];
    }
  }

  /// Remove the persisted result for [jobId] after reconciling.
  static Future<void> clearResult(String jobId) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('clearResult', {'jobId': jobId});
    } catch (_) {}
  }

  /// Get current progress for an active job (0-100, or null if unknown/terminal).
  static Future<int?> getProgress(String jobId) async {
    if (!isSupported) return null;
    try {
      final pct = await _channel.invokeMethod<int>('getProgress', {'jobId': jobId});
      return pct;
    } catch (_) {
      return null;
    }
  }

  /// Cancel the entire native upload queue.
  static Future<void> cancelAll() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('cancelAll');
    } catch (_) {}
  }
}
