import 'package:edtech/features/courses/data/entities/course_entity.dart';
import 'package:edtech/features/courses/data/entities/module_entity.dart';
import 'package:edtech/features/courses/data/entities/review_entity.dart';

class CourseModel extends CourseEntity {
  const CourseModel({
    required super.id,
    required super.title,
    required super.description,
    required super.shortDescription,
    required super.requirements,
    required super.thumbnailUrl,
    required super.introVideoUrl,
    required super.level,
    required super.type,
    required super.price,
    required super.status,
    required super.language,
    required super.updatedAt,
    required super.mentorName,
    required super.mentorId,
    super.mentorAvatarUrl,
    required super.isStudent,
    required super.totalModules,
    required super.totalLessons,
    required super.totalResources,
    required super.totalDuration,
    super.modules,
    super.reviews,
  });

  factory CourseModel.fromJson(Map<String, dynamic> json) {
    final mentor = json['mentor'] as Map? ?? {};
    final stats = json['stats'] as Map? ?? {};

    final modules = (json['modules'] as List<dynamic>?)
            ?.map((e) => ModuleEntity.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final reviews = (json['courseReviews'] as List<dynamic>?)
            ?.map((r) {
              final user = r['user'] as Map? ?? {};
              return ReviewEntity(
                id: r['id'] as int? ?? 0,
                rating: r['rating'] as int? ?? 0,
                comment: r['comment'] as String? ?? '',
                createdAt: r['createdAt'] as String? ?? '',
                userName: user['name'] as String? ?? '',
                userAvatarUrl: user['avatarUrl'] as String?,
                userId: user['id'] as int?,
              );
            })
            .toList() ??
        [];

    return CourseModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      shortDescription: json['shortDescription'] as String? ?? '',
      requirements: json['requirements'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      introVideoUrl: json['introVideoUrl'] as String? ?? '',
      level: json['level'] as String? ?? '',
      type: json['type'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? '',
      language: json['language'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      mentorName: mentor['name'] as String? ?? '',
      mentorId: mentor['id'] as int? ?? 0,
      mentorAvatarUrl: mentor['avatarUrl'] as String?,
      isStudent: json['isStudent'] as bool? ?? false,
      totalModules: stats['totalModules'] as int? ?? modules.length,
      totalLessons: stats['totalLessons'] as int? ?? 0,
      totalResources: stats['totalResources'] as int? ?? 0,
      totalDuration: stats['totalDuration'] as int? ?? 0,
      modules: modules,
      reviews: reviews,
    );
  }
}
