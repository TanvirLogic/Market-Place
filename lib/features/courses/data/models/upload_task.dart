enum UploadTaskType {
  videoPost,
  course,
  moduleLesson,
  resource;

  String get dbValue {
    switch (this) {
      case UploadTaskType.videoPost:
        return 'video_post';
      case UploadTaskType.course:
        return 'course';
      case UploadTaskType.moduleLesson:
        return 'module_lesson';
      case UploadTaskType.resource:
        return 'resource';
    }
  }

  static UploadTaskType fromDb(String value) {
    switch (value) {
      case 'video_post':
        return UploadTaskType.videoPost;
      case 'course':
        return UploadTaskType.course;
      case 'module_lesson':
        return UploadTaskType.moduleLesson;
      case 'resource':
        return UploadTaskType.resource;
      default:
        return UploadTaskType.videoPost;
    }
  }
}

class CourseUploadMetadata {
  final String courseTitle;
  final String shortDescription;
  final String description;
  final String requirements;
  final String language;
  final String level;
  final String type;
  final double price;
  final String? videoPath;

  const CourseUploadMetadata({
    required this.courseTitle,
    required this.shortDescription,
    required this.description,
    required this.requirements,
    required this.language,
    required this.level,
    required this.type,
    required this.price,
    this.videoPath,
  });

  Map<String, dynamic> toJson() => {
    'courseTitle': courseTitle,
    'shortDescription': shortDescription,
    'description': description,
    'requirements': requirements,
    'language': language,
    'level': level,
    'type': type,
    'price': price,
    'videoPath': videoPath,
  };

  factory CourseUploadMetadata.fromJson(Map<String, dynamic> json) =>
      CourseUploadMetadata(
        courseTitle: json['courseTitle'] as String,
        shortDescription: json['shortDescription'] as String? ?? '',
        description: json['description'] as String? ?? '',
        requirements: json['requirements'] as String? ?? '',
        language: json['language'] as String? ?? '',
        level: json['level'] as String? ?? '',
        type: json['type'] as String? ?? 'FREE',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        videoPath: json['videoPath'] as String?,
      );
}

/// Response from the unified init endpoint.
/// The same endpoint returns either a direct-single upload URL or multipart info.
class UploadInitResponse {
  final bool isMultipart;

  // For single upload (< 15MB)
  final String? uploadUrl;

  // Always present
  final String fileUrl;

  // S3 object key
  final String? key;

  // Human-readable expiry (e.g. "24 hours")
  final String? expiresIn;

  // For multipart upload (>= 15MB)
  final String? s3UploadId;
  final int totalParts;
  final List<PartPresignedUrl> parts;

  const UploadInitResponse({
    required this.isMultipart,
    this.uploadUrl,
    required this.fileUrl,
    this.key,
    this.expiresIn,
    this.s3UploadId,
    this.totalParts = 0,
    this.parts = const [],
  });

  factory UploadInitResponse.fromJson(Map<String, dynamic> json) {
    final isMultipart = json['isMultipart'] as bool? ?? false;
    final parts = (json['parts'] as List?)
            ?.map((p) => PartPresignedUrl.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];
    return UploadInitResponse(
      isMultipart: isMultipart,
      uploadUrl: json['uploadUrl'] as String?,
      fileUrl: json['fileUrl'] as String,
      key: json['key'] as String?,
      expiresIn: json['expiresIn'] as String?,
      s3UploadId: isMultipart ? json['uploadId'] as String? : null,
      totalParts: json['totalParts'] as int? ?? parts.length,
      parts: parts,
    );
  }
}

class MultipartInitResult {
  final String s3UploadId;
  final int partSize;
  final int totalParts;
  final List<PartPresignedUrl> parts;

  const MultipartInitResult({
    required this.s3UploadId,
    required this.partSize,
    required this.totalParts,
    required this.parts,
  });

  Map<String, dynamic> toJson() => {
    's3UploadId': s3UploadId,
    'partSize': partSize,
    'totalParts': totalParts,
    'parts': parts.map((p) => p.toJson()).toList(),
  };

  factory MultipartInitResult.fromJson(Map<String, dynamic> json) =>
      MultipartInitResult(
        s3UploadId: json['uploadId'] as String,
        partSize: 0,
        totalParts: json['totalParts'] as int,
        parts: (json['parts'] as List)
            .map((p) => PartPresignedUrl.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

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
        partNumber: json['partNumber'] as int,
        uploadUrl: json['uploadUrl'] as String,
      );
}

class PartETag {
  final int partNumber;
  final String eTag;

  const PartETag({required this.partNumber, required this.eTag});

  Map<String, dynamic> toJson() => {
    'partNumber': partNumber,
    'eTag': eTag,
  };

  factory PartETag.fromJson(Map<String, dynamic> json) => PartETag(
    partNumber: json['partNumber'] as int,
    eTag: json['eTag'] as String,
  );
}

class ModuleLessonMetadata {
  final int moduleId;
  final int courseId;
  final String lessonTitle;
  final String? contentType;
  final int? lessonId;

  const ModuleLessonMetadata({
    required this.moduleId,
    required this.courseId,
    required this.lessonTitle,
    this.contentType,
    this.lessonId,
  });

  Map<String, dynamic> toJson() => {
    'moduleId': moduleId,
    'courseId': courseId,
    'lessonTitle': lessonTitle,
    'contentType': contentType,
    if (lessonId != null) 'lessonId': lessonId,
  };

  factory ModuleLessonMetadata.fromJson(Map<String, dynamic> json) =>
      ModuleLessonMetadata(
        moduleId: json['moduleId'] as int,
        courseId: json['courseId'] as int,
        lessonTitle: json['lessonTitle'] as String,
        contentType: json['contentType'] as String?,
        lessonId: json['lessonId'] as int?,
      );
}


