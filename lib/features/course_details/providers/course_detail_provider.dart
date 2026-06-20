import 'package:flutter/material.dart';
import 'package:edtech/features/course_details/data/models/course_model.dart';
import 'package:edtech/features/course_details/data/entities/review_entity.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/app/setup_network_caller.dart';

class CourseDetailProvider extends ChangeNotifier {
  CourseModel? _course;
  bool _isLoading = false;
  String? _errorMessage;
  String? _reviewError;

  CourseModel? get course => _course;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get reviewError => _reviewError;

  Future<void> loadCourse(int courseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final response = await getNetworkCaller().getRequest(
      url: '${Urls.updateCourseUrl}?courseID=$courseId',
    );

    if (response.isSuccess) {
      final data = response.responseData['data'];
      if (data is Map<String, dynamic>) {
        _course = CourseModel.fromJson(data);
      }
    } else {
      _errorMessage = response.errorMessage ?? 'Failed to load course';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> submitReview({
    required int courseId,
    required int rating,
    required String comment,
  }) async {
    _reviewError = null;
    notifyListeners();

    final response = await getNetworkCaller().postRequest(
      url: Urls.courseReviewUrl,
      body: {
        'courseId': courseId,
        'rating': rating,
        'comment': comment,
      },
    );

    if (response.isSuccess) {
      final newReviewData = response.responseData['data'];
      if (newReviewData is Map<String, dynamic> && _course != null) {
        final user = newReviewData['user'] as Map<String, dynamic>?;
        final newReview = ReviewEntity(
          id: newReviewData['id'] ?? 0,
          rating: newReviewData['rating'] ?? rating,
          comment: newReviewData['comment'] ?? comment,
          createdAt: newReviewData['createdAt'] ?? DateTime.now().toIso8601String(),
          userName: user?['name'] ?? '',
          userAvatarUrl: user?['avatarUrl'] as String?,
        );
        final updatedReviews = [newReview, ..._course!.reviews];
        _course = CourseModel(
          id: _course!.id,
          title: _course!.title,
          description: _course!.description,
          shortDescription: _course!.shortDescription,
          requirements: _course!.requirements,
          thumbnailUrl: _course!.thumbnailUrl,
          introVideoUrl: _course!.introVideoUrl,
          level: _course!.level,
          type: _course!.type,
          price: _course!.price,
          status: _course!.status,
          language: _course!.language,
          updatedAt: _course!.updatedAt,
          mentorName: _course!.mentorName,
          mentorId: _course!.mentorId,
          mentorAvatarUrl: _course!.mentorAvatarUrl,
          isStudent: _course!.isStudent,
          totalModules: _course!.totalModules,
          totalLessons: _course!.totalLessons,
          totalResources: _course!.totalResources,
          totalDuration: _course!.totalDuration,
          modules: _course!.modules,
          reviews: updatedReviews,
        );
        notifyListeners();
      }
      return newReviewData as Map<String, dynamic>?;
    }

    final errors = response.responseData['errors'];
    if (errors is Map<String, dynamic>) {
      final reviewErrors = errors['review'];
      if (reviewErrors is List && reviewErrors.isNotEmpty) {
        _reviewError = reviewErrors[0].toString();
        notifyListeners();
        return {'_error': _reviewError};
      }
    }

    _reviewError = response.errorMessage ?? 'Failed to submit review';
    notifyListeners();
    return {'_error': _reviewError};
  }

  Future<Map<String, dynamic>?> updateReview({
    required int reviewId,
    required String comment,
  }) async {
    final response = await getNetworkCaller().putRequest(
      url: Urls.courseReviewUrl,
      body: {
        'reviewId': reviewId,
        'comment': comment,
      },
    );

    if (response.isSuccess && _course != null) {
      final updatedData = response.responseData['data'];
      if (updatedData is Map<String, dynamic>) {
        final updatedReviews = _course!.reviews.map((r) {
          if (r.id == reviewId) {
            return ReviewEntity(
              id: r.id,
              rating: updatedData['rating'] as int? ?? r.rating,
              comment: updatedData['comment'] as String? ?? comment,
              createdAt: r.createdAt,
              userName: r.userName,
              userAvatarUrl: r.userAvatarUrl,
              userId: r.userId,
            );
          }
          return r;
        }).toList();
        _course = CourseModel(
          id: _course!.id,
          title: _course!.title,
          description: _course!.description,
          shortDescription: _course!.shortDescription,
          requirements: _course!.requirements,
          thumbnailUrl: _course!.thumbnailUrl,
          introVideoUrl: _course!.introVideoUrl,
          level: _course!.level,
          type: _course!.type,
          price: _course!.price,
          status: _course!.status,
          language: _course!.language,
          updatedAt: _course!.updatedAt,
          mentorName: _course!.mentorName,
          mentorId: _course!.mentorId,
          mentorAvatarUrl: _course!.mentorAvatarUrl,
          isStudent: _course!.isStudent,
          totalModules: _course!.totalModules,
          totalLessons: _course!.totalLessons,
          totalResources: _course!.totalResources,
          totalDuration: _course!.totalDuration,
          modules: _course!.modules,
          reviews: updatedReviews,
        );
        notifyListeners();
      }
      return response.responseData['data'] as Map<String, dynamic>?;
    }

    return {'_error': response.errorMessage ?? 'Failed to update review'};
  }

  Future<Map<String, dynamic>?> deleteReview(int reviewId) async {
    final response = await getNetworkCaller().deleteRequest(
      url: Urls.courseReviewUrl,
      body: {'reviewId': reviewId},
    );

    if (response.isSuccess && _course != null) {
      final updatedReviews = _course!.reviews.where((r) => r.id != reviewId).toList();
      _course = CourseModel(
        id: _course!.id,
        title: _course!.title,
        description: _course!.description,
        shortDescription: _course!.shortDescription,
        requirements: _course!.requirements,
        thumbnailUrl: _course!.thumbnailUrl,
        introVideoUrl: _course!.introVideoUrl,
        level: _course!.level,
        type: _course!.type,
        price: _course!.price,
        status: _course!.status,
        language: _course!.language,
        updatedAt: _course!.updatedAt,
        mentorName: _course!.mentorName,
        mentorId: _course!.mentorId,
        mentorAvatarUrl: _course!.mentorAvatarUrl,
        isStudent: _course!.isStudent,
        totalModules: _course!.totalModules,
        totalLessons: _course!.totalLessons,
        totalResources: _course!.totalResources,
        totalDuration: _course!.totalDuration,
        modules: _course!.modules,
        reviews: updatedReviews,
      );
      notifyListeners();
      return {};
    }

    return {'_error': response.errorMessage ?? 'Failed to delete review'};
  }
}
