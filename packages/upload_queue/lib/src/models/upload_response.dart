/// Response from the unified init endpoint.
class InitUploadResponse {
  final bool isMultipart;

  /// For single upload (< 15MB)
  final String? uploadUrl;

  /// Always present
  final String fileUrl;

  /// S3 object key
  final String? key;

  /// Human-readable expiry (e.g. "24 hours")
  final String? expiresIn;

  /// For multipart upload (>= 15MB)
  final String? s3UploadId;
  final int totalParts;
  final List<PartPresignedUrl> parts;

  const InitUploadResponse({
    required this.isMultipart,
    this.uploadUrl,
    required this.fileUrl,
    this.key,
    this.expiresIn,
    this.s3UploadId,
    this.totalParts = 0,
    this.parts = const [],
  });

  factory InitUploadResponse.fromJson(Map<String, dynamic> json) {
    final d = json['data'] is Map
        ? json['data'] as Map<String, dynamic>
        : json;
    final isMultipart = d['isMultipart'] as bool? ?? false;
    final partsRaw = d['parts'] as List?;
    final parts = partsRaw
            ?.map((p) => PartPresignedUrl.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];
    return InitUploadResponse(
      isMultipart: isMultipart,
      uploadUrl: d['uploadUrl'] as String?,
      fileUrl: (d['fileUrl'] as String?) ?? '',
      key: d['key'] as String?,
      expiresIn: d['expiresIn'] as String?,
      s3UploadId: isMultipart ? d['uploadId'] as String? : null,
      totalParts: d['totalParts'] as int? ?? parts.length,
      parts: parts,
    );
  }
}

/// A single part's presigned URL from the init response.
class PartPresignedUrl {
  final int partNumber;
  final String uploadUrl;

  const PartPresignedUrl({
    required this.partNumber,
    required this.uploadUrl,
  });

  Map<String, dynamic> toJson() => {
    'partNumber': partNumber,
    'uploadUrl': uploadUrl,
  };

  factory PartPresignedUrl.fromJson(Map<String, dynamic> json) =>
      PartPresignedUrl(
        partNumber: (json['partNumber'] as num?)?.toInt() ?? 0,
        uploadUrl: (json['uploadUrl'] as String?) ?? '',
      );
}

/// An ETag result from uploading a part.
class PartETag {
  final int partNumber;
  final String eTag;

  const PartETag({required this.partNumber, required this.eTag});

  Map<String, dynamic> toJson() => {
    'partNumber': partNumber,
    'eTag': eTag,
  };

  factory PartETag.fromJson(Map<String, dynamic> json) => PartETag(
    partNumber: (json['partNumber'] as num?)?.toInt() ?? 0,
    eTag: (json['eTag'] as String?) ?? '',
  );
}

/// Result of uploading a single part.
class PartUploadResult {
  final int partNumber;
  final bool success;
  final String? eTag;
  final String? errorMessage;
  final bool isUrlExpired;

  const PartUploadResult({
    required this.partNumber,
    required this.success,
    this.eTag,
    this.errorMessage,
    this.isUrlExpired = false,
  });
}
