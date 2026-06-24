enum LessonType { video, resource }

class Lesson {
  final int id;
  String title;
  final String duration;
  final LessonType type;
  String? videoUrl;
  final String? fileUrl;
  final String? fileType;
  double uploadProgress;
  String uploadStatus;

  Lesson({
    required this.id,
    required this.title,
    required this.duration,
    required this.type,
    this.videoUrl,
    this.fileUrl,
    this.fileType,
    this.uploadProgress = 0.0,
    this.uploadStatus = 'completed',
  });
}

class CourseModule {
  final int id;
  String title;
  final List<Lesson> lessons;
  bool isExpanded;
  final int order;
  final int courseId;

  CourseModule({
    required this.id,
    required this.title,
    this.lessons = const [],
    this.isExpanded = false,
    this.order = 0,
    this.courseId = 1,
  });
}
