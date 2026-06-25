import 'dart:async';

import 'package:edtech/features/courses/data/models/upload_task.dart';
import 'package:edtech/features/courses/data/repositories/upload_queue_repository.dart';
import 'package:edtech/features/courses/providers/unified_upload_queue_provider.dart';
import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:edtech/app/urls.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/native_upload_bridge.dart';
import 'package:edtech/global/core/services/toast_service.dart';

class ManageModuleProvider extends ChangeNotifier {
  final int courseId;
  int _nextModuleId = 1;
  int _nextLessonId = 1;
  bool _isLoading = true;

  final List<CourseModule> _modules = [];
  final Map<int, String> _videoUrlCache = {};
  final Map<int, int> _queueItemToLesson = {};
  final Map<int, String> _pendingFileUrls = {};
  Timer? _progressTimer;
  bool _hasUnsavedChanges = false;

  String _courseTitle = '';
  String _courseShortDescription = '';
  String _courseDescription = '';
  String _courseRequirements = '';
  String _courseLanguage = '';
  String _courseLevel = '';
  String _courseType = '';
  String _courseStatus = '';
  double _coursePrice = 0;
  String? _courseThumbnailUrl;
  String? _courseIntroVideoUrl;

  ManageModuleProvider({this.courseId = 0}) {
    _fetchCourse();
  }

  List<CourseModule> get modules => _modules;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool get isLoading => _isLoading;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  String get courseTitle => _courseTitle;
  String get courseShortDescription => _courseShortDescription;
  String get courseDescription => _courseDescription;
  String get courseRequirements => _courseRequirements;
  String get courseLanguage => _courseLanguage;
  String get courseLevel => _courseLevel;
  String get courseType => _courseType;
  String get courseStatus => _courseStatus;
  double get coursePrice => _coursePrice;
  String? get courseThumbnailUrl => _courseThumbnailUrl;
  String? get courseIntroVideoUrl => _courseIntroVideoUrl;

  int get nextModuleId => _nextModuleId;
  int get nextLessonId => _nextLessonId;

  void incrementModuleId() => _nextModuleId++;
  void incrementLessonId() => _nextLessonId++;

  Future<void> refresh() => _fetchCourse();

  Future<void> _fetchCourse() async {
    _isLoading = true;
    notifyListeners();
    final response = await getNetworkCaller().getRequest(
      url: '${Urls.updateCourseUrl}?courseID=$courseId',
    );
    if (response.isSuccess) {
      final data = response.responseData['data'];
      if (data is Map) {
        _courseTitle = data['title'] as String? ?? '';
        _courseShortDescription = data['shortDescription'] as String? ?? '';
        _courseDescription = data['description'] as String? ?? '';
        _courseRequirements = data['requirements'] as String? ?? '';
        _courseLanguage = data['language'] as String? ?? '';
        _courseLevel = data['level'] as String? ?? '';
        _courseType = data['type'] as String? ?? '';
        _courseStatus = data['status'] as String? ?? '';
        _coursePrice = (data['price'] as num?)?.toDouble() ?? 0;
        _courseThumbnailUrl = data['thumbnailUrl'] as String?;
        _courseIntroVideoUrl = data['introVideoUrl'] as String?;

        final modulesList = data['modules'] as List? ?? [];
        _modules.clear();
        for (final item in modulesList) {
          final lessons = (item['lessons'] as List?)?.map((l) {
            final lessonId = l['id'] as int? ?? _nextLessonId++;
            final video = l['video'] as Map?;
            final duration = video?['duration'] as int? ?? l['duration'] as int?;
            final videoUrl = l['videoUrl'] as String?
                ?? video?['videoUrl'] as String?
                ?? video?['url'] as String?
                ?? video?['fileUrl'] as String?
                ?? l['fileUrl'] as String?
                ?? l['url'] as String?
                ?? _videoUrlCache[lessonId];
            if (videoUrl != null) _videoUrlCache[lessonId] = videoUrl;
            return Lesson(
              id: lessonId,
              title: l['title'] as String? ?? '',
              duration: duration != null ? _formatDuration(duration) : '0:00',
              type: LessonType.video,
              videoUrl: videoUrl,
            );
          }).toList() ?? [];
          final resources = (item['resources'] as List?)?.map((r) {
            return Lesson(
              id: r['id'] as int? ?? _nextLessonId++,
              title: r['title'] as String? ?? '',
              duration: '',
              type: LessonType.resource,
              fileUrl: r['fileUrl'] as String?,
              fileType: r['fileType'] as String?,
            );
          }).toList() ?? [];
          _modules.add(
            CourseModule(
              id: item['id'] as int? ?? _nextModuleId++,
              title: item['title'] as String? ?? '',
              order: item['order'] as int? ?? _modules.length,
              courseId: courseId,
              lessons: [...lessons, ...resources],
              isExpanded: false,
            ),
          );
        }
      }
    }
    _isLoading = false;
    notifyListeners();
    _restorePendingUploads();
  }

