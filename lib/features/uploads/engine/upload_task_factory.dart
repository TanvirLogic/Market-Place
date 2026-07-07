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

  /// A binary PUT of the whole file to a single presigned URL (direct, <15 MB).
  Future<UploadTask> directTask(UploadJob job) async {
    final (baseDir, dir, filename) = await Task.split(filePath: job.filePath);
    return UploadTask(
      taskId: directTaskId(job.id),
      url: job.directUploadUrl!,
      httpRequestMethod: 'PUT',
      post: 'binary',
      filename: filename,
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

  Map<String, dynamic> _baseMeta(UploadJob job) => {
        'jobId': job.id,
        'type': job.type.wire,
        'isMultipart': job.isMultipart,
      };
}
