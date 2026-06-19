import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';

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
  uploadingUrls,
  uploadingImage,
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

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  XFile? _thumbnailFile;
  XFile? get thumbnailFile => _thumbnailFile;

  XFile? _videoFile;
  XFile? get videoFile => _videoFile;

  String? _createdCourseId;
  String? get createdCourseId => _createdCourseId;

  bool _isCancelled = false;
  http.Client? _activeClient;

  void cancel() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
    _step = UploadStep.idle;
    _uploadProgress = 0.0;
    UploadNotificationService.cancel();
    UploadNotificationService.stopService();
    notifyListeners();
  }

  String get buttonText {
    switch (_step) {
      case UploadStep.uploadingUrls:
        return 'Processing...';
      case UploadStep.uploadingImage:
      case UploadStep.uploadingVideo:
        final pct = (_uploadProgress * 100).toInt();
        final base = _step == UploadStep.uploadingImage
            ? 'Uploading image'
            : 'Uploading video';
        return pct > 0 ? '$base $pct%' : base;
      case UploadStep.creatingCourse:
        return 'Creating course...';
      case UploadStep.error:
        return 'Retry';
      case UploadStep.idle:
      case UploadStep.done:
        return 'Create Course';
    }
  }

  Future<XFile?> pickThumbnail() async {
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
    }
  }

  Future<XFile?> pickVideo() async {
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
    UploadNotificationService.cancel();
    UploadNotificationService.stopService();
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
        await _uploadToS3(
          uploadUrl,
          thumbnail,
          _inferImageContentType(thumbnail.name),
        );
        result['thumbnailUrl'] = fileUrl;
      }
    }

    if (video != null) {
      final info = innerData['video'] as Map<String, dynamic>?;
      final uploadUrl = info?['uploadUrl'] as String?;
      final fileUrl = info?['fileUrl'] as String?;
      if (uploadUrl != null && fileUrl != null) {
        await _uploadToS3(
          uploadUrl,
          video,
          _inferVideoContentType(video.name),
        );
        result['introVideoUrl'] = fileUrl;
      }
    }

    return result;
  }

  bool _checkCancelled() {
    if (_isCancelled) {
      _step = UploadStep.idle;
      _uploadProgress = 0.0;
      _errorMessage = null;
      notifyListeners();
      return true;
    }
    return false;
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
    _isCancelled = false;
    _errorMessage = null;
    notifyListeners();

    try {
      await UploadNotificationService.startService();
      _step = UploadStep.uploadingUrls;
      notifyListeners();

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

      if (_checkCancelled()) return false;

      if (!urlsResponse.isSuccess) {
        _step = UploadStep.error;
        _errorMessage = urlsResponse.errorMessage;
        AppLogger.e('CourseUpload: upload-urls failed — code=${urlsResponse.responseCode}, error=$_errorMessage, body=${urlsResponse.responseData}');
        ToastService.showError('Failed to get upload URL');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }

      AppLogger.i('CourseUpload: upload-urls response — ${urlsResponse.responseData}');

      final raw = urlsResponse.responseData;
      final wrapper = raw is Map ? raw['data'] : null;
      final innerData = wrapper is Map ? wrapper['data'] ?? wrapper : wrapper;
      if (innerData is! Map<String, dynamic>) {
        _step = UploadStep.error;
        _errorMessage = 'Invalid response from server';
        AppLogger.e('CourseUpload: unexpected response format — $raw');
        ToastService.showError('Failed to get upload URL');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }
      final thumbInfo = innerData['thumbnail'] as Map<String, dynamic>?;
      if (thumbInfo == null) {
        _step = UploadStep.error;
        _errorMessage = 'Missing thumbnail upload info';
        ToastService.showError('Failed to get upload URL');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }
      final thumbUploadUrl = thumbInfo['uploadUrl'] as String?;
      final thumbFileUrl = thumbInfo['fileUrl'] as String?;
      if (thumbUploadUrl == null || thumbFileUrl == null) {
        _step = UploadStep.error;
        _errorMessage = 'Invalid thumbnail upload info';
        ToastService.showError('Failed to get upload URL');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }

      _step = UploadStep.uploadingImage;
      notifyListeners();

      await _uploadToS3(thumbUploadUrl, _thumbnailFile!, thumbContentType);
      if (_checkCancelled()) return false;

      String? videoFileUrl;
      final videoInfo = innerData['video'] as Map<String, dynamic>?;
      if (videoInfo != null) {
        videoFileUrl = videoInfo['fileUrl'] as String;
        final videoUploadUrl = videoInfo['uploadUrl'] as String;

        _step = UploadStep.uploadingVideo;
        notifyListeners();

        await _uploadToS3(
          videoUploadUrl,
          _videoFile!,
          _inferVideoContentType(_videoFile!.name),
        );
        if (_checkCancelled()) return false;
      }

      _step = UploadStep.creatingCourse;
      notifyListeners();

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

      if (courseResponse.isSuccess) {
        final rawData = courseResponse.responseData['data'];
        final data = (rawData is Map) ? (rawData['data'] ?? rawData) : rawData;
        _createdCourseId = (data is Map<String, dynamic>) ? data['id']?.toString() : null;
        _step = UploadStep.done;
        ToastService.showSuccess('Course created successfully');
        await UploadNotificationService.showSuccess(title: 'Course Created');
        await UploadNotificationService.stopService();
        notifyListeners();
        return true;
      } else {
        _step = UploadStep.error;
        _errorMessage = courseResponse.errorMessage;
        ToastService.showError(courseResponse.errorMessage ?? 'Failed to create course');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }
    } catch (e) {
      if (_isCancelled) {
        _step = UploadStep.idle;
        _uploadProgress = 0.0;
        _errorMessage = null;
        notifyListeners();
        return false;
      }
      _step = UploadStep.error;
      _errorMessage = e.toString();
      AppLogger.e('CourseUpload: unexpected error — $_errorMessage');
      ToastService.showError('Something went wrong. Please try again.');
      await UploadNotificationService.showError(title: 'Upload Failed');
      await UploadNotificationService.stopService();
      notifyListeners();
      return false;
    }
  }

  Future<void> _uploadToS3(String url, XFile file, String contentType) async {
    _uploadProgress = 0.0;
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
            final now = DateTime.now();
            if (now.difference(lastUiUpdate) >= const Duration(milliseconds: 200)) {
              lastUiUpdate = now;
              notifyListeners();
            }
            UploadNotificationService.showProgress(
              progress: sent,
              total: total,
              title: 'Uploading Course Assets',
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
    _activeClient = client;

    try {
      final response = await client.send(request).timeout(const Duration(hours: 6));
      _uploadProgress = 1.0;
      notifyListeners();
      if (response.statusCode != 200) {
        throw HttpException(
          'Upload failed with status ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
    } on TimeoutException {
      throw HttpException(
        'Upload timed out. Check your connection and try again.',
        uri: Uri.parse(url),
      );
    } finally {
      _uploadProgress = 0.0;
      notifyListeners();
      if (_activeClient == client) _activeClient = null;
      client.close();
    }
  }

  String _inferImageContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'avif':
        return 'image/avif';
      default:
        return 'image/jpeg';
    }
  }

  String _inferVideoContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
      case 'quicktime':
        return 'video/quicktime';
      case 'mkv':
      case 'x-matroska':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }
}