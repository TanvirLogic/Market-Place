import 'dart:async';

import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:edtech/global/core/services/video_metadata_service.dart';

class _StreamedProgressRequest extends http.BaseRequest {
  final Stream<List<int>> _stream;

  _StreamedProgressRequest(super.method, super.url, this._stream);

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_stream);
  }
}

class ManageModuleProvider extends ChangeNotifier {
  final int courseId;
  int _nextModuleId = 1;
  int _nextLessonId = 1;
  bool _isLoading = true;
  double _uploadProgress = 0.0;

  final List<CourseModule> _modules = [];
  final Map<int, String> _videoUrlCache = {};
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
  double get uploadProgress => _uploadProgress;

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
    void Function(double)? onProgress,
  }) async {
    final module = _modules[moduleIndex];
    final videoName = videoFile.name;
    final videoContentType = _inferVideoContentType(videoName);

    await UploadNotificationService.startService();

    final uploadUrlResponse = await getNetworkCaller().postRequest(
      url: Urls.courseModuleUploadUrl,
      body: {
        'moduleID': module.id,
        'videoFilename': videoName,
        'videoContentType': videoContentType,
      },
    );
    if (!uploadUrlResponse.isSuccess) {
      ToastService.showError(uploadUrlResponse.errorMessage ?? 'Failed to get upload URL');
      await UploadNotificationService.showError(title: 'Upload Failed');
      await UploadNotificationService.stopService();
      return false;
    }

    final raw = uploadUrlResponse.responseData;
    final wrapper = raw is Map ? raw['data'] : null;
    final data = wrapper is Map ? (wrapper['data'] ?? wrapper) : wrapper;
    if (data is! Map) {
      ToastService.showError('Invalid upload URL response');
      await UploadNotificationService.showError(title: 'Upload Failed');
      await UploadNotificationService.stopService();
      return false;
    }
    final uploadUrl = data['uploadUrl'] as String?;
    final fileUrl = data['fileUrl'] as String?;
    if (uploadUrl == null || fileUrl == null) {
      ToastService.showError('Invalid upload URL response');
      await UploadNotificationService.showError(title: 'Upload Failed');
      await UploadNotificationService.stopService();
      return false;
    }

    final results = await Future.wait([
      _uploadToS3(uploadUrl, videoFile, videoContentType, onProgress: onProgress),
      _getVideoInfo(videoFile),
    ]);

    if (!(results[0] as bool)) return false;

    final info = results[1] as Map<String, int>;
    final fileSize = info['fileSize']!;
    final duration = info['duration']!;

    final lessonResponse = await getNetworkCaller().postRequest(
      url: Urls.courseModuleLessonUrl,
      body: {
        'title': title,
        'moduleId': module.id,
        'videoUrl': fileUrl,
        'duration': duration,
        'fileSize': fileSize,
      },
    );
    if (!lessonResponse.isSuccess) {
      ToastService.showError(lessonResponse.errorMessage ?? 'Failed to create lesson');
      await UploadNotificationService.showError(title: 'Upload Failed');
      await UploadNotificationService.stopService();
      return false;
    }

    final lessonRaw = lessonResponse.responseData;
    final lessonData = (lessonRaw is Map) ? (lessonRaw['data'] is Map ? lessonRaw['data']['data'] ?? lessonRaw['data'] : lessonRaw['data']) : null;
    final lessonId = (lessonData is Map) ? lessonData['id'] as int? : null;

    final newId = lessonId ?? _nextLessonId++;
    _videoUrlCache[newId] = fileUrl;
    module.lessons.add(
      Lesson(
        id: newId,
        title: title,
        duration: duration > 0 ? _formatDuration(duration) : '0:00',
        type: LessonType.video,
        videoUrl: fileUrl,
      ),
    );
    notifyListeners();
    ToastService.showSuccess('Video lesson added successfully');
    await UploadNotificationService.showSuccess(title: 'Upload Complete');
    await UploadNotificationService.stopService();
    return true;
  }

  Future<bool> addResourceLesson(int moduleIndex, String title, XFile resourceFile) async {
    final module = _modules[moduleIndex];
    final fileSize = await resourceFile.length();
    final filename = resourceFile.name;
    final contentType = _inferResourceContentType(filename);

    final uploadUrlResponse = await getNetworkCaller().postRequest(
      url: Urls.courseModuleResourceUploadUrl,
      body: {
        'filename': filename,
        'contentType': contentType,
      },
    );
    if (!uploadUrlResponse.isSuccess) {
      ToastService.showError(uploadUrlResponse.errorMessage ?? 'Failed to get upload URL');
      return false;
    }

    final raw = uploadUrlResponse.responseData;
    final data = (raw is Map) ? (raw['data'] is Map ? raw['data']['data'] ?? raw['data'] : raw['data']) : null;
    if (data is! Map) {
      ToastService.showError('Invalid upload URL response');
      return false;
    }
    final uploadUrl = data['uploadUrl'] as String?;
    final fileUrl = data['fileUrl'] as String?;
    if (uploadUrl == null || fileUrl == null) {
      ToastService.showError('Invalid upload URL response');
      return false;
    }

    final uploaded = await _uploadToS3(uploadUrl, resourceFile, contentType);
    if (!uploaded) return false;

    final lessonResponse = await getNetworkCaller().postRequest(
      url: Urls.courseModuleResourceUrl,
      body: {
        'moduleId': module.id,
        'title': title,
        'fileUrl': fileUrl,
        'fileType': contentType,
        'fileSize': fileSize,
      },
    );
    if (!lessonResponse.isSuccess) {
      ToastService.showError(lessonResponse.errorMessage ?? 'Failed to create lesson');
      return false;
    }

    final lessonRaw = lessonResponse.responseData;
    final lessonData = (lessonRaw is Map) ? (lessonRaw['data'] is Map ? lessonRaw['data']['data'] ?? lessonRaw['data'] : lessonRaw['data']) : null;
    final lessonId = (lessonData is Map) ? lessonData['id'] as int? : null;

    module.lessons.add(
      Lesson(
        id: lessonId ?? _nextLessonId++,
        title: title,
        duration: '0:00',
        type: LessonType.resource,
      ),
    );
    notifyListeners();
    ToastService.showSuccess('Resource lesson added successfully');
    return true;
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

  Future<bool> _uploadToS3(
    String url,
    XFile file,
    String contentType, {
    void Function(double)? onProgress,
  }) async {
    _uploadProgress = 0.0;
    onProgress?.call(0.0);
    notifyListeners();

    final total = await file.length();
    final stream = file.openRead().cast<List<int>>();

    int sent = 0;
    int lastPct = -1;
    DateTime lastUiUpdate = DateTime.now();

    final progressStream = stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          sent += chunk.length;
          final pct = total > 0 ? (sent * 100 ~/ total) : 0;
          if (pct != lastPct) {
            lastPct = pct;
            _uploadProgress = sent / total;
            onProgress?.call(sent / total);
            final now = DateTime.now();
            if (now.difference(lastUiUpdate) >= const Duration(milliseconds: 200)) {
              lastUiUpdate = now;
              notifyListeners();
            }
            UploadNotificationService.showProgress(
              progress: sent,
              total: total,
              title: 'Uploading Video Lesson',
              fileName: file.name,
            );
          }
          sink.add(chunk);
        },
      ),
    );

    final request = _StreamedProgressRequest(
      'PUT',
      Uri.parse(url),
      progressStream,
    );
    request.headers['Content-Type'] = contentType;
    request.contentLength = total;

    final client = http.Client();

    try {
      final response = await client.send(request).timeout(const Duration(hours: 6));
      if (response.statusCode != 200) {
        AppLogger.e('S3 upload failed: status=${response.statusCode}');
        ToastService.showError('Upload failed with status ${response.statusCode}');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        return false;
      }
      return true;
    } on TimeoutException {
      AppLogger.e('S3 upload timed out');
      ToastService.showError('Upload timed out. Check your connection and try again.');
      await UploadNotificationService.showError(title: 'Upload Failed');
      await UploadNotificationService.stopService();
      return false;
    } catch (e) {
      AppLogger.e('S3 upload failed: $e');
      ToastService.showError('File upload failed');
      await UploadNotificationService.showError(title: 'Upload Failed');
      await UploadNotificationService.stopService();
      return false;
    } finally {
      client.close();
    }
  }

  Future<Map<String, int>> _getVideoInfo(XFile file) async {
    final metadata = await VideoMetadataService.getVideoInfo(file.path);
    if (metadata.duration > 0 && metadata.fileSize > 0) {
      return {'duration': metadata.duration, 'fileSize': metadata.fileSize};
    }
    final fileSize = await file.length();
    return {
      'duration': metadata.duration > 0 ? metadata.duration : 1,
      'fileSize': fileSize,
    };
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _inferVideoContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4': return 'video/mp4';
      case 'mov': case 'quicktime': return 'video/quicktime';
      case 'mkv': case 'x-matroska': return 'video/x-matroska';
      case 'webm': return 'video/webm';
      default: return 'video/mp4';
    }
  }
}
