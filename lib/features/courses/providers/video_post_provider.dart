import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/native_upload_bridge.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:edtech/global/core/services/upload_path_storage.dart';
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

enum VideoUploadStep {
  idle,
  gettingUrl,
  uploading,
  creatingPost,
  done,
  error,
}

class VideoPostProvider extends ChangeNotifier {
  final ImagePicker _imagePicker;

  VideoPostProvider({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  VideoUploadStep _step = VideoUploadStep.idle;
  VideoUploadStep get step => _step;

  bool get isLoading =>
      _step != VideoUploadStep.idle &&
      _step != VideoUploadStep.done &&
      _step != VideoUploadStep.error;

  double _uploadProgress = 0.0;
  double get uploadProgress => _uploadProgress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  XFile? _videoFile;
  XFile? get videoFile => _videoFile;

  bool _isPicking = false;
  bool get isPicking => _isPicking;

  String get stepMessage {
    switch (_step) {
      case VideoUploadStep.gettingUrl:
        return 'Getting upload URL...';
      case VideoUploadStep.uploading:
        final pct = (_uploadProgress * 100).toInt();
        return pct > 0 ? 'Uploading $pct%' : 'Uploading...';
      case VideoUploadStep.creatingPost:
        return 'Creating post...';
      case VideoUploadStep.error:
        return 'Retry';
      case VideoUploadStep.idle:
      case VideoUploadStep.done:
        return 'Upload Video';
    }
  }

  String get buttonText => stepMessage;

  Future<XFile?> pickVideo() async {
    if (_isPicking) return null;
    _isPicking = true;
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
      _isPicking = false;
      notifyListeners();
    }
  }

  void reset() {
    _step = VideoUploadStep.idle;
    _errorMessage = null;
    _videoFile = null;
    _uploadProgress = 0.0;
    notifyListeners();
  }

  Future<bool> uploadVideoPost({
    required String title,
  }) async {
    _step = VideoUploadStep.gettingUrl;
    _errorMessage = null;
    notifyListeners();
    ToastService.showInfo('Getting upload URL...');

    await UploadPathStorage.savePath(
      filePath: _videoFile!.path,
      uploadType: 'video_post',
      title: title,
    );

    final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await UploadNotificationService.requestNotificationPermission();
    await UploadNotificationService.startService();

    try {
      final videoFile = _videoFile!;
      final videoName = videoFile.name;
      final videoContentType = _inferVideoContentType(videoName);

      final urlsResponse = await getNetworkCaller().postRequest(
        url: Urls.videoPostAssetsUploadUrl,
        body: {
          'videoFilename': videoName,
          'videoContentType': videoContentType,
        },
      );

      if (!urlsResponse.isSuccess) {
        _step = VideoUploadStep.error;
        _errorMessage = urlsResponse.errorMessage;
        ToastService.showError('Failed to get upload URL');
        notifyListeners();
        return false;
      }

      final raw = urlsResponse.responseData;
      final wrapper = raw is Map ? raw['data'] : null;
      final data = wrapper is Map ? (wrapper['data'] ?? wrapper) : wrapper;

      if (data is! Map<String, dynamic>) {
        _step = VideoUploadStep.error;
        _errorMessage = 'Invalid response';
        ToastService.showError('Invalid server response');
        notifyListeners();
        return false;
      }

      final uploadUrl = data['uploadUrl'] as String?;
      final fileUrl = data['fileUrl'] as String?;

      if (uploadUrl == null || fileUrl == null) {
        _step = VideoUploadStep.error;
        ToastService.showError('Invalid upload URL from server');
        notifyListeners();
        return false;
      }

      await NativeUploadBridge.startNativeUpload(
        filePath: videoFile.path,
        uploadUrl: uploadUrl,
        title: title,
        contentType: videoContentType,
        uploadType: 'video_post',
      );

      _step = VideoUploadStep.uploading;
      _uploadProgress = 0.0;
      notifyListeners();
      ToastService.showInfo('Uploading video...');

      final total = await videoFile.length();
      final stream = videoFile.openRead().cast<List<int>>();

      int sent = 0;
      int lastPct = -1;

      final progressStream = stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) {
            sent += chunk.length;
            final pct = total > 0 ? (sent * 100 ~/ total) : 0;
            if (pct != lastPct) {
              lastPct = pct;
              _uploadProgress = sent / total;
              if (pct % 10 == 0 && pct > 0) {
                ToastService.showInfo('Uploading $pct%');
              }
              notifyListeners();
              UploadNotificationService.showProgress(
                notificationId: notifId,
                progress: sent,
                total: total,
                title: title,
              );
            }
            sink.add(chunk);
          },
        ),
      );

      final request = _StreamedProgressRequest('PUT', Uri.parse(uploadUrl), progressStream);
      request.headers['Content-Type'] = videoContentType;
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

      _uploadProgress = 1.0;
      notifyListeners();
      ToastService.showSuccess('Video uploaded');

      _step = VideoUploadStep.creatingPost;
      notifyListeners();
      ToastService.showInfo('Creating post...');

      final metadata = await VideoMetadataService.getVideoInfo(videoFile.path);
      final fileSize = metadata.fileSize > 0
          ? metadata.fileSize
          : await videoFile.length();
      final duration = metadata.duration > 0 ? metadata.duration : 1;

      final postResponse = await getNetworkCaller().postRequest(
        url: Urls.videoPostUrl,
        body: {
          'title': title.trim(),
          'videoUrl': fileUrl,
          'duration': duration,
          'fileSize': fileSize,
        },
      );

      if (!postResponse.isSuccess) {
        _step = VideoUploadStep.error;
        _errorMessage = postResponse.errorMessage;
        ToastService.showError(postResponse.errorMessage ?? 'Failed to create post');
        notifyListeners();
        return false;
      }

      await NativeUploadBridge.clearState();
      _step = VideoUploadStep.done;
      notifyListeners();
      ToastService.showSuccess('Video post created!');
      await UploadNotificationService.showSuccess(
        notificationId: notifId,
        title: title,
        body: 'Video uploaded successfully',
      );
      await UploadNotificationService.stopService();

      await UploadPathStorage.clearAll();

      return true;
    } catch (e) {
      _step = VideoUploadStep.error;
      _errorMessage = e.toString();
      AppLogger.e('VideoPost: error — $_errorMessage');
      ToastService.showError('Upload failed. Will retry from queue.');
      notifyListeners();
      return false;
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
