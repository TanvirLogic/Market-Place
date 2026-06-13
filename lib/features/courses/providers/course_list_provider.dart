import 'package:flutter/material.dart';

class CourseListProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<dynamic> _courses = [];
  List<dynamic> get courses => _courses;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> fetchCourses() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    _courses = [];
    _isLoading = false;
    notifyListeners();
  }
}
