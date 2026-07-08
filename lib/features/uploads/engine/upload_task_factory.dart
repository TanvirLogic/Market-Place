import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

import '../data/models/upload_job.dart';

/// Builds `background_downloader` [UploadTask]s for S3 uploads.
///
/// Design notes:
/// * S3 presigned uploads are **binary PUTs** → `post: 'binary'`,
///   `httpRequestMethod: 'PUT'`.
/// * Multipart parts are uploaded via a `Range: bytes=start-end` header into the
///   ORIGINAL file — `background_downloader` slices the bytes natively, so we
///   never write temp part files. (The Range header is consumed by the package
///   and not forwarded to S3.)
/// * `taskId` encodes job + part so we can route status updates back to the job.
/// * `group` is per-job so all parts of one upload are managed together.
/// * `metaData` carries the S3 context (JSON) needed to advance the flow after
///   an app kill, read back from the package's persistent database.
class UploadTaskFactory {
  const UploadTaskFactory();

  /// Prefix for all groups so we can identify our tasks in the shared database.
  static const String groupPrefix = 'eduverse_upload';

  static String groupFor(String jobId) => '${groupPrefix}_$jobId';

  static String directTaskId(String jobId) => '${jobId}__direct';

  static String partTaskId(String jobId, int partNumber) =>
      '${jobId}__p$partNumber';

  static String completeTaskId(String jobId) => '${jobId}__complete';

  static String callbackTaskId(String jobId) => '${jobId}__callback';

  /// Extract the jobId from any of our task ids.
  static String jobIdOf(String taskId) => taskId.split('__').first;

  /// Returns the part number for a part task id, or null for a direct task.
  static int? partNumberOf(String taskId) {
    final tail = taskId.split('__').last;
    if (tail.startsWith('p')) {
      return int.tryParse(tail.substring(1));
    }
    return null;
  }

  /// Whether [taskId] belongs to an API call (complete or callback).
  static bool isApiTask(String taskId) =>
      taskId.endsWith('__complete') || taskId.endsWith('__callback');

  /// A binary PUT of the whole file to a single presigned URL (direct, <15 MB).
  Future<UploadTask> directTask(UploadJob job) async {
    final (baseDir, dir, filename) = await Task.split(filePath: job.filePath);
    return UploadTask(
      taskId: directTaskId(job.id),
      url: job.directUploadUrl!,
      httpRequestMethod: 'PUT',
      post: 'binary',
      filename: filename,
      displayName: job.title,
      baseDirectory: baseDir,
      directory: dir,
      group: groupFor(job.id),
      headers: {
        // Omit Content-Disposition — S3 presigned PUTs don't want it.
        'Content-Disposition': '',
      },
      updates: Updates.statusAndProgress,
      retries: 3,
      metaData: jsonEncode(_baseMeta(job)),
    );
  }

  /// A binary PUT of one byte-range of the file to a part's presigned URL
  /// (multipart, >=15 MB). The `Range` header tells background_downloader which
  /// slice of the file to send.
  Future<UploadTask> partTask(UploadJob job, UploadPart part) async {
    final (baseDir, dir, filename) = await Task.split(filePath: job.filePath);
    return UploadTask(
      taskId: partTaskId(job.id, part.partNumber),
      url: part.uploadUrl,
      httpRequestMethod: 'PUT',
      post: 'binary',
      filename: filename,
      displayName: job.title,
      baseDirectory: baseDir,
      directory: dir,
      group: groupFor(job.id),
      headers: {
        'Content-Disposition': '',
        'Range': part.rangeHeader,
      },
      updates: Updates.statusAndProgress,
      retries: 3,
      metaData: jsonEncode({
        ..._baseMeta(job),
        'partNumber': part.partNumber,
      }),
    );
  }

  /// A JSON POST via DataTask for the S3 complete step.
  ///   URL: [url] (route.completeEndpoint)
  ///   Body: { key, uploadId, parts }
  ///   Auth: passed via [token] so the task carries its own credential.
  ///   method: defaults to 'POST', set to 'PUT' for avatar/cover endpoints.
  DataTask completeTask({
    required UploadJob job,
    required String url,
    required String body,
    required String token,
    String method = 'POST',
  }) {
    return DataTask(
      taskId: completeTaskId(job.id),
      url: url,
      httpRequestMethod: method,
      post: body,
      headers: _authHeaders(token),
      group: groupFor(job.id),
      updates: Updates.status,
      metaData: jsonEncode({
        ..._baseMeta(job),
        'step': 'complete',
      }),
    );
  }

  /// A JSON POST/PUT via DataTask for the upload callback.
  ///   Includes the Idempotency-Key so HTTP 409 is returned on replay.
  DataTask callbackTask({
    required UploadJob job,
    required String url,
    required String body,
    required String token,
    required String method,
  }) {
    return DataTask(
      taskId: callbackTaskId(job.id),
      url: url,
      httpRequestMethod: method,
      post: body,
      headers: {
        ..._authHeaders(token),
        'Idempotency-Key': '${job.id}_callback',
      },
      group: groupFor(job.id),
      updates: Updates.status,
      metaData: jsonEncode({
        ..._baseMeta(job),
        'step': 'callback',
      }),
    );
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _baseMeta(UploadJob job) => {
        'jobId': job.id,
        'type': job.type.wire,
        'isMultipart': job.isMultipart,
      };
}
