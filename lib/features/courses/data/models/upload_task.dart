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


