import 'dart:io';

import '../data/models/upload_enums.dart';
import '../data/models/upload_job.dart';
import '../service/upload_service.dart';

/// Result of a one-shot image upload.
class ImageUploadResult {
  final bool isSuccess;
  final String? fileUrl;
  final String? errorMessage;
  const ImageUploadResult({
    required this.isSuccess,
    this.fileUrl,
    this.errorMessage,
  });
}

/// Convenience wrapper for one-shot image uploads (avatar / cover) that runs the
/// same S3 flow as everything else (init → PUT → [complete] → confirm callback)
/// and awaits completion. Images are almost always < 15 MB so they take the
/// direct-PUT path, but multipart is handled transparently if the backend asks
/// for it.
///
/// Unlike the queue-based flow, this awaits the final result so the caller can
/// update the UI immediately — matching the previous `S3UploadService` UX.
class ImageUploadHelper {
  ImageUploadHelper({UploadService? service})
      : _service = service ?? UploadService();

  final UploadService _service;

  /// Uploads [filePath] as the given image [type] (avatar or cover) and
  /// resolves with the final file URL.
  Future<ImageUploadResult> upload({
    required String filePath,
    required UploadAssetType type,
    required String title,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return const ImageUploadResult(
        isSuccess: false,
        errorMessage: 'File not found',
      );
    }

    final fileSize = await file.length();
    final id = 'img_${DateTime.now().millisecondsSinceEpoch}';

    final progressSub = onProgress == null
        ? null
        : _service.updates.listen((j) {
            if (j.id == id) onProgress(j.progress);
          });

    try {
      await _service.ensureStarted();
      final job = await _service.enqueue(
        id: id,
        filePath: filePath,
        type: type,
        title: title,
        fileSize: fileSize,
        metadata: {'fileSize': fileSize, 'uploadType': type.wire},
      );

      final done = await _awaitTerminal(job.id);
      if (done.state == UploadJobState.completed) {
        return ImageUploadResult(isSuccess: true, fileUrl: done.fileUrl);
      }
      return ImageUploadResult(
        isSuccess: false,
        errorMessage: done.error ?? 'Upload failed',
      );
    } finally {
      await progressSub?.cancel();
    }
  }

  Future<UploadJob> _awaitTerminal(String id) async {
    final current = _service.job(id);
    if (current != null && current.state.isTerminal) return current;
    await for (final j in _service.updates) {
      if (j.id == id && j.state.isTerminal) return j;
    }
    return _service.job(id)!;
  }

  Future<void> dispose() => _service.dispose();
}
