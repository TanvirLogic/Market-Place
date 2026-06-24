import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/courses/data/models/upload_task.dart';
import 'package:edtech/features/courses/data/repositories/upload_queue_repository.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/native_upload_bridge.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:edtech/global/core/services/upload_path_storage.dart';

class _StreamedProgressRequest extends http.BaseRequest {
  final Stream<List<int>> _stream;
  _StreamedProgressRequest(super.method, super.url, this._stream);
  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_stream);
  }
}

enum UploadStep {
  idle,
  gettingUrl,
  uploadingThumbnail,
  uploadingVideo,
  creatingCourse,
  done,
  error,
}

class CourseUploadProvider extends ChangeNotifier {
  final ImagePicker _imagePicker;

  CourseUploadProvider({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  UploadStep _step = UploadStep.idle;
  UploadStep get step => _step;

  bool get isLoading =>
      _step != UploadStep.idle &&
      _step != UploadStep.done &&
      _step != UploadStep.error;

  double _uploadProgress = 0.0;
  double get uploadProgress => _uploadProgress;

  bool _isPickingThumbnail = false;
  bool get isPickingThumbnail => _isPickingThumbnail;
  bool _isPickingVideo = false;
  bool get isPickingVideo => _isPickingVideo;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  XFile? _thumbnailFile;
  XFile? get thumbnailFile => _thumbnailFile;

  XFile? _videoFile;
  XFile? get videoFile => _videoFile;

  String? _createdCourseId;
  String? get createdCourseId => _createdCourseId;

  String get stepMessage {
    switch (_step) {
      case UploadStep.gettingUrl:
        return 'Getting upload URL...';
      case UploadStep.uploadingThumbnail:
        final pct = (_uploadProgress * 100).toInt();
        return pct > 0 ? 'Uploading thumbnail $pct%' : 'Uploading thumbnail...';
      case UploadStep.uploadingVideo:
        final pct = (_uploadProgress * 100).toInt();
        return pct > 0 ? 'Uploading intro video $pct%' : 'Uploading intro video...';
      case UploadStep.creatingCourse:
        return 'Creating course...';
      case UploadStep.error:
        return 'Retry';
      case UploadStep.idle:
      case UploadStep.done:
        return 'Create Course';
    }
  }

  String get buttonText => stepMessage;

  Future<XFile?> pickThumbnail() async {
    if (_isPickingThumbnail) return null;
    _isPickingThumbnail = true;
    notifyListeners();
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (file != null) {
        _thumbnailFile = file;
        notifyListeners();
      }
      return file;
    } catch (e) {
      ToastService.showError('Failed to open gallery');
      return null;
    } finally {
      _isPickingThumbnail = false;
      notifyListeners();
    }
  }

  Future<XFile?> pickVideo() async {
    if (_isPickingVideo) return null;
    _isPickingVideo = true;
    notifyListeners();
    try {
      final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (file != null) {
        _videoFile = file;
        notifyListeners();
      }
      return file;
    } catch (e) {
      ToastService.showError('Failed to open gallery');
      return null;
    } finally {
      _isPickingVideo = false;
      notifyListeners();
    }
  }

  void clearThumbnail() {
    _thumbnailFile = null;
    notifyListeners();
  }

  void clearVideo() {
    _videoFile = null;
    notifyListeners();
  }

  void reset() {
    _step = UploadStep.idle;
    _errorMessage = null;
    _createdCourseId = null;
    _thumbnailFile = null;
    _videoFile = null;
    notifyListeners();
  }

  Future<Map<String, String?>> uploadEditAssets({
    XFile? thumbnail,
    XFile? video,
  }) async {
    if (thumbnail == null && video == null) return {};

    final body = <String, dynamic>{};
    if (thumbnail != null) {
      body['thumbnailFilename'] = thumbnail.name;
      body['thumbnailContentType'] = _inferImageContentType(thumbnail.name);
    }
    if (video != null) {
      body['videoFilename'] = video.name;
      body['videoContentType'] = _inferVideoContentType(video.name);
    }

    final urlsResponse = await getNetworkCaller().postRequest(
      url: Urls.courseAssetsUploadUrl,
      body: body,
    );

    if (!urlsResponse.isSuccess) {
      ToastService.showError('Failed to get upload URL');
      return {};
    }

    final raw = urlsResponse.responseData;
    final wrapper = raw is Map ? raw['data'] : null;
    final innerData = wrapper is Map ? wrapper['data'] ?? wrapper : wrapper;
    if (innerData is! Map<String, dynamic>) return {};

    final result = <String, String?>{};

    if (thumbnail != null) {
      final info = innerData['thumbnail'] as Map<String, dynamic>?;
      final uploadUrl = info?['uploadUrl'] as String?;
      final fileUrl = info?['fileUrl'] as String?;
      if (uploadUrl != null && fileUrl != null) {
        ToastService.showInfo('Uploading thumbnail...');
        await _directUploadToS3(uploadUrl, thumbnail, _inferImageContentType(thumbnail.name));
        ToastService.showSuccess('Thumbnail uploaded');
        result['thumbnailUrl'] = fileUrl;
      }
    }

    if (video != null) {
      final info = innerData['video'] as Map<String, dynamic>?;
      final uploadUrl = info?['uploadUrl'] as String?;
      final fileUrl = info?['fileUrl'] as String?;
      if (uploadUrl != null && fileUrl != null) {
        ToastService.showInfo('Uploading intro video...');
        await _directUploadToS3(uploadUrl, video, _inferVideoContentType(video.name));
        ToastService.showSuccess('Intro video uploaded');
        result['introVideoUrl'] = fileUrl;
      }
    }

    return result;
  }

  Future<bool> uploadCourse({
    required String title,
    required String description,
    required String shortDescription,
    required String requirements,
    required String language,
    required String level,
    required String type,
    required double price,
  }) async {
    _errorMessage = null;

    final meta = CourseUploadMetadata(
      courseTitle: title,
      shortDescription: shortDescription,
      description: description,
      requirements: requirements,
      language: language,
      level: level,
      type: type,
      price: price,
      videoPath: _videoFile?.path,
    );
    final metadataJson = jsonEncode(meta.toJson());

    await UploadPathStorage.savePath(
      filePath: _thumbnailFile!.path,
      uploadType: 'course',
      title: title,
      metadata: metadataJson,
    );

    final queueItem = UploadQueueItem(
      filePath: _thumbnailFile!.path,
      title: 'Course: $title',
      status: 'pending',
      uploadType: 'course',
      metadata: metadataJson,
    );
    await UploadQueueRepository.insert(queueItem);

    _uploadProgress = 0.0;
    _step = UploadStep.gettingUrl;
    notifyListeners();
    ToastService.showInfo('Getting upload URL...');

    try {
      await UploadNotificationService.requestNotificationPermission();
      await UploadNotificationService.startService();
      final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final thumbName = _thumbnailFile!.name;
      final thumbContentType = _inferImageContentType(thumbName);

      final body = <String, dynamic>{
        'thumbnailFilename': thumbName,
        'thumbnailContentType': thumbContentType,
      };
      if (_videoFile != null) {
        body['videoFilename'] = _videoFile!.name;
        body['videoContentType'] = _inferVideoContentType(_videoFile!.name);
      }

      final urlsResponse = await getNetworkCaller().postRequest(
        url: Urls.courseAssetsUploadUrl,
        body: body,
      );

      if (!urlsResponse.isSuccess) {
        _step = UploadStep.error;
        _errorMessage = urlsResponse.errorMessage;
        ToastService.showError('Failed to get upload URL');
        notifyListeners();
        return false;
      }

      final raw = urlsResponse.responseData;
      final wrapper = raw is Map ? raw['data'] : null;
      final innerData = wrapper is Map ? wrapper['data'] ?? wrapper : wrapper;
      if (innerData is! Map<String, dynamic>) {
        _step = UploadStep.error;
        _errorMessage = 'Invalid server response';
        ToastService.showError('Invalid server response');
        notifyListeners();
        return false;
      }

      final thumbInfo = innerData['thumbnail'] as Map<String, dynamic>?;
      if (thumbInfo == null || thumbInfo['uploadUrl'] == null || thumbInfo['fileUrl'] == null) {
        _step = UploadStep.error;
        ToastService.showError('Missing thumbnail upload info');
        notifyListeners();
        return false;
      }

      final thumbUploadUrl = thumbInfo['uploadUrl'] as String;
      final thumbFileUrl = thumbInfo['fileUrl'] as String;

      await NativeUploadBridge.startNativeUpload(
        filePath: _thumbnailFile!.path,
        uploadUrl: thumbUploadUrl,
        title: 'Course Thumbnail: $title',
        contentType: thumbContentType,
        uploadType: 'course',
      );

      _step = UploadStep.uploadingThumbnail;
      _uploadProgress = 0.0;
      notifyListeners();
      ToastService.showInfo('Uploading thumbnail...');

      await _uploadToS3(thumbUploadUrl, _thumbnailFile!, thumbContentType, notifId, 'Uploading Course Thumbnail');

      _step = UploadStep.uploadingThumbnail;
      _uploadProgress = 1.0;
      notifyListeners();
      ToastService.showSuccess('Thumbnail uploaded');

      String? videoFileUrl;
      final videoInfo = innerData['video'] as Map<String, dynamic>?;
      if (videoInfo != null) {
        final videoUploadUrl = videoInfo['uploadUrl'] as String;
        videoFileUrl = videoInfo['fileUrl'] as String;

        await NativeUploadBridge.startNativeUpload(
          filePath: _videoFile!.path,
          uploadUrl: videoUploadUrl,
          title: 'Course Video: $title',
          contentType: _inferVideoContentType(_videoFile!.name),
          uploadType: 'course',
        );

        _step = UploadStep.uploadingVideo;
        _uploadProgress = 0.0;
        notifyListeners();
        ToastService.showInfo('Uploading intro video...');

        await _uploadToS3(
          videoUploadUrl,
          _videoFile!,
          _inferVideoContentType(_videoFile!.name),
          notifId,
          'Uploading Course Intro Video',
        );

        _step = UploadStep.uploadingVideo;
        _uploadProgress = 1.0;
        notifyListeners();
        ToastService.showSuccess('Intro video uploaded');
      }

      _step = UploadStep.creatingCourse;
      notifyListeners();
      ToastService.showInfo('Creating course...');

      final courseResponse = await getNetworkCaller().postRequest(
        url: Urls.createCourseUrl,
        body: {
          'title': title.trim(),
          'description': description.trim(),
          'shortDescription': shortDescription.trim(),
          'requirements': requirements.trim(),
          'thumbnailUrl': thumbFileUrl,
          if (videoFileUrl != null) 'introVideoUrl': videoFileUrl,
          'language': language,
          'level': level.toUpperCase(),
          'type': type.toUpperCase(),
          'price': price,
        },
      );

      if (!courseResponse.isSuccess) {
        _step = UploadStep.error;
        _errorMessage = courseResponse.errorMessage;
        ToastService.showError(courseResponse.errorMessage ?? 'Failed to create course');
        notifyListeners();
        return false;
      }

      final rawData = courseResponse.responseData['data'];
      final data = (rawData is Map) ? (rawData['data'] ?? rawData) : rawData;
      _createdCourseId = (data is Map<String, dynamic>) ? data['id']?.toString() : null;

      await NativeUploadBridge.clearState();
      _step = UploadStep.done;
      notifyListeners();
      ToastService.showSuccess('Course created successfully!');
      await UploadNotificationService.showSuccess(
        notificationId: notifId,
        title: 'Course Created',
        body: title,
      );
      await UploadNotificationService.stopService();

      await UploadPathStorage.clearAll();
      await UploadQueueRepository.clearCompleted();

      return true;
    } catch (e) {
      _step = UploadStep.error;
      _errorMessage = e.toString();
      AppLogger.e('CourseUpload: error — $_errorMessage');
      ToastService.showError('Upload failed. The course will resume from queue.');
      notifyListeners();
      return false;
    }
  }

  Future<void> _uploadToS3(String url, XFile file, String contentType, int notifId, String notifTitle) async {
    final total = await file.length();
    final stream = file.openRead().cast<List<int>>();

    int sent = 0;
    int lastPct = -1;
    DateTime lastToast = DateTime.now();

    final progressStream = stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          sent += chunk.length;
          final pct = total > 0 ? (sent * 100 ~/ total) : 0;
          if (pct != lastPct) {
            lastPct = pct;
            _uploadProgress = sent / total;
            notifyListeners();
            final now = DateTime.now();
            if (now.difference(lastToast) >= const Duration(seconds: 1)) {
              lastToast = now;
            }
            UploadNotificationService.showProgress(
              notificationId: notifId,
              progress: sent,
              total: total,
              title: notifTitle,
            );
          }
          sink.add(chunk);
        },
      ),
    );

    final request = _StreamedProgressRequest('PUT', Uri.parse(url), progressStream);
    request.headers['Content-Type'] = contentType;
    request.contentLength = total;

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(const Duration(hours: 6));
      if (response.statusCode != 200) {
        throw HttpException('Upload failed: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> _directUploadToS3(String url, XFile file, String contentType) async {
    final bytes = await file.readAsBytes();
    final response = await http.put(
      Uri.parse(url),
      headers: {'Content-Type': contentType},
      body: bytes,
    ).timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) {
      throw HttpException('Upload failed: ${response.statusCode}');
    }
  }

  String _inferImageContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'avif': return 'image/avif';
      default: return 'image/jpeg';
    }
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
