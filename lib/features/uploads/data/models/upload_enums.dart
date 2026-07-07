/// Upload domain enums, shared across the new background_downloader-based system.
library;

/// The asset category being uploaded. Drives which init/callback endpoints and
/// request bodies are used, but every type follows the same S3 rules:
/// `< 15 MB` → direct PUT, `>= 15 MB` → multipart.
enum UploadAssetType {
  videoPost('video_post'),
  course('course'),
  courseIntro('course_intro'),
  courseThumb('course_thumb'),
  moduleLesson('module_lesson'),
  resource('resource'),
  avatar('avatar'),
  cover('cover');

  const UploadAssetType(this.wire);

  /// Stable string persisted in Hive and used in metadata maps.
  final String wire;

  static UploadAssetType fromWire(String? value) {
    for (final t in UploadAssetType.values) {
      if (t.wire == value) return t;
    }
    return UploadAssetType.videoPost;
  }
}

/// Lifecycle state of an upload job.
enum UploadJobState {
  pending('pending'),
  uploading('uploading'),
  completing('completing'),
  callback('callback'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const UploadJobState(this.wire);

  final String wire;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;

  bool get isActive => this == pending || this == uploading ||
      this == completing || this == callback;

  static UploadJobState fromWire(String? value) {
    for (final s in UploadJobState.values) {
      if (s.wire == value) return s;
    }
    return UploadJobState.pending;
  }
}
