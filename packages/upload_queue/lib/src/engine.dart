import 'models/models.dart';

/// Abstract engine for uploading files.
///
/// The default implementation ([DartHttpEngine]) uses `package:http` and works
/// in the foreground. Swap it for a native implementation to support true
/// background upload (survive app kill like YouTube).
///
/// To build a custom engine, implement every method below. The queue calls
/// these in order:
///   1. [initUpload] — get presigned URLs from your backend
///   2a. [uploadParts] — multipart: upload each part to S3
///   2b. [directUpload] — small file: PUT directly to S3
///   3. [completeMultipart] — multipart: tell S3 the upload is done
///   4. [sendCallback] — notify your backend with the final file URL
///   5. [abortMultipart] — on failure: cancel the multipart upload
///
/// See [DartHttpEngine] for a complete reference implementation.
abstract class UploadEngine {
  UploadEngine(this.config);

  final UploadConfig config;

  /// Initiate upload — calls your backend's init endpoint.
  Future<InitUploadResponse?> initUpload({
    required String filePath,
    Map<String, dynamic>? extraFields,
  });

  /// Upload entire file via direct PUT to presigned URL (single-part path).
  ///
  /// [dbTaskId] is the queue's internal task id used as the native WorkManager
  /// tag so background state can be queried after process death.
  Future<bool> directUpload({
    required String filePath,
    required String uploadUrl,
    void Function(double progress)? onProgress,
    int? dbTaskId,
  });

  /// Upload all multipart parts concurrently in batches.
  ///
  /// [dbTaskId] is the queue's internal task id used as the native WorkManager
  /// tag so background state can be queried after process death.
  Future<List<PartUploadResult>> uploadParts({
    required String filePath,
    required List<PartPresignedUrl> parts,
    required int partSize,
    void Function(int completed, int total)? onProgress,
    int? dbTaskId,
  });

  /// Complete multipart upload — sends ETags to server.
  ///
  /// [extraFields] is merged into the completion body when the backend needs
  /// additional context (e.g. `moduleID`, `videoFilename`) alongside
  /// `uploadId` + `parts`.
  Future<String?> completeMultipart({
    required String s3UploadId,
    required List<PartETag> parts,
    String? endpoint,
    Map<String, dynamic>? extraFields,
  });

  /// Abort multipart upload on S3.
  ///
  /// [s3Key] is the S3 object key required by backends that scope the abort
  /// to a specific object (e.g. `{key, uploadId}`).
  Future<bool> abortMultipart(
    String s3UploadId, {
    String? endpoint,
    String? s3Key,
  });

  /// Send server callback with file metadata.
  ///
  /// [dbTaskId] is threaded to native background workers so their WorkManager
  /// tag matches the DB task id and results survive process death.
  Future<bool> sendCallback(CallbackRequest callback, {int? dbTaskId});

  /// Complete a multipart upload and send the callback in one operation.
  ///
  /// Returns the final [fileUrl] on success, or `null` if either the
  /// complete-multipart or the callback failed.
  ///
  /// Default implementation calls [completeMultipart] then [sendCallback].
  /// Native engines (e.g. [NativeBackgroundEngine]) should override this to
  /// chain both operations in background workers (WorkManager) so the entire
  /// post-upload flow survives app kill.
  Future<String?> completeMultipartAndCallback({
    required String s3UploadId,
    required List<PartETag> parts,
    required CallbackRequest callback,
    String? endpoint,
    int? dbTaskId,
    Map<String, dynamic>? completeExtraFields,
  }) async {
    final fileUrl = await completeMultipart(
      s3UploadId: s3UploadId,
      parts: parts,
      endpoint: endpoint,
      extraFields: completeExtraFields,
    );
    if (fileUrl == null || fileUrl.isEmpty) return null;
    final ok = await sendCallback(
      CallbackRequest(
        url: callback.url,
        body: {...callback.body, 'videoUrl': fileUrl},
        idempotencyKey: callback.idempotencyKey,
      ),
      dbTaskId: dbTaskId,
    );
    return ok ? fileUrl : null;
  }

  /// Check whether a background upload (WorkManager) for [dbTaskId] has
  /// already completed while the app was killed.
  ///
  /// Returns `true` if the upload completed, `false` if still running or
  /// failed, and `null` when the engine cannot determine the state (default).
  Future<bool?> checkUploadCompleted(int dbTaskId) async => null;

  /// Query the outcome of a native complete+callback chain that ran while
  /// the app was killed. Returns a map with `state`
  /// (`success` / `failed` / `running` / `unknown`), optional `fileUrl`,
  /// and optional `error`.
  ///
  /// Default implementation returns null (engine does not track chain state).
  Future<Map<String, dynamic>?> getChainStatus(int dbTaskId) async => null;

  /// Cancel a background upload (WorkManager) for [dbTaskId].
  /// Called before re-queuing a stale task to avoid duplicate workers.
  Future<void> cancelUpload(int dbTaskId) async {}

  /// Refresh presigned URLs for an existing multipart upload.
  ///
  /// Called during resume after app-kill. The engine should obtain fresh
  /// upload URLs for the given [partNumbers] without creating a new S3
  /// multipart session. Defaults to calling [initUpload] which may or may
  /// not return the same [s3UploadId] — engines should override this to
  /// call a dedicated refresh endpoint when available.
  Future<InitUploadResponse?> refreshPresignedUrls({
    required String filePath,
    required String s3UploadId,
    required List<int> partNumbers,
    Map<String, dynamic>? extraFields,
  }) async {
    // Default: fall back to initUpload. Subclasses should override to
    // use a dedicated refresh endpoint that preserves the same uploadId.
    return initUpload(filePath: filePath, extraFields: extraFields);
  }

  /// Release resources (HTTP client, etc.) called by [UploadQueue.dispose].
  void dispose() {}

  /// Compute part size from file size and total parts.
  static int computePartSize(int fileSize, int totalParts) {
    if (totalParts <= 0) return 5 * 1024 * 1024;
    return (fileSize + totalParts - 1) ~/ totalParts;
  }
}
