import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/courses/data/models/course_feed_model.dart';
import 'package:flutter/foundation.dart';

class CourseFeedProvider extends ChangeNotifier {
  List<CourseFeedModel> _courses = [];
  List<CourseFeedModel> _enrolledCourses = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  bool _hasNextPage = true;
  int _page = 1;

  List<CourseFeedModel> get courses => _courses;
  List<CourseFeedModel> get enrolledCourses => _enrolledCourses;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasNextPage => _hasNextPage;

  Future<void> fetchFeed({bool isRefresh = false}) async {
    if (isRefresh) _page = 1;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await getNetworkCaller().getRequest(
        url: '${Urls.socialFeedUrl}?page=$_page',
      );

      if (response.isSuccess) {
        final data = response.responseData['data'];
        final courseList = (data['courses'] as List?) ?? [];

        if (isRefresh || _page == 1) {
          _courses = courseList
              .map((e) => CourseFeedModel.fromJson(e as Map<String, dynamic>))
              .toList();
          final enrolledList = (data['enrolledCourses'] as List?) ?? [];
          _enrolledCourses = enrolledList
              .map((e) => CourseFeedModel.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          _courses.addAll(
            courseList
                .map((e) => CourseFeedModel.fromJson(e as Map<String, dynamic>)),
          );
        }

        _hasNextPage = data['hasNextPage'] as bool? ?? false;
      } else {
        _errorMessage = response.errorMessage ?? 'Failed to load courses';
      }
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchMore() async {
    if (_isLoadingMore || !_hasNextPage) return;
    _isLoadingMore = true;
    _page++;
    notifyListeners();

    try {
      final response = await getNetworkCaller().getRequest(
        url: '${Urls.socialFeedUrl}?page=$_page',
      );

      if (response.isSuccess) {
        final data = response.responseData['data'];
        final courseList = (data['courses'] as List?) ?? [];
        _courses.addAll(
          courseList
              .map((e) => CourseFeedModel.fromJson(e as Map<String, dynamic>)),
        );
        _hasNextPage = data['hasNextPage'] as bool? ?? false;
      } else {
        _page--;
      }
    } catch (_) {
      _page--;
    }

    _isLoadingMore = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _page = 1;
    await fetchFeed(isRefresh: true);
  }
}
