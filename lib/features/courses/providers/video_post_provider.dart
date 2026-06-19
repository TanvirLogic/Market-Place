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

  String get buttonText {
    switch (_step) {
      case VideoUploadStep.gettingUrl:
        return 'Processing...';
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

  void reset() {
    _step = VideoUploadStep.idle;
    _errorMessage = null;
    _videoFile = null;
    _uploadProgress = 0.0;
    UploadNotificationService.cancel();
    notifyListeners();
  }

  Future<bool> uploadVideoPost({
    required String title,
  }) async {
    _step = VideoUploadStep.gettingUrl;
    _errorMessage = null;
    notifyListeners();

    try {
      final videoFile = _videoFile!;
      final videoName = videoFile.name;
      final videoContentType = _inferVideoContentType(videoName);

      await UploadNotificationService.startService();

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
        AppLogger.e('VideoPost: upload-urls failed — ${urlsResponse.responseCode}, $_errorMessage');
        ToastService.showError('Failed to get upload URL');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }

      final raw = urlsResponse.responseData;
      final wrapper = raw is Map ? raw['data'] : null;
      final data = wrapper is Map ? (wrapper['data'] ?? wrapper) : wrapper;

      if (data is! Map<String, dynamic>) {
        _step = VideoUploadStep.error;
        _errorMessage = 'Invalid response from server';
        ToastService.showError('Failed to get upload URL');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }

      final uploadUrl = data['uploadUrl'] as String?;
      final fileUrl = data['fileUrl'] as String?;

      if (uploadUrl == null || fileUrl == null) {
        _step = VideoUploadStep.error;
        _errorMessage = 'Invalid upload info from server';
        ToastService.showError('Failed to get upload URL');
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }

      _step = VideoUploadStep.uploading;
      notifyListeners();

      final results = await Future.wait([
        _uploadToS3(uploadUrl, videoFile, videoContentType),
        _getVideoInfo(videoFile),
      ]);

      final info = results[1] as Map<String, int>;
      final fileSize = info['fileSize'] ?? 0;
      final duration = info['duration'] ?? 0;

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
        await UploadNotificationService.showError(title: 'Upload Failed');
        await UploadNotificationService.stopService();
        notifyListeners();
        return false;
      }

      _step = VideoUploadStep.done;
      ToastService.showSuccess('Video post created successfully');
      await UploadNotificationService.showSuccess(title: 'Upload Complete');
      await UploadNotificationService.stopService();
      notifyListeners();
      return true;
    } catch (e) {
      _step = VideoUploadStep.error;
      _errorMessage = e.toString();
      AppLogger.e('VideoPost: unexpected error — $_errorMessage');
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
              title: 'Uploading Video',
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
      client.close();
    }
  }

  Future<Map<String, int>> _getVideoInfo(XFile file) async {
    final metadata = await VideoMetadataService.getVideoInfo(file.path);
    if (metadata.duration > 0 && metadata.fileSize > 0) {
      return {'duration': metadata.duration, 'fileSize': metadata.fileSize};
    }
    final fileSize = await file.length();
    return {'duration': metadata.duration > 0 ? metadata.duration : 1, 'fileSize': fileSize};
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
