import 'package:flutter/material.dart';
import 'package:edtech/features/courses/data/models/course_model.dart';
import 'package:edtech/features/courses/data/entities/module_entity.dart';
import 'package:edtech/features/courses/data/entities/lesson_entity.dart';
import 'package:edtech/features/courses/data/entities/review_entity.dart';

class EnrolledCourseProvider extends ChangeNotifier {
  CourseModel? _course;
  bool _isLoading = false;
  String? _errorMessage;

  CourseModel? get course => _course;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadCourse(String courseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    _course = CourseModel(
      id: 0,
      title: 'Complete Web Development Bootcamp 2025',
      description: 'Master modern web development.',
      shortDescription: '',
      requirements: '',
      thumbnailUrl: '',
      introVideoUrl: '',
      level: 'BEGINNER',
      type: 'PAID',
      price: 499,
      status: 'PUBLISHED',
      language: 'English',
      updatedAt: '',
      mentorName: 'John Doe',
      mentorId: 1,
      isStudent: true,
      totalModules: 2,
      totalLessons: 3,
      totalResources: 0,
      totalDuration: 47,
      modules: [
        ModuleEntity(
          id: 1,
          title: 'Introduction to Web Development',
          order: 0,
          lessons: [
            LessonEntity(id: 1, title: 'Welcome to the Course', duration: '10:00', isResource: false),
            LessonEntity(id: 2, title: 'How the Internet Works', duration: '15:00', isResource: false),
            LessonEntity(id: 3, title: 'Setting Up Your Environment', duration: '12:00', isResource: false),
          ],
        ),
        ModuleEntity(
          id: 2,
          title: 'HTML & CSS Fundamentals',
          order: 1,
          lessons: [
            LessonEntity(id: 4, title: 'HTML Document Structure', duration: '20:00', isResource: false),
            LessonEntity(id: 5, title: 'CSS Selectors & Properties', duration: '25:00', isResource: false),
          ],
        ),
      ],
      reviews: [
        ReviewEntity(id: 1, rating: 5, comment: 'Amazing course!', createdAt: '', userName: 'Alice Johnson'),
        ReviewEntity(id: 2, rating: 4, comment: 'Great content!', createdAt: '', userName: 'Bob Smith'),
      ],
    );

    _isLoading = false;
    notifyListeners();
  }
}
