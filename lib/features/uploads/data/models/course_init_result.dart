import 's3_init_response.dart';

/// Holds both thumbnail and video presigned URL data from the combined
/// `course/assets/upload` endpoint. One or both may be present depending on
/// what was sent in the request body.
class CourseInitResult {
  final S3InitResponse? thumbnail;
  final S3InitResponse? video;

  const CourseInitResult({this.thumbnail, this.video});

  /// Parse from the full response envelope for the course/assets/upload endpoint.
  ///
  /// Expected shape:
  /// ```json
  /// {
  ///   "data": {
  ///     "data": {
  ///       "thumbnail": { ... },
  ///       "video": { ... } | null
  ///     }
  ///   }
  /// }
  /// ```
  factory CourseInitResult.fromEnvelope(Map<String, dynamic> json) {
    final d = json['data'] is Map ? json['data'] as Map<String, dynamic> : json;
    final nested = d['data'] is Map ? d['data'] as Map<String, dynamic> : null;
    if (nested == null) {
      return const CourseInitResult();
    }

    S3InitResponse? thumbnail;
    if (nested['thumbnail'] is Map) {
      thumbnail = S3InitResponse.fromSection(
        Map<String, dynamic>.from(nested['thumbnail'] as Map),
      );
    }

    S3InitResponse? video;
    if (nested['video'] is Map) {
      video = S3InitResponse.fromSection(
        Map<String, dynamic>.from(nested['video'] as Map),
      );
    }

    return CourseInitResult(thumbnail: thumbnail, video: video);
  }
}
