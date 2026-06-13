import 'package:flutter/material.dart';
import 'package:edtech/features/courses/data/models/course_model.dart';
import 'package:edtech/features/courses/data/entities/module_entity.dart';
import 'package:edtech/features/courses/data/entities/lesson_entity.dart';
import 'package:edtech/features/courses/data/entities/review_entity.dart';

class CourseDetailProvider extends ChangeNotifier {
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
      id: courseId,
      title: 'Complete Web Development Bootcamp 2025',
      description: 'Master modern web development with this comprehensive bootcamp. Learn HTML, CSS, JavaScript, React, Node.js, and MongoDB.',
      instructorName: 'John Doe',
      instructorTitle: 'Senior Developer & Instructor',
      level: 'BEGINNER',
      language: 'English',
      price: 499,
      rating: 4.8,
      videosCount: 156,
      resourcesCount: 23,
      thumbnailUrl: '',
      modules: [
        ModuleEntity(
          title: 'Introduction to Web Development',
          lessonsCount: '3 Lessons',
          lessons: [
            LessonEntity(title: 'Welcome to the Course', duration: '10:00', isLocked: false),
            LessonEntity(title: 'How the Internet Works', duration: '15:00', isLocked: false),
            LessonEntity(title: 'Setting Up Your Environment', duration: '12:00', isLocked: true),
          ],
        ),
        ModuleEntity(
          title: 'HTML & CSS Fundamentals',
          lessonsCount: '2 Lessons',
          lessons: [
            LessonEntity(title: 'HTML Document Structure', duration: '20:00', isLocked: true),
            LessonEntity(title: 'CSS Selectors & Properties', duration: '25:00', isLocked: true),
          ],
        ),
        ModuleEntity(
          title: 'JavaScript Basics',
          lessonsCount: '2 Lessons',
          lessons: [
            LessonEntity(title: 'Variables & Data Types', duration: '18:00', isLocked: true),
            LessonEntity(title: 'Functions & Scope', duration: '22:00', isLocked: true),
          ],
        ),
      ],
      reviews: [
        ReviewEntity(name: 'Alice Johnson', timeAgo: '2 days ago', rating: 5, comment: 'Amazing course! Very well structured and easy to follow.', imageUrl: ''),
        ReviewEntity(name: 'Bob Smith', timeAgo: '1 week ago', rating: 4, comment: 'Great content but could use more exercises in later sections.', imageUrl: ''),
        ReviewEntity(name: 'Carol Williams', timeAgo: '2 weeks ago', rating: 5, comment: 'The instructor explains everything clearly. Highly recommended!', imageUrl: ''),
      ],
    );

    _isLoading = false;
    notifyListeners();
  }
}