  Future<void> _restorePendingUploads() async {
    try {
      final allItems = await UploadQueueRepository.getActive();
      final lessonItems = allItems.where((i) => i.uploadType == 'module_lesson' || i.uploadType == 'resource').toList();
      if (lessonItems.isEmpty) return;

      final nativeData = await NativeUploadBridge.getQueueItems();
      final nativeItems =
          (nativeData['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
              [];

      bool hasUpdates = false;

      for (final item in lessonItems) {
        final meta = item.parseMetadata(ModuleLessonMetadata.fromJson);
        if (meta == null) {
          AppLogger.w('_restorePendingUploads: could not parse metadata for item ${item.id}');
          continue;
        }
        if (meta.courseId != courseId) continue;

        final moduleIndex = _modules.indexWhere((m) => m.id == meta.moduleId);
        if (moduleIndex < 0) {
          AppLogger.w('_restorePendingUploads: module ${meta.moduleId} not found for item ${item.id}');
          continue;
        }

        final module = _modules[moduleIndex];
        final alreadyExists = module.lessons.any(
          (l) => l.title == meta.lessonTitle,
        );
        if (alreadyExists) continue;

        // Match native item by ID first, then by filePath as fallback
        // (after recovery, IDs may have been regenerated differently)
        Map<String, dynamic>? nativeItem;
        for (final n in nativeItems) {
          if (n['id'] == item.id) {
            nativeItem = n;
            break;
          }
        }
        if (nativeItem == null) {
          for (final n in nativeItems) {
            if (n['filePath'] == item.filePath) {
              nativeItem = n;
              break;
            }
          }
        }

        final progress =
            ((nativeItem?['progress'] as num?)?.toDouble() ?? 0.0) / 100.0;
        final status = nativeItem?['status'] as String? ?? item.status;
        final fileUrl = nativeItem?['fileUrl'] as String? ?? item.fileUrl;

        final isResource = item.uploadType == 'resource';
        AppLogger.i('_restorePendingUploads: restoring ${isResource ? "resource" : "lesson"} "${meta.lessonTitle}" — status=$status, progress=$progress');

        final lessonId = _nextLessonId++;
        final lesson = Lesson(
          id: lessonId,
          title: meta.lessonTitle,
          duration: '0:00',
          type: isResource ? LessonType.resource : LessonType.video,
          uploadProgress: progress,
          uploadStatus: status,
          videoUrl: isResource ? null : fileUrl,
          fileUrl: isResource ? fileUrl : null,
        );

        module.lessons.add(lesson);
        _queueItemToLesson[item.id!] = lessonId;
        hasUpdates = true;
      }

      if (hasUpdates) {
        _startProgressPolling();
        notifyListeners();
      }
    } catch (e) {
      AppLogger.e('_restorePendingUploads error: $e');
    }
  }

  List<Map<String, dynamic>> getSerializedOrder() {
    return _modules.asMap().entries.map((entry) {
      final module = entry.value;
      return {
        'module_id': module.id,
        'sort_order': entry.key,
        'title': module.title,
        'lessons': module.lessons.asMap().entries.map((le) {
          return {
            'lesson_id': le.value.id,
            'sort_order': le.key,
            'title': le.value.title,
            'type': le.value.type.name,
          };
        }).toList(),
      };
    }).toList();
  }

  void saveOrder() {
    final serialized = getSerializedOrder();
    debugPrint('Saving order: $serialized');
    _hasUnsavedChanges = false;
    notifyListeners();
    ToastService.showInfo("Module Managed Succesfully");
  }

  void addLessonToModule(
    int moduleIndex,
    LessonType type, {
    String? customTitle,
  }) {
    _modules[moduleIndex].lessons.add(
      Lesson(
        id: _nextLessonId++,
        title:
            customTitle ??
            (type == LessonType.video
                ? "Setting Up Your Environment"
                : "HTML Fundamentals"),
        duration: "18:20",
        type: type,
      ),
    );
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void reorderModule(int oldIndex, int newIndex) {
    final module = _modules.removeAt(oldIndex);
    _modules.insert(newIndex, module);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void toggleExpand(CourseModule module) {
    for (final m in _modules) {
      if (m != module) m.isExpanded = false;
    }
    module.isExpanded = !module.isExpanded;
    notifyListeners();
  }

  void renameModule(CourseModule module, String newName) {
    module.title = newName;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void reorderLesson(
    CourseModule module,
    int oldLessonIndex,
    int newLessonIndex,
  ) {
    if (newLessonIndex > oldLessonIndex) newLessonIndex--;
    final lesson = module.lessons.removeAt(oldLessonIndex);
    module.lessons.insert(newLessonIndex, lesson);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  Future<bool> addModule(String title) async {
    final nextOrder = _modules.isEmpty
        ? 0
        : _modules.map((m) => m.order).reduce((a, b) => a > b ? a : b) + 1;
    final response = await getNetworkCaller().postRequest(
      url: Urls.courseModuleUrl,
      body: {'title': title, 'order': nextOrder, 'courseID': courseId},
    );
    if (response.isSuccess) {
      final data = response.responseData['data'];
      final moduleId = data['id'] as int? ?? _nextModuleId++;
      final serverCourseId = data['courseId'] as int? ?? courseId;
      _modules.add(
        CourseModule(
          id: moduleId,
          title: title,
          order: nextOrder,
          courseId: serverCourseId,
          lessons: [],
          isExpanded: true,
        ),
      );
      notifyListeners();
      ToastService.showSuccess('Module added successfully');
      return true;
    } else {
      ToastService.showError(response.errorMessage ?? 'Failed to add module');
      return false;
    }
  }

  Future<bool> deleteModule(CourseModule module) async {
    final response = await getNetworkCaller().deleteRequest(
      url: Urls.courseModuleUrl,
      body: {'moduleID': module.id},
    );
    if (response.isSuccess) {
      _modules.removeWhere((m) => m.id == module.id);
      notifyListeners();
      ToastService.showSuccess('Module deleted successfully');
      return true;
    } else {
      ToastService.showError(
        response.errorMessage ?? 'Failed to delete module',
      );
      return false;
    }
  }

  Future<bool> editModule(CourseModule module, String title) async {
    final response = await getNetworkCaller().putRequest(
      url: Urls.courseModuleUrl,
      body: {'moduleID': module.id, 'title': title},
    );
    if (response.isSuccess) {
      module.title = title;
      notifyListeners();
      ToastService.showSuccess('Module updated successfully');
      return true;
    } else {
      ToastService.showError(
        response.errorMessage ?? 'Failed to update module',
      );
      return false;
    }
  }

  Future<bool> updateCourse(Map<String, dynamic> body) async {
    final response = await getNetworkCaller().putRequest(
      url: Urls.updateCourseUrl,
      body: body,
    );
    if (response.isSuccess) {
      await refresh();
      ToastService.showSuccess('Course updated successfully');
      return true;
    } else {
      ToastService.showError(
        response.errorMessage ?? 'Failed to update course',
      );
      return false;
    }
  }

  Future<bool> renameLesson(
    CourseModule module,
    int lessonIndex,
    String newName,
  ) async {
    final lesson = module.lessons[lessonIndex];
    final isResource = lesson.type == LessonType.resource;
    final response = await getNetworkCaller().putRequest(
      url: isResource ? Urls.courseModuleResourceUrl : Urls.courseModuleLessonUrl,
      body: isResource
          ? {'resourceId': lesson.id, 'title': newName}
          : {'lessonId': lesson.id, 'title': newName},
    );
    if (response.isSuccess) {
      module.lessons[lessonIndex].title = newName;
      notifyListeners();
      ToastService.showSuccess(isResource ? 'Resource updated successfully' : 'Lesson renamed successfully');
      return true;
    } else {
      ToastService.showError(
        response.errorMessage ?? 'Failed to rename',
      );
      return false;
    }
  }

  Future<bool> deleteLesson(CourseModule module, int lessonIndex) async {
    final lesson = module.lessons[lessonIndex];
    final isResource = lesson.type == LessonType.resource;
    final response = await getNetworkCaller().deleteRequest(
      url: isResource ? Urls.courseModuleResourceUrl : Urls.courseModuleLessonUrl,
      body: isResource ? {'resourceId': lesson.id} : {'lessonId': lesson.id},
    );
    if (response.isSuccess) {
      module.lessons.removeAt(lessonIndex);
      notifyListeners();
      ToastService.showSuccess(isResource ? 'Resource deleted successfully' : 'Lesson deleted successfully');
      return true;
    } else {
      ToastService.showError(
        response.errorMessage ?? 'Failed to delete',
      );
      return false;
    }
  }

  Future<bool> addVideoLesson(
    int moduleIndex,
    String title,
    XFile videoFile, {
    UnifiedUploadQueueProvider? queueProvider,
  }) async {
    final module = _modules[moduleIndex];
    final lessonId = _nextLessonId++;

    final lesson = Lesson(
      id: lessonId,
      title: title,
      duration: '0:00',
      type: LessonType.video,
      uploadProgress: 0.0,
      uploadStatus: 'pending',
    );
    module.lessons.add(lesson);
    _hasUnsavedChanges = true;
    notifyListeners();

    try {
      final queueId = await queueProvider!.addModuleLessonToQueue(
        videoPath: videoFile.path,
        lessonTitle: title,
        moduleId: module.id,
        courseId: courseId,
      );
      if (queueId <= 0) {
        lesson.uploadStatus = 'failed';
        notifyListeners();
        return false;
      }
      _queueItemToLesson[queueId] = lessonId;
      _startProgressPolling();
      return true;
    } catch (e) {
      AppLogger.e('addVideoLesson queue error: $e');
      lesson.uploadStatus = 'failed';
      notifyListeners();
      ToastService.showError('Failed to queue video lesson');
      return false;
    }
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    int emptyNativeReads = 0;

    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final data = await NativeUploadBridge.getQueueItems();
        final items = data['items'] as List<dynamic>? ?? [];
        bool updated = false;

        // If native state is empty but we still have queued lessons,
        // the native service completed and deleted the state file.
        // Mark all queued lessons as completed using cached fileUrls.
        if (items.isEmpty && _queueItemToLesson.isNotEmpty) {
          emptyNativeReads++;
          // Wait 2 cycles (4 seconds) to confirm native is truly gone
          // before marking as completed (avoids false positive on slow reads)
          if (emptyNativeReads >= 2) {
            for (final entry in _queueItemToLesson.entries) {
              final lesson = _findLessonById(entry.value);
              if (lesson != null && lesson.uploadStatus != 'completed') {
                lesson.uploadStatus = 'completed';
                final cachedUrl = _pendingFileUrls.remove(entry.key);
                if (cachedUrl != null && cachedUrl.isNotEmpty) {
                  _setLessonUrl(lesson, cachedUrl);
                }
                updated = true;
              }
            }
            _queueItemToLesson.clear();
            _pendingFileUrls.clear();
          }
        } else if (items.isNotEmpty) {
          emptyNativeReads = 0;

          for (final raw in items) {
            final item = raw as Map<String, dynamic>;
            final queueId = item['id'] as int;
            final lessonId = _queueItemToLesson[queueId];
            if (lessonId == null) continue;

            final lesson = _findLessonById(lessonId);
            if (lesson == null) {
              _queueItemToLesson.remove(queueId);
              _pendingFileUrls.remove(queueId);
              continue;
            }

            final status = item['status'] as String? ?? 'pending';
            final progress =
                ((item['progress'] as num?)?.toDouble() ?? 0.0) / 100.0;

            if (lesson.uploadStatus != status ||
                lesson.uploadProgress != progress) {
              lesson.uploadStatus = status;
              lesson.uploadProgress = progress;
              updated = true;
            }

            // Cache fileUrl while native state is still available
            final fileUrl = item['fileUrl'] as String?;
            if (fileUrl != null && fileUrl.isNotEmpty) {
              _pendingFileUrls[queueId] = fileUrl;
            }

            if (status == 'completed') {
              if (fileUrl != null && fileUrl.isNotEmpty) {
                _setLessonUrl(lesson, fileUrl);
              } else {
                final cachedUrl = _pendingFileUrls.remove(queueId);
                if (cachedUrl != null && cachedUrl.isNotEmpty) {
                  _setLessonUrl(lesson, cachedUrl);
                }
              }
              _queueItemToLesson.remove(queueId);
              _pendingFileUrls.remove(queueId);
            } else if (status == 'failed') {
              _queueItemToLesson.remove(queueId);
              _pendingFileUrls.remove(queueId);
            }
          }
        }

        if (updated) notifyListeners();

        if (_queueItemToLesson.isEmpty) {
          _progressTimer?.cancel();
          _progressTimer = null;
        }
      } catch (e) {
        AppLogger.e('_startProgressPolling error: $e');
      }
    });
  }

  Lesson? _findLessonById(int lessonId) {
    for (final module in _modules) {
      for (final lesson in module.lessons) {
        if (lesson.id == lessonId) return lesson;
      }
    }
    return null;
  }

  void _setLessonUrl(Lesson lesson, String url) {
    if (lesson.type == LessonType.resource) {
      lesson.fileUrl ??= url;
    } else {
      lesson.videoUrl ??= url;
    }
  }

  Future<bool> addResourceLesson(
    int moduleIndex,
    String title,
    XFile resourceFile, {
    UnifiedUploadQueueProvider? queueProvider,
  }) async {
    final module = _modules[moduleIndex];
    final lessonId = _nextLessonId++;

    final lesson = Lesson(
      id: lessonId,
      title: title,
      duration: '0:00',
      type: LessonType.resource,
      uploadProgress: 0.0,
      uploadStatus: 'pending',
    );
    module.lessons.add(lesson);
    _hasUnsavedChanges = true;
    notifyListeners();

    try {
      final contentType = _inferResourceContentType(resourceFile.name);
      final queueId = await queueProvider!.addResourceToQueue(
        filePath: resourceFile.path,
        lessonTitle: title,
        moduleId: module.id,
        courseId: courseId,
        contentType: contentType,
      );
      if (queueId <= 0) {
        lesson.uploadStatus = 'failed';
        notifyListeners();
        ToastService.showError('Failed to queue resource');
        return false;
      }
      _queueItemToLesson[queueId] = lessonId;
      _startProgressPolling();
      return true;
    } catch (e) {
      AppLogger.e('addResourceLesson queue error: $e');
      lesson.uploadStatus = 'failed';
      notifyListeners();
      ToastService.showError('Failed to queue resource lesson');
      return false;
    }
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _inferResourceContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default: return 'application/octet-stream';
    }
  }

}
