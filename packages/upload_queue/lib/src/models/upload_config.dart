import 'upload_response.dart';
import 'upload_task.dart';

/// Configuration for the upload queue.
///
/// Every API interaction has a customizable callback, so you can
/// adapt this package to **any** backend response shape.
class UploadConfig {
  /// Endpoint for init/complete/abort upload requests.
  final String initUploadEndpoint;

  /// Provider that returns the current auth token.
  final String Function() tokenProvider;

  /// Builds the callback request after upload completes.
  /// Return null to skip the callback step.
  final CallbackRequest Function(UploadTask task)? buildCallback;

  /// Optional logger.
  final void Function(String message)? logger;

  /// Maximum parts to upload concurrently (multipart only).
  final int maxConcurrentParts;

  /// Maximum retries per part before giving up.
  final int maxPartRetries;

  /// Timeout for uploading a single part.
  final Duration partUploadTimeout;

  /// Timeout for init/complete API calls.
  final Duration apiTimeout;

  /// Human-readable expiry limit before URLs are refreshed.
  final Duration urlExpiryLimit;

  /// Maximum number of tasks allowed in the queue before evicting oldest
  /// failed items. 0 = unlimited. Defaults to 200.
  final int maxQueueSize;

  /// Maximum bytes per second for upload bandwidth throttling.
  /// 0 (default) = unlimited.
  final int maxBytesPerSecond;

  /// When true, uploads only run on unmetered (Wi-Fi) networks. Large video
  /// uploads (300 MB – 2 GB) can be expensive on mobile data, so this maps to
  /// WorkManager's `NetworkType.UNMETERED` on Android and a Wi-Fi wait on iOS.
  /// Default false (upload on any connected network).
  final bool wifiOnly;

  /// Optional predicate deciding whether the source file should be deleted
  /// after a task reaches a terminal *completed* state. Return true only for
  /// files that live in a temp/cache directory your app owns (e.g. copies made
  /// by image_picker). This frees disk promptly instead of waiting for a
  /// periodic sweep — important when uploading multiple 2 GB videos.
  final bool Function(UploadTask task)? shouldDeleteSourceOnComplete;

  /// Provider that returns the current refresh token, or null if unavailable.
  /// Used by native workers to refresh the access token on 401.
  final String Function()? refreshTokenProvider;

  /// The token refresh endpoint URL (e.g. "https://api.example.com/auth/refresh").
  /// Required if [refreshTokenProvider] is provided.
  final String? refreshEndpoint;

  // ────────────────────────────────────────────
  //  API Customization Hooks
  //  Override any of these to match your backend.
  //  Defaults handle the shape documented in planning.md.
  // ────────────────────────────────────────────

  /// Override the endpoint for init upload per task.
  /// Default: null (uses [initUploadEndpoint])
  final String Function(Map<String, dynamic>? extraFields)? buildInitEndpoint;

  /// Build the request body for init upload.
  /// Default: {filename, contentType} + extraFields
  final Map<String, dynamic> Function(
    String fileName,
    Map<String, dynamic>? extraFields,
  )? buildInitBody;

  /// Parse the init response into our internal model.
  /// Default expects: {isMultipart, uploadUrl, fileUrl, key, expiresIn,
  ///                  uploadId, totalParts, parts[{partNumber, uploadUrl}]}
  final InitUploadResponse Function(Map<String, dynamic> json)?
      parseInitResponse;

  /// Build the request body for complete multipart.
  /// Default: {uploadId, parts[{partNumber, eTag}]}
  final Map<String, dynamic> Function(
    String s3UploadId,
    List<PartETag> parts,
  )? buildCompleteBody;

  /// Optional builder for extra fields merged into the complete-multipart body
  /// per task. Use this when your backend needs contextual fields
  /// (e.g. `moduleID`, `videoFilename`, `videoContentType`) on the completion
  /// call in addition to `uploadId` + `parts`.
  final Map<String, dynamic> Function(UploadTask task)?
      buildCompleteExtraFields;

  /// Override the endpoint for complete-multipart per task.
  /// Default: null (falls back to init endpoint or task metadata['initEndpoint']).
  final String Function(UploadTask task)? buildCompleteEndpoint;

  /// Override the endpoint for abort-multipart per task.
  /// Default: null (falls back to the complete/init endpoint).
  final String Function(UploadTask task)? buildAbortEndpoint;

  /// Extract fileUrl from the complete multipart response.
  /// Default: reads json['fileUrl']
  final String? Function(Map<String, dynamic> json)? parseCompleteResponse;

  /// Build the request body for abort multipart.
  /// Default: {uploadId}
  final Map<String, dynamic> Function(String s3UploadId)? buildAbortBody;

  /// Build the request body to refresh a single part's URL.
  /// Default: {uploadId, partNumber}
  final Map<String, dynamic> Function(
    String s3UploadId,
    int partNumber,
  )? buildPartUrlBody;

  /// Parse the refreshed part URL from the response.
  /// Default: reads json['uploadUrl']
  final String? Function(Map<String, dynamic> json)? parsePartUrlResponse;

  /// Extract the ETag from the S3 PUT response headers.
  /// Default: reads headers['etag'] or headers['Etag'], strips quotes.
  final String? Function(Map<String, String> headers)? extractETag;

  const UploadConfig({
    required this.initUploadEndpoint,
    required this.tokenProvider,
    this.buildCallback,
    this.logger,
    this.maxConcurrentParts = 3,
    this.maxPartRetries = 3,
    this.partUploadTimeout = const Duration(hours: 1),
    this.apiTimeout = const Duration(seconds: 30),
    this.urlExpiryLimit = const Duration(hours: 23),
    this.maxQueueSize = 200,
    this.maxBytesPerSecond = 0,
    this.wifiOnly = false,
    this.shouldDeleteSourceOnComplete,
    this.refreshTokenProvider,
    this.refreshEndpoint,
    this.buildInitEndpoint,
    this.buildInitBody,
    this.parseInitResponse,
    this.buildCompleteBody,
    this.buildCompleteExtraFields,
    this.buildCompleteEndpoint,
    this.buildAbortEndpoint,
    this.parseCompleteResponse,
    this.buildAbortBody,
    this.buildPartUrlBody,
    this.parsePartUrlResponse,
    this.extractETag,
  });
}

/// Describes a callback request to the app server after upload completes.
class CallbackRequest {
  final String url;
  final Map<String, dynamic> body;
  final String? idempotencyKey;

  const CallbackRequest({
    required this.url,
    required this.body,
    this.idempotencyKey,
  });
}
