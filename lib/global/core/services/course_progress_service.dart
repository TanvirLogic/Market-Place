import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CourseProgressService {
  CourseProgressService._();

  static const _storage = FlutterSecureStorage();
  static const _prefix = 'course_done_';

  static Future<void> markLessonCompleted(
    int courseId,
    int lessonId,
  ) async {
    final key = '$_prefix$courseId';
    final existing = await _storage.read(key: key);
    final set = <int>{};
    if (existing != null && existing.isNotEmpty) {
      final list = (jsonDecode(existing) as List).cast<num>();
      set.addAll(list.map((e) => e.toInt()));
    }
    set.add(lessonId);
    await _storage.write(key: key, value: jsonEncode(set.toList()));
  }

  static Future<Set<int>> getCompletedLessonIds(int courseId) async {
    final key = '$_prefix$courseId';
    final existing = await _storage.read(key: key);
    if (existing == null || existing.isEmpty) return {};
    final list = (jsonDecode(existing) as List).cast<num>();
    return list.map((e) => e.toInt()).toSet();
  }

  static Future<double> getProgress(
    int courseId,
    int totalVideoLessons,
  ) async {
    if (totalVideoLessons <= 0) return 0;
    final completed = await getCompletedLessonIds(courseId);
    return completed.length / totalVideoLessons;
  }
}
