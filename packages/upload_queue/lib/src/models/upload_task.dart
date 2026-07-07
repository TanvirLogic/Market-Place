/// State of an upload task.
enum UploadState {
  pending,
  uploading,
  completed,
  failed,
  cancelled,
}

/// Represents a single file upload within the queue.
class UploadTask {
  final int id;
  final String filePath;
  final String title;
  final UploadState state;
  final double progress;
  final int totalParts;
  final int partsCompleted;
  final String? s3UploadId;

  /// S3 object key (e.g. "videos/uuid.mp4"). Returned by the init response and
  /// required by the complete-multipart and abort endpoints. Persisted so both
  /// survive an app-kill resume.
  final String? s3Key;

  final String? errorMessage;
  final Map<String, dynamic>? metadata;
  final String? fileUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UploadTask({
    required this.id,
    required this.filePath,
    required this.title,
    this.state = UploadState.pending,
    this.progress = 0.0,
    this.totalParts = 0,
    this.partsCompleted = 0,
    this.s3UploadId,
    this.s3Key,
    this.errorMessage,
    this.metadata,
    this.fileUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  UploadTask copyWith({
    int? id,
    String? filePath,
    String? title,
    UploadState? state,
    double? progress,
    int? totalParts,
    int? partsCompleted,
    String? s3UploadId,
    String? s3Key,
    String? errorMessage,
    Map<String, dynamic>? metadata,
    String? fileUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UploadTask(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      totalParts: totalParts ?? this.totalParts,
      partsCompleted: partsCompleted ?? this.partsCompleted,
      s3UploadId: s3UploadId ?? this.s3UploadId,
      s3Key: s3Key ?? this.s3Key,
      errorMessage: errorMessage ?? this.errorMessage,
      metadata: metadata ?? this.metadata,
      fileUrl: fileUrl ?? this.fileUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
