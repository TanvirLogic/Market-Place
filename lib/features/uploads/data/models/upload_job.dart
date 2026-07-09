import 'dart:convert';

import 'upload_enums.dart';

/// Size boundary for the S3 rule: files strictly below this use a single direct
/// PUT; files at or above use multipart. 15 MiB, matching the backend contract.
const int kMultipartThresholdBytes = 15 * 1024 * 1024;

/// One S3 multipart part. For background_downloader we do NOT slice the file on
/// disk; instead each part is uploaded via a `Range: bytes=start-end` header
/// into the original file. [rangeStart] is inclusive, [rangeEnd] inclusive.
/// [rangeEnd] == -1 means "to end of file" (last part).
class UploadPart {
  final int partNumber;
  final int rangeStart;
  final int rangeEnd;

  /// Presigned PUT URL for this part (may be refreshed after expiry).
  String uploadUrl;

  /// S3 ETag captured from the PUT response header once the part completes.
  /// Preserved verbatim (including surrounding quotes) — the complete endpoint
  /// expects the raw header value.
  String? eTag;

  bool get done => eTag != null && eTag!.isNotEmpty;

  UploadPart({
    required this.partNumber,
    required this.rangeStart,
    required this.rangeEnd,
    required this.uploadUrl,
    this.eTag,
  });

  /// HTTP Range header value for background_downloader, e.g. `bytes=0-104857599`.
  /// Omits the end for the final part (`bytes=419430400-`).
  String get rangeHeader =>
      rangeEnd < 0 ? 'bytes=$rangeStart-' : 'bytes=$rangeStart-$rangeEnd';

  Map<String, dynamic> toMap() => {
        'partNumber': partNumber,
        'rangeStart': rangeStart,
        'rangeEnd': rangeEnd,
        'uploadUrl': uploadUrl,
        'eTag': eTag,
      };

  factory UploadPart.fromMap(Map<dynamic, dynamic> m) => UploadPart(
        partNumber: (m['partNumber'] as num).toInt(),
        rangeStart: (m['rangeStart'] as num).toInt(),
        rangeEnd: (m['rangeEnd'] as num).toInt(),
        uploadUrl: m['uploadUrl'] as String? ?? '',
        eTag: m['eTag'] as String?,
      );
}

/// A single upload job persisted in Hive. Represents one file being uploaded
/// through the full init → transfer → complete → callback flow.
class UploadJob {
  /// Stable unique id (also used as the background_downloader task group).
  final String id;

  /// Absolute path to the source file on device.
  final String filePath;

  final UploadAssetType type;

  /// Human-readable title shown in the UI.
  final String title;

  final int fileSize;

  UploadJobState state;
  double progress; // 0.0 – 1.0

  /// Whether the backend chose multipart for this job.
  bool isMultipart;

  /// S3 object key returned by init (needed for complete/abort).
  String? key;

  /// S3 multipart upload id (multipart only).
  String? s3UploadId;

  /// Presigned URL for the single direct PUT (direct only).
  String? directUploadUrl;

  /// Final CDN/file URL (from init, confirmed at complete).
  String? fileUrl;

  final List<UploadPart> parts;

  /// Arbitrary per-type context (moduleId, courseId, duration, endpoints…).
  final Map<String, dynamic> metadata;

  /// Last error message, if failed.
  String? error;

  /// Upload speed in bytes per second (for UI display).
  double? speedBytesPerSec;

  /// Estimated remaining time in seconds (for UI display).
  int? etaSeconds;

  /// When the transfer phase started (epoch ms). Used for speed calculation.
  int? transferStartedAt;

  /// Bytes uploaded so far in the transfer phase.
  int transferredBytes;

  final int createdAt;
  int updatedAt;

  UploadJob({
    required this.id,
    required this.filePath,
    required this.type,
    required this.title,
    required this.fileSize,
    this.state = UploadJobState.pending,
    this.progress = 0.0,
    this.isMultipart = false,
    this.key,
    this.s3UploadId,
    this.directUploadUrl,
    this.fileUrl,
    List<UploadPart>? parts,
    Map<String, dynamic>? metadata,
    this.error,
    this.speedBytesPerSec,
    this.etaSeconds,
    this.transferStartedAt,
    this.transferredBytes = 0,
    int? createdAt,
    int? updatedAt,
  })  : parts = parts ?? <UploadPart>[],
        metadata = metadata ?? <String, dynamic>{},
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Client-side prediction of the S3 rule. The server is authoritative, but
  /// this lets us sanity-check and choose the right init flags.
  bool get predictedMultipart => fileSize >= kMultipartThresholdBytes;

  int get partsCompleted => parts.where((p) => p.done).length;

  /// ETags for the complete-multipart request, ordered by part number.
  List<Map<String, dynamic>> get etagPayload {
    final sorted = [...parts]..sort((a, b) => a.partNumber.compareTo(b.partNumber));
    return sorted
        .where((p) => p.done)
        .map((p) => {'partNumber': p.partNumber, 'eTag': p.eTag})
        .toList();
  }

  void touch() => updatedAt = DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'filePath': filePath,
        'type': type.wire,
        'title': title,
        'fileSize': fileSize,
        'state': state.wire,
        'progress': progress,
        'isMultipart': isMultipart,
        'key': key,
        's3UploadId': s3UploadId,
        'directUploadUrl': directUploadUrl,
        'fileUrl': fileUrl,
        'parts': parts.map((p) => p.toMap()).toList(),
        'metadata': jsonEncode(metadata),
        'error': error,
        'speedBytesPerSec': speedBytesPerSec,
        'etaSeconds': etaSeconds,
        'transferStartedAt': transferStartedAt,
        'transferredBytes': transferredBytes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory UploadJob.fromMap(Map<dynamic, dynamic> m) {
    final rawMeta = m['metadata'];
    Map<String, dynamic> meta = {};
    if (rawMeta is String && rawMeta.isNotEmpty) {
      try {
        meta = Map<String, dynamic>.from(jsonDecode(rawMeta) as Map);
      } catch (_) {}
    } else if (rawMeta is Map) {
      meta = Map<String, dynamic>.from(rawMeta);
    }
    return UploadJob(
      id: m['id'] as String,
      filePath: m['filePath'] as String,
      type: UploadAssetType.fromWire(m['type'] as String?),
      title: m['title'] as String? ?? '',
      fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
      state: UploadJobState.fromWire(m['state'] as String?),
      progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
      isMultipart: m['isMultipart'] as bool? ?? false,
      key: m['key'] as String?,
      s3UploadId: m['s3UploadId'] as String?,
      directUploadUrl: m['directUploadUrl'] as String?,
      fileUrl: m['fileUrl'] as String?,
      parts: (m['parts'] as List?)
              ?.map((p) => UploadPart.fromMap(p as Map))
              .toList() ??
          <UploadPart>[],
      metadata: meta,
      error: m['error'] as String?,
      speedBytesPerSec: (m['speedBytesPerSec'] as num?)?.toDouble(),
      etaSeconds: (m['etaSeconds'] as num?)?.toInt(),
      transferStartedAt: (m['transferStartedAt'] as num?)?.toInt(),
      transferredBytes: (m['transferredBytes'] as num?)?.toInt() ?? 0,
      createdAt: (m['createdAt'] as num?)?.toInt(),
      updatedAt: (m['updatedAt'] as num?)?.toInt(),
    );
  }
}
