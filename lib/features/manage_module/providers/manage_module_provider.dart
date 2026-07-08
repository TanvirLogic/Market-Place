import 'dart:async';

import 'package:edtech/features/uploads/presentation/upload_queue_provider.dart';
import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:edtech/app/urls.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';

class ManageModuleProvider extends ChangeNotifier {
  final int courseId;
  final UploadQueueProvider _queueProvider;
  int _nextModuleId = 1;
  int _nextLessonId = 1;
  bool _isLoading = true;

  final List<CourseModule> _modules = [];
  final Map<int, String> _videoUrlCache = {};
  final Map<int, PendingLesson> _pendingLessons = {};
  Timer? _progressTimer;
  bool _hasUnsavedChanges = false;
  bool _isRestoringPending = false;
  bool _isRefreshing = false;
  bool _isQueuing = false;
  bool _polling = false;
  bool _disposed = false;
  final Set<int> _notifiedCompletions = {};

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

  ManageModuleProvider({
    this.courseId = 0,
    required UploadQueueProvider queueProvider,
  }) : _queueProvider = queueProvider {
    _fetchCourse();
    _queueProvider.addListener(_onQueueChanged);
  }

  List<CourseModule> get modules => _modules;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool get isLoading => _isLoading;

  Map<int, PendingLesson> get pendingLessons => _pendingLessons;

  List<PendingLesson> pendingLessonsForModule(int moduleId) {
    return _pendingLessons.values.where((p) => p.moduleId == moduleId).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _queueProvider.removeListener(_onQueueChanged);
    _progressTimer?.cancel();
    _progressTimer = null;
    super.dispose();
  }

