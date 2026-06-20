import 'lesson_entity.dart';

class ModuleEntity {
  final int id;
  final String title;
  final int order;
  final List<LessonEntity> lessons;

  const ModuleEntity({
    required this.id,
    required this.title,
    required this.order,
    this.lessons = const [],
  });

  factory ModuleEntity.fromJson(Map<String, dynamic> json) {
    final videoLessons = (json['lessons'] as List<dynamic>?)
            ?.map((l) {
              final video = l['video'] as Map?;
              final duration = video?['duration'] as int? ?? l['duration'] as int?;
              final vidUrl = video?['videoUrl'] as String?
                  ?? video?['url'] as String?
                  ?? video?['fileUrl'] as String?
                  ?? l['videoUrl'] as String?
                  ?? l['fileUrl'] as String?
                  ?? l['url'] as String?;
              return LessonEntity(
                id: l['id'] as int? ?? 0,
                title: l['title'] as String? ?? '',
                duration: duration != null ? _fmt(duration) : '0:00',
                isResource: false,
                videoUrl: vidUrl,
              );
            })
            .toList() ??
        [];

    final resources = (json['resources'] as List<dynamic>?)
            ?.map((r) => LessonEntity(
                  id: r['id'] as int? ?? 0,
                  title: r['title'] as String? ?? '',
                  duration: '',
                  isResource: true,
                  fileUrl: r['fileUrl'] as String?,
                  fileType: r['fileType'] as String?,
                ))
            .toList() ??
        [];

    return ModuleEntity(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      lessons: [...videoLessons, ...resources],
    );
  }

  static String _fmt(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
