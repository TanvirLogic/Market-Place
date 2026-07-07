/// Parsed result of the S3 init endpoint. The same endpoint returns either a
/// single direct-upload URL (`isMultipart == false`) or multipart part URLs
/// (`isMultipart == true`).
class S3InitResponse {
  final bool isMultipart;

  /// Direct single-PUT URL (direct only).
  final String? uploadUrl;

  /// Final file/CDN URL (always present).
  final String fileUrl;

  /// S3 object key (needed for complete/abort).
  final String? key;

  /// Human-readable expiry (e.g. "24 hours"), informational.
  final String? expiresIn;

  /// S3 multipart upload id (multipart only).
  final String? s3UploadId;

  final int totalParts;

  /// Presigned URLs per part: `[{partNumber, uploadUrl}]`.
  final List<S3PartUrl> parts;

  const S3InitResponse({
    required this.isMultipart,
    this.uploadUrl,
    required this.fileUrl,
    this.key,
    this.expiresIn,
    this.s3UploadId,
    this.totalParts = 0,
    this.parts = const [],
  });

  /// Parse from a raw response section (already unwrapped to the object that
  /// holds `isMultipart`). Matches the existing backend shape.
  factory S3InitResponse.fromSection(Map<String, dynamic> d) {
    final isMultipart = d['isMultipart'] as bool? ?? false;
    final parts = (d['parts'] as List?)
            ?.map((p) => S3PartUrl.fromMap(p as Map<String, dynamic>))
            .toList() ??
        const <S3PartUrl>[];
    return S3InitResponse(
      isMultipart: isMultipart,
      uploadUrl: d['uploadUrl'] as String?,
      fileUrl: (d['fileUrl'] as String?) ?? '',
      key: d['key'] as String?,
      expiresIn: d['expiresIn'] as String?,
      s3UploadId: isMultipart ? d['uploadId'] as String? : null,
      totalParts: (d['totalParts'] as num?)?.toInt() ?? parts.length,
      parts: parts,
    );
  }

  /// Parse from the full response envelope. Unwraps `data`, and for the course
  /// endpoints that return `data.thumbnail` / `data.video`, selects the section
  /// named by [courseAssetKey] ('thumbnail' or 'video').
  factory S3InitResponse.fromEnvelope(
    Map<String, dynamic> json, {
    String? courseAssetKey,
  }) {
    final d =
        json['data'] is Map ? json['data'] as Map<String, dynamic> : json;
    final nested = d['data'] is Map ? d['data'] as Map<String, dynamic> : null;
    if (nested != null &&
        (nested.containsKey('thumbnail') || nested.containsKey('video'))) {
      final section =
          nested[courseAssetKey ?? 'thumbnail'] as Map<String, dynamic>?;
      if (section != null) return S3InitResponse.fromSection(section);
    }
    return S3InitResponse.fromSection(d);
  }
}

/// A presigned URL for one multipart part from the init response.
class S3PartUrl {
  final int partNumber;
  final String uploadUrl;

  const S3PartUrl({required this.partNumber, required this.uploadUrl});

  factory S3PartUrl.fromMap(Map<String, dynamic> m) => S3PartUrl(
        partNumber: (m['partNumber'] as num?)?.toInt() ?? 0,
        uploadUrl: (m['uploadUrl'] as String?) ?? '',
      );
}