  void _onQueueChanged() {
    if (_modules.isNotEmpty && !_isRestoringPending && !_isLoading) {
      _restorePendingUploads();
    }
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

  Future<void> refresh() => _fetchCourse(silent: _pendingLessons.isNotEmpty);

  Future<void> _silentRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await _fetchCourse(silent: true);
    } finally {
      _isRefreshing = false;
    }
    // Restore any pending items that are still in the DB after a silent
    // refresh so they don't disappear from the UI.
    await _restorePendingUploads();
  }

  Future<void> _fetchCourse({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    final response = await getNetworkCaller().getRequest(
      // TODO : Use the actual courseId instead of hardcoding 2
      url: '${Urls.updateCourseUrl}?courseID=$courseId',
      // url: '${Urls.updateCourseUrl}?courseID=2',
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
          final lessons =
              (item['lessons'] as List?)?.map((l) {
                final lessonId = l['id'] as int? ?? _nextLessonId++;
                final video = l['video'] as Map?;
                final duration =
                    video?['duration'] as int? ?? l['duration'] as int?;
                final videoUrl =
                    l['videoUrl'] as String? ??
                    video?['videoUrl'] as String? ??
                    video?['url'] as String? ??
                    video?['fileUrl'] as String? ??
                    l['fileUrl'] as String? ??
                    l['url'] as String? ??
                    _videoUrlCache[lessonId];
                if (videoUrl != null) _videoUrlCache[lessonId] = videoUrl;
                return Lesson(
                  id: lessonId,
                  title: l['title'] as String? ?? '',
                  duration: duration != null
                      ? _formatDuration(duration)
                      : '0:00',
                  type: LessonType.video,
                  videoUrl: videoUrl,
                );
              }).toList() ??
              [];
          final resources =
              (item['resources'] as List?)?.map((r) {
                return Lesson(
                  id: r['id'] as int? ?? _nextLessonId++,
                  title: r['title'] as String? ?? '',
                  duration: '',
                  type: LessonType.resource,
                  fileUrl: r['fileUrl'] as String?,
                  fileType: r['fileType'] as String?,
                );
              }).toList() ??
              [];
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
    if (!silent) {
      _isLoading = false;
    }
    for (final module in _modules) {
      if (module.id >= _nextModuleId) {
        _nextModuleId = module.id + 1;
      }
      for (final lesson in module.lessons) {
        if (lesson.id >= _nextLessonId) {
          _nextLessonId = lesson.id + 1;
        }
      }
    }

    notifyListeners();
    if (!silent) {
      _restorePendingUploads();
    }
  }

  Future<void> _restorePendingUploads() async {
    if (_isRestoringPending) return;
    _isRestoringPending = true;
    try {
      final allTasks = _queueProvider.tasks;
      final lessonTasks = allTasks
          .where(
            (t) =>
                t.metadata?['uploadType'] == 'module_lesson' ||
                t.metadata?['uploadType'] == 'resource',
          )
          .toList();
      if (lessonTasks.isEmpty) {
        AppLogger.i('_restorePendingUploads: no active lesson items found');
        return;
      }
      AppLogger.i(
        '_restorePendingUploads: found ${lessonTasks.length} item(s) to restore',
      );

      bool hasUpdates = false;

      for (final task in lessonTasks) {
        if (_pendingLessons.containsKey(task.id)) continue;

        final uploadType = task.metadata?['uploadType'] as String?;
        final moduleId = task.metadata?['moduleId'] as int?;
        final restoredLessonId = task.metadata?['lessonId'] as int?;
        final lessonTitle =
            task.metadata?['lessonTitle'] as String? ?? task.title;
        final courseIdMeta = task.metadata?['courseId'] as int?;

        if (moduleId == null || courseIdMeta != courseId) continue;

        final moduleIndex = _modules.indexWhere((m) => m.id == moduleId);
        if (moduleIndex < 0) {
          AppLogger.w(
            '_restorePendingUploads: module $moduleId not found for task #${task.id}',
          );
          continue;
        }

        final alreadyExistsById = restoredLessonId != null
            ? _modules[moduleIndex].lessons.any((l) => l.id == restoredLessonId)
            : false;
        final alreadyExistsByUrl =
            task.fileUrl != null && task.fileUrl!.isNotEmpty
            ? _modules[moduleIndex].lessons.any(
                (l) => l.videoUrl == task.fileUrl || l.fileUrl == task.fileUrl,
              )
            : false;
        if (alreadyExistsById || alreadyExistsByUrl) {
          AppLogger.i(
            '_restorePendingUploads: skipping "$lessonTitle" — already exists on server',
          );
          continue;
        }

        final isResource = uploadType == 'resource';
        final progress = task.progress;

        if (task.state == UploadState.completed) {
          AppLogger.i(
            '_restorePendingUploads: skipping queueId=${task.id} '
            '"$lessonTitle" — upload already complete',
          );
          continue;
        }

        AppLogger.i(
          '_restorePendingUploads: restoring ${isResource ? "resource" : "lesson"} '
          '"$lessonTitle" queueId=${task.id} '
          'state=${task.state.name} progress=${(progress * 100).toInt()}% '
          'moduleId=$moduleId',
        );

        final lessonId = restoredLessonId ?? _nextLessonId++;
        if (restoredLessonId != null && restoredLessonId >= _nextLessonId) {
          _nextLessonId = lessonId + 1;
        }
        final pending = PendingLesson(
          queueId: task.id,
          lessonId: lessonId,
          title: lessonTitle,
          type: isResource ? LessonType.resource : LessonType.video,
          filePath: task.filePath,
          uploadProgress: progress,
          uploadStatus: task.state.name,
          fileUrl: task.fileUrl,
          moduleId: moduleId,
        );

        _pendingLessons[task.id] = pending;
        hasUpdates = true;
      }

      if (hasUpdates) {
        _startProgressPolling();
        notifyListeners();
      }
    } catch (e) {
      AppLogger.e('_restorePendingUploads error: $e');
    } finally {
      _isRestoringPending = false;
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
      // Cancel pending uploads for this module
      for (final entry in _pendingLessons.entries) {
        if (entry.value.moduleId == module.id) {
          await _queueProvider.cancelTask(entry.key);
        }
      }
      _modules.removeWhere((m) => m.id == module.id);
      _pendingLessons.removeWhere((_, p) => p.moduleId == module.id);
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
      url: isResource
          ? Urls.courseModuleResourceUrl
          : Urls.courseModuleLessonUrl,
      body: isResource
          ? {'resourceId': lesson.id, 'title': newName}
          : {'lessonId': lesson.id, 'title': newName},
    );
    if (response.isSuccess) {
      module.lessons[lessonIndex].title = newName;
      notifyListeners();
      ToastService.showSuccess(
        isResource
            ? 'Resource updated successfully'
            : 'Lesson renamed successfully',
      );
      return true;
    } else {
      ToastService.showError(response.errorMessage ?? 'Failed to rename');
      return false;
    }
  }

  Future<bool> deleteLesson(CourseModule module, int lessonIndex) async {
    final allModuleLessons = module.lessons;
    if (lessonIndex < 0 || lessonIndex >= allModuleLessons.length) {
      return false;
    }
    final lesson = allModuleLessons[lessonIndex];

    final isResource = lesson.type == LessonType.resource;
    final response = await getNetworkCaller().deleteRequest(
      url: isResource
          ? Urls.courseModuleResourceUrl
          : Urls.courseModuleLessonUrl,
      body: isResource ? {'resourceId': lesson.id} : {'lessonId': lesson.id},
    );
    if (response.isSuccess) {
      module.lessons.removeAt(lessonIndex);
      notifyListeners();
      ToastService.showSuccess(
        isResource
            ? 'Resource deleted successfully'
            : 'Lesson deleted successfully',
      );
      return true;
    } else {
      ToastService.showError(response.errorMessage ?? 'Failed to delete');
      return false;
    }
  }

  Future<void> deletePendingLesson(int queueId) async {
    final pending = _pendingLessons[queueId];
    if (pending == null) return;

    await _queueProvider.cancelTask(queueId);

    _pendingLessons.remove(queueId);

    if (_pendingLessons.isEmpty) {
      _progressTimer?.cancel();
      _progressTimer = null;
    }
    notifyListeners();
    ToastService.showSuccess('Upload cancelled');
  }

  Future<void> retryPendingLesson(int queueId) async {
    if (_isQueuing) {
      ToastService.showError('Please wait, another operation is in progress');
      return;
    }
    final pending = _pendingLessons[queueId];
    if (pending == null) return;

    _isQueuing = true;
    try {
      await _queueProvider.retryFailed(queueId);

      _pendingLessons[queueId] = PendingLesson(
        queueId: pending.queueId,
        lessonId: pending.lessonId,
        title: pending.title,
        type: pending.type,
        filePath: pending.filePath,
        moduleId: pending.moduleId,
        uploadProgress: 0.0,
        uploadStatus: 'pending',
      );
      _startProgressPolling();
      notifyListeners();
      ToastService.showInfo('Retrying upload...');
    } finally {
      _isQueuing = false;
    }
  }

  Future<bool> addVideoLesson(
    int moduleIndex,
    String title,
    XFile videoFile,
  ) async {
    if (_isQueuing) {
      ToastService.showError('Please wait, another file is being queued');
      return false;
    }

    _isQueuing = true;
    try {
      final module = _modules[moduleIndex];

      if (!await _checkDedupOrCleanup(videoFile.path)) return false;

      final lessonId = _nextLessonId++;
      int queueId;
      try {
        queueId = await _queueProvider.addModuleLessonToQueue(
          videoPath: videoFile.path,
          lessonTitle: title,
          moduleId: module.id,
          courseId: courseId,
          lessonId: lessonId,
        );
      } catch (e) {
        AppLogger.e('addVideoLesson queue error: $e');
        ToastService.showError('Failed to uplaod video lesson');
        return false;
      }

      if (queueId <= 0) return false;

      final pending = PendingLesson(
        queueId: queueId,
        lessonId: lessonId,
        title: title,
        type: LessonType.video,
        filePath: videoFile.path,
        uploadProgress: 0.0,
        uploadStatus: 'pending',
        moduleId: module.id,
      );

      _pendingLessons[queueId] = pending;
      _hasUnsavedChanges = true;
      notifyListeners();
      _startProgressPolling();
      return true;
    } finally {
      _isQueuing = false;
    }
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _pollProgress();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollProgress();
    });
  }

  Future<void> _pollProgress() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final allTasks = _queueProvider.tasks;
      bool updated = false;
      final completedIds = <int>[];
      final vanishedIds = <int>[];

      // Snapshot keys to avoid ConcurrentModificationError
      for (final queueId in _pendingLessons.keys.toList()) {
        final pending = _pendingLessons[queueId];
        if (pending == null) continue;
        final task = allTasks.where((t) => t.id == queueId).firstOrNull;

        if (task == null) {
          // Job was removed from service (e.g., after failure). Show failure
          // status for a few seconds so the user can see it, then auto-remove.
          if (pending.uploadStatus == 'uploading' ||
              pending.uploadStatus == 'pending') {
            pending.uploadStatus = 'failed';
            pending.uploadProgress = 0.0;
            pending.vanishedAt = DateTime.now().millisecondsSinceEpoch;
            updated = true;
          }
          if (pending.vanishedAt != null &&
              DateTime.now().millisecondsSinceEpoch - pending.vanishedAt! >
                  5000) {
            vanishedIds.add(queueId);
            updated = true;
          }
          continue;
        } else {
          // Clear the vanished flag if the task reappeared (e.g. retry).
          pending.vanishedAt = null;
        }

        final stateName = task.state.name;
        final progress = task.progress;

        if (pending.uploadStatus != stateName ||
            pending.uploadProgress != progress) {
          pending.uploadStatus = stateName;
          pending.uploadProgress = progress;
          updated = true;
        }

        if (task.fileUrl != null && task.fileUrl!.isNotEmpty) {
          pending.fileUrl = task.fileUrl;
        }

        if (task.state == UploadState.completed) {
          pending.uploadStatus = 'completed';
          pending.uploadProgress = 1.0;
          updated = true;
          completedIds.add(queueId);
          if (_notifiedCompletions.add(queueId)) {
            ToastService.showSuccess('Upload completed successfully');
          }
        } else if (task.state == UploadState.failed) {
          pending.uploadStatus = 'failed';
          pending.uploadProgress = 0.0;
          updated = true;
        }
      }

      // Remove vanished + completed in batch after iteration
      for (final id in [...vanishedIds, ...completedIds]) {
        _pendingLessons.remove(id);
      }

      // Trim notified completions set to prevent memory leak
      if (_notifiedCompletions.length > 100) {
        _notifiedCompletions.removeWhere(
          (k) => !_pendingLessons.containsKey(k),
        );
      }

      if (completedIds.isNotEmpty) {
        await _silentRefresh();
      }

      if (updated) notifyListeners();

      if (_pendingLessons.isEmpty) {
        _progressTimer?.cancel();
        _progressTimer = null;
        if (completedIds.isNotEmpty && !_disposed) {
          Future.delayed(const Duration(seconds: 10), () async {
            if (!_disposed) await _silentRefresh();
          });
        }
      }
    } catch (e) {
      AppLogger.e('_startProgressPolling error: $e');
    } finally {
      _polling = false;
    }
  }

  /// Checks if a filePath is already in the queue (any status).
  /// If it exists with a terminal status (failed/cancelled/completed),
  /// auto-cleans the old row to allow re-upload.
  /// Returns true if the file is safe to queue, false if blocked.
  Future<bool> _checkDedupOrCleanup(String filePath) async {
    final existing = _queueProvider.tasks
        .where(
          (t) {
            final matchesPath = t.filePath == filePath;
            final matchesOriginal = t.metadata?['originalPath'] == filePath;
            return (matchesPath || matchesOriginal) &&
                (t.metadata?['uploadType'] == 'module_lesson' ||
                    t.metadata?['uploadType'] == 'resource');
          },
        )
        .firstOrNull;
    if (existing == null) return true;

    if (existing.state == UploadState.pending ||
        existing.state == UploadState.uploading) {
      ToastService.showError('This file is already being uploaded');
      return false;
    }

    // Terminal status — clean up and allow re-upload
    await _queueProvider.removeTask(existing.id);
    _pendingLessons.remove(existing.id);
    return true;
  }

  Future<bool> addResourceLesson(
    int moduleIndex,
    String title,
    XFile resourceFile,
  ) async {
    if (_isQueuing) {
      ToastService.showError('Your file is being uploaded');
      return false;
    }

    _isQueuing = true;
    try {
      final module = _modules[moduleIndex];

      if (!await _checkDedupOrCleanup(resourceFile.path)) return false;

      final lessonId = _nextLessonId++;
      int queueId;
      try {
        final contentType = _inferResourceContentType(resourceFile.name);
        queueId = await _queueProvider.addResourceToQueue(
          filePath: resourceFile.path,
          lessonTitle: title,
          moduleId: module.id,
          courseId: courseId,
          contentType: contentType,
          lessonId: lessonId,
        );
      } catch (e) {
        AppLogger.e('addResourceLesson queue error: $e');
        ToastService.showError('Failed to upload resource lesson');
        return false;
      }

      if (queueId <= 0) return false;

      final pending = PendingLesson(
        queueId: queueId,
        lessonId: lessonId,
        title: title,
        type: LessonType.resource,
        filePath: resourceFile.path,
        uploadProgress: 0.0,
        uploadStatus: 'pending',
        moduleId: module.id,
      );

      _pendingLessons[queueId] = pending;
      _hasUnsavedChanges = true;
      notifyListeners();
      _startProgressPolling();
      return true;
    } finally {
      _isQueuing = false;
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
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }
}
