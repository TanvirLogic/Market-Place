class DashboardStats {
  final int totalCourses;
  final int totalEnrollments;
  final int totalLessons;
  final int totalResources;
  final int totalReviews;
  final double? avgRating;

  const DashboardStats({
    required this.totalCourses,
    required this.totalEnrollments,
    required this.totalLessons,
    required this.totalResources,
    required this.totalReviews,
    this.avgRating,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalCourses: json['totalCourses'] as int? ?? 0,
      totalEnrollments: json['totalEnrollments'] as int? ?? 0,
      totalLessons: json['totalLessons'] as int? ?? 0,
      totalResources: json['totalResources'] as int? ?? 0,
      totalReviews: json['totalReviews'] as int? ?? 0,
      avgRating: (json['avgRating'] as num?)?.toDouble(),
    );
  }
}

class DashboardCourse {
  final int id;
  final String title;
  final String status;
  final double price;
  final String type;
  final String updatedAt;
  final int totalEnrollments;

  const DashboardCourse({
    required this.id,
    required this.title,
    required this.status,
    required this.price,
    required this.type,
    required this.updatedAt,
    required this.totalEnrollments,
  });

  factory DashboardCourse.fromJson(Map<String, dynamic> json) {
    return DashboardCourse(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      type: json['type'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      totalEnrollments: json['totalEnrollments'] as int? ?? 0,
    );
  }
}

class DashboardEntity {
  final DashboardStats stats;
  final List<DashboardCourse> courses;

  const DashboardEntity({
    required this.stats,
    required this.courses,
  });

  factory DashboardEntity.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return DashboardEntity(
      stats: DashboardStats.fromJson(data['stats'] as Map<String, dynamic>? ?? {}),
      courses: (data['courses'] as List<dynamic>?)
              ?.map((e) => DashboardCourse.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}