import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingUploadPath {
  final String key;
  final String filePath;
  final String uploadType;
  final String title;
  final String? metadata;
  final DateTime createdAt;

  const PendingUploadPath({
    required this.key,
    required this.filePath,
    required this.uploadType,
    required this.title,
    this.metadata,
    required this.createdAt,
  });

  bool get fileExists => File(filePath).existsSync();

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'uploadType': uploadType,
    'title': title,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingUploadPath.fromJson(String key, Map<String, dynamic> json) =>
      PendingUploadPath(
        key: key,
        filePath: json['filePath'] as String,
        uploadType: json['uploadType'] as String? ?? 'video_post',
        title: json['title'] as String? ?? '',
        metadata: json['metadata'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class UploadPathStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _prefix = 'pending_upload_';
  static const String _queueKey = 'upload_queue_atomic';

  // ---- Individual key-based storage (backward compatible) ----

  static Future<void> savePath({
    required String filePath,
    required String uploadType,
    required String title,
    String? metadata,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final key = '$_prefix$timestamp';
    final value = jsonEncode({
      'filePath': filePath,
      'uploadType': uploadType,
      'title': title,
      'metadata': metadata,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _storage.write(key: key, value: value);
    // Also sync to atomic queue
    await _syncToAtomicQueue();
  }

  static Future<void> removePath(String key) async {
    await _storage.delete(key: key);
    await _syncToAtomicQueue();
  }

  /// Removes the FSS entry whose [filePath] matches, then resyncs the atomic queue.
  static Future<void> removePathByFilePath(String filePath) async {
    final all = await _storage.readAll();
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_prefix)) continue;
      if (entry.value.isEmpty) continue;
      try {
        final json = jsonDecode(entry.value) as Map<String, dynamic>;
        if (json['filePath'] == filePath) {
          await _storage.delete(key: entry.key);
        }
      } catch (_) {}
    }
    await _syncToAtomicQueue();
  }

  static Future<List<PendingUploadPath>> getAllPendingPaths() async {
    final all = await _storage.readAll();
    final paths = <PendingUploadPath>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_prefix)) continue;
      if (entry.value.isEmpty) continue;
      try {
        final json = jsonDecode(entry.value) as Map<String, dynamic>;
        paths.add(PendingUploadPath.fromJson(entry.key, json));
      } catch (_) {}
    }
    paths.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return paths;
  }

  static Future<void> clearAll() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_prefix) || key == _queueKey) {
        await _storage.delete(key: key);
      }
    }
  }

  static Future<void> removeStalePaths() async {
    final paths = await getAllPendingPaths();
    for (final path in paths) {
      if (!path.fileExists) {
        await removePath(path.key);
      }
    }
  }

  // ---- Atomic queue (single JSON blob for native sync) ----

  /// Serializes the full queue as a JSON array into a single secure storage key.
  /// This enables atomic read/write and easy native sync.
  static Future<void> _syncToAtomicQueue() async {
    try {
      final paths = await getAllPendingPaths();
      final queueJson = jsonEncode(
        paths.map((p) => {
          'key': p.key,
          'filePath': p.filePath,
          'uploadType': p.uploadType,
          'title': p.title,
          'metadata': p.metadata,
          'createdAt': p.createdAt.toIso8601String(),
        }).toList(),
      );
      await _storage.write(key: _queueKey, value: queueJson);
    } catch (_) {}
  }

  /// Returns the atomic queue as a JSON string (for native MethodChannel sync).
  /// Uses a stable hash of the file path as the id to ensure consistency
  /// across app restarts and crash recovery cycles.
  static Future<String> getAtomicQueueJson() async {
    try {
      final paths = await getAllPendingPaths();
      final items = paths.map((p) => {
        'id': p.filePath.hashCode & 0x7FFFFFFFFFFFFFFF,
        'filePath': p.filePath,
        'title': p.title,
        'uploadUrl': null,
        'contentType': _inferContentType(p.filePath),
        'uploadType': p.uploadType,
        'metadata': p.metadata,
      }).toList();
      return jsonEncode(items);
    } catch (_) {
      return '[]';
    }
  }

  /// Remove items from the atomic queue whose filePath matches completed items.
  static Future<void> removeCompletedPaths(List<String> completedFilePaths) async {
    final paths = await getAllPendingPaths();
    for (final path in paths) {
      if (completedFilePaths.contains(path.filePath)) {
        await _storage.delete(key: path.key);
      }
    }
    await _syncToAtomicQueue();
  }

  // ──────────────────────────────────────────────
  //  Pending edit callback storage (course edit flow)
  // ──────────────────────────────────────────────

  static String _inferContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
      case 'quicktime':
        return 'video/quicktime';
      case 'mkv':
      case 'x-matroska':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }
}
