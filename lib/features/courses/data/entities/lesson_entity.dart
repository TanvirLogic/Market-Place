class LessonEntity {
  final int id;
  final String title;
  final String duration;
  final bool isResource;
  final String? videoUrl;
  final String? fileUrl;
  final String? fileType;

  const LessonEntity({
    required this.id,
    required this.title,
    required this.duration,
    required this.isResource,
    this.videoUrl,
    this.fileUrl,
    this.fileType,
  });
}
