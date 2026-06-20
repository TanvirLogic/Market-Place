import 'module_entity.dart';
import 'review_entity.dart';

class CourseEntity {
  final int id;
  final String title;
  final String description;
  final String shortDescription;
  final String requirements;
  final String thumbnailUrl;
  final String introVideoUrl;
  final String level;
  final String type;
  final double price;
  final String status;
  final String language;
  final String updatedAt;
  final String mentorName;
  final int mentorId;
  final String? mentorAvatarUrl;
  final bool isStudent;
  final int totalModules;
  final int totalLessons;
  final int totalResources;
  final int totalDuration;
  final List<ModuleEntity> modules;
  final List<ReviewEntity> reviews;

  const CourseEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.shortDescription,
    required this.requirements,
    required this.thumbnailUrl,
    required this.introVideoUrl,
    required this.level,
    required this.type,
    required this.price,
    required this.status,
    required this.language,
    required this.updatedAt,
    required this.mentorName,
    required this.mentorId,
    this.mentorAvatarUrl,
    required this.isStudent,
    required this.totalModules,
    required this.totalLessons,
    required this.totalResources,
    required this.totalDuration,
    this.modules = const [],
    this.reviews = const [],
  });
}
