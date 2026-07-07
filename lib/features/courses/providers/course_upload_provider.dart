import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  Future<bool> uploadEditAssets({
    required XFile? thumbnail,
    required XFile? video,
    required Map<String, dynamic> callbackBody,
    required int courseId,
    VoidCallback? onCourseUpdated,
  }) async {
    if (thumbnail == null && video == null) return true;

    // Step 1: Get presigned URLs (fast API call — sheet awaits this)
    final presignedBody = <String, dynamic>{};
    if (thumbnail != null) {
      presignedBody['thumbnailFilename'] = thumbnail.name;
      presignedBody['thumbnailContentType'] = _inferImageContentType(thumbnail.name);
      presignedBody['thumbnailFileSize'] = await thumbnail.length();
    } else {
      presignedBody['thumbnailFilename'] = 'keep.jpg';
      presignedBody['thumbnailContentType'] = 'image/jpeg';
      presignedBody['thumbnailFileSize'] = 0;
    }
    if (video != null) {
      presignedBody['videoFilename'] = video.name;
      presignedBody['videoContentType'] = _inferVideoContentType(video.name);
      presignedBody['videoFileSize'] = await video.length();
    } else {
      presignedBody['videoFilename'] = 'keep.mp4';
      presignedBody['videoContentType'] = 'video/mp4';
      presignedBody['videoFileSize'] = 0;
    }

    final urlsResponse = await getNetworkCaller().postRequest(
      url: Urls.courseAssetsUploadUrl,
      body: presignedBody,
    );

    if (!urlsResponse.isSuccess) {
      AppLogger.w('uploadEditAssets: POST failed — code=${urlsResponse.responseCode}, error=${urlsResponse.errorMessage}, data=${urlsResponse.responseData}');
      ToastService.showError(urlsResponse.errorMessage ?? 'Failed to get upload URL');
      return false;
    }

    final raw = urlsResponse.responseData;
    final wrapper = raw is Map ? raw['data'] : null;
    final innerData = wrapper is Map ? wrapper['data'] ?? wrapper : wrapper;
    if (innerData is! Map<String, dynamic>) {
      ToastService.showError('Invalid server response');
      return false;
    }

    // Collect upload info for background processing
    final uploads = <_PendingUpload>[];
    final multipartUploads = <_PendingMultipartUpload>[];
    if (thumbnail != null) {
      final info = innerData['thumbnail'] as Map<String, dynamic>?;
      final uploadUrl = info?['uploadUrl'] as String?;
      final fileUrl = info?['fileUrl'] as String?;
      if (fileUrl != null) {
        callbackBody['thumbnailUrl'] = fileUrl;
        if (info?['isMultipart'] as bool? ?? false) {
          multipartUploads.add(_PendingMultipartUpload(
            file: thumbnail,
            assetInfo: info!,
          ));
        } else if (uploadUrl != null) {
          uploads.add(_PendingUpload(
            file: thumbnail,
            uploadUrl: uploadUrl,
            contentType: _inferImageContentType(thumbnail.name),
          ));
        }
      }
    }

    if (video != null) {
      final info = innerData['video'] as Map<String, dynamic>?;
      final uploadUrl = info?['uploadUrl'] as String?;
      final fileUrl = info?['fileUrl'] as String?;
      if (fileUrl != null) {
        callbackBody['introVideoUrl'] = fileUrl;
        if (info?['isMultipart'] as bool? ?? false) {
          multipartUploads.add(_PendingMultipartUpload(
            file: video,
            assetInfo: info!,
          ));
        } else if (uploadUrl != null) {
          uploads.add(_PendingUpload(
            file: video,
            uploadUrl: uploadUrl,
            contentType: _inferVideoContentType(video.name),
          ));
        }
      }
    }

    if (uploads.isEmpty && multipartUploads.isEmpty) {
      ToastService.showError('Failed to get upload URLs');
      return false;
    }

    ToastService.showSuccess('Course update queued');

    // Fire off background upload + PUT /course — sheet pops immediately
    unawaited(_completeUploadEdit(
      uploads: uploads,
      multipartUploads: multipartUploads,
      callbackBody: Map<String, dynamic>.from(callbackBody),
      courseId: courseId,
      onCourseUpdated: onCourseUpdated,
    ));
    return true;
  }

  Future<void> _completeUploadEdit({
    required List<_PendingUpload> uploads,
    required List<_PendingMultipartUpload> multipartUploads,
    required Map<String, dynamic> callbackBody,
    required int courseId,
    VoidCallback? onCourseUpdated,
  }) async {
    try {
      await UploadNotificationService.requestNotificationPermission();
      await UploadNotificationService.startService();

      final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      for (final upload in uploads) {
        final total = await upload.file.length();
        final stream = upload.file.openRead().cast<List<int>>();

        int sent = 0;
        int sentPct = -1;
        final progressStream = stream.transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              sent += chunk.length;
              final pct = total > 0 ? (sent * 100 ~/ total) : 0;
              if (pct > sentPct) {
                sentPct = pct;
                UploadNotificationService.showProgress(
                  notificationId: notifId,
                  progress: sent,
                  total: total,
                  title: upload.file.name,
                );
              }
              sink.add(chunk);
            },
          ),
        );

        final request = _StreamedProgressRequest('PUT', Uri.parse(upload.uploadUrl), progressStream);
        request.headers['Content-Type'] = upload.contentType;
        request.contentLength = total;

        final client = http.Client();
        try {
          final response = await client.send(request).timeout(const Duration(minutes: 5));
          if (response.statusCode != 200) {
            throw HttpException('Upload failed: ${response.statusCode}');
          }
        } finally {
          client.close();
        }
      }

      for (final mu in multipartUploads) {
        final fileUrl = await _uploadMultipartAsset(
          mu.assetInfo, mu.file, notifId, 'Uploading ${mu.file.name}',
        );
        if (fileUrl == null) {
          throw Exception('Multipart upload failed for ${mu.file.name}');
        }
      }

      final response = await getNetworkCaller().putRequest(
        url: Urls.updateCourseUrl,
        body: callbackBody,
      );

      if (response.isSuccess) {
        onCourseUpdated?.call();
        ToastService.showSuccess('Course updated successfully');
        await UploadNotificationService.showSuccess(
          notificationId: notifId,
          title: 'Course Update',
          body: 'Course updated successfully',
        );
      } else {
        AppLogger.w('_completeUploadEdit: PUT /course failed — ${response.errorMessage}');
        ToastService.showError(response.errorMessage ?? 'Failed to update course');
        await UploadNotificationService.showError(
          notificationId: notifId,
          title: 'Course Update',
          body: response.errorMessage ?? 'Failed to update course',
        );
      }
    } catch (e) {
      AppLogger.e('_completeUploadEdit: error — $e');
      ToastService.showError('Failed to update course: $e');
      await UploadNotificationService.showError(
        notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'Course Update',
        body: 'Upload failed: $e',
      );
    } finally {
      await UploadNotificationService.stopService();
    }
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
      final thumbFileSize = await _thumbnailFile!.length();

      final body = <String, dynamic>{
        'thumbnailFilename': thumbName,
        'thumbnailContentType': thumbContentType,
        'thumbnailFileSize': thumbFileSize,
      };
      if (_videoFile != null) {
        body['videoFilename'] = _videoFile!.name;
        body['videoContentType'] = _inferVideoContentType(_videoFile!.name);
        body['videoFileSize'] = await _videoFile!.length();
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
      if (thumbInfo == null || thumbInfo['fileUrl'] == null) {
        _step = UploadStep.error;
        ToastService.showError('Missing thumbnail upload info');
        notifyListeners();
        return false;
      }
      final thumbFileUrl = thumbInfo['fileUrl'] as String;

      await NativeUploadBridge.startNativeUpload(
        filePath: _thumbnailFile!.path,
        uploadUrl: thumbInfo['uploadUrl'] as String? ?? '',
        title: 'Course Thumbnail: $title',
        contentType: thumbContentType,
        uploadType: 'course',
      );

      _step = UploadStep.uploadingThumbnail;
      _uploadProgress = 0.0;
      notifyListeners();
      ToastService.showInfo('Uploading thumbnail...');

      final thumbIsMultipart = thumbInfo['isMultipart'] as bool? ?? false;
      if (thumbIsMultipart) {
        await _uploadMultipartAsset(thumbInfo, _thumbnailFile!, notifId, 'Uploading Course Thumbnail');
      } else {
        final thumbUploadUrl = thumbInfo['uploadUrl'] as String?;
        if (thumbUploadUrl == null) {
          _step = UploadStep.error;
          ToastService.showError('Missing thumbnail upload URL');
          notifyListeners();
          return false;
        }
        await _uploadToS3(thumbUploadUrl, _thumbnailFile!, thumbContentType, notifId, 'Uploading Course Thumbnail');
      }

      _step = UploadStep.uploadingThumbnail;
      _uploadProgress = 1.0;
      notifyListeners();
      ToastService.showSuccess('Thumbnail uploaded');

      String? videoFileUrl;
      final videoInfo = innerData['video'] as Map<String, dynamic>?;
      if (videoInfo != null) {
        videoFileUrl = videoInfo['fileUrl'] as String?;

        if (videoInfo['isMultipart'] as bool? ?? false) {
          videoFileUrl = await _uploadMultipartAsset(videoInfo, _videoFile!, notifId, 'Uploading Course Intro Video');
        } else {
          final videoUploadUrl = videoInfo['uploadUrl'] as String?;
          if (videoUploadUrl == null) {
            _step = UploadStep.error;
            ToastService.showError('Missing video upload URL');
            notifyListeners();
            return false;
          }

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
          // ignore: use_null_aware_elements
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

  Future<String?> _uploadMultipartAsset(
    Map<String, dynamic> assetInfo,
    XFile file,
    int notifId,
    String notifTitle,
  ) async {
    final uploadId = assetInfo['uploadId'] as String?;
    final partsRaw = assetInfo['parts'] as List?;
    final totalParts = assetInfo['totalParts'] as int? ?? 0;
    final fileUrl = assetInfo['fileUrl'] as String?;

    if (uploadId == null || partsRaw == null || partsRaw.isEmpty) {
      ToastService.showError('Invalid multipart response');
      return null;
    }

    final fileSize = await file.length();
    final partSize = totalParts > 0
        ? (fileSize + totalParts - 1) ~/ totalParts
        : 5 * 1024 * 1024;

    final client = http.Client();
    final etags = <Map<String, dynamic>>[];
    final parts = partsRaw.cast<Map<String, dynamic>>()
      ..sort((a, b) => (a['partNumber'] as num).compareTo(b['partNumber'] as num));

    try {
      int completed = 0;
      for (final part in parts) {
        final partNumber = (part['partNumber'] as num).toInt();
        final uploadUrl = part['uploadUrl'] as String?;
        if (uploadUrl == null) continue;

        final startByte = (partNumber - 1) * partSize;
        final endByte = min(startByte + partSize, fileSize);

        final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
        request.contentLength = endByte - startByte;
        final stream = file.openRead(startByte, endByte);
        await stream.forEach(request.sink.add);
        request.sink.close();

        final response =
            await client.send(request).timeout(const Duration(hours: 1));

        if (response.statusCode == 200) {
          final eTag = response.headers['etag'] ?? response.headers['Etag'];
          if (eTag != null) {
            // Preserve S3's canonical quoted ETag verbatim — the backend's
            // complete endpoint expects the raw header value.
            etags.add({
              'partNumber': partNumber,
              'eTag': eTag,
            });
          }
        }

        completed++;
        _uploadProgress = completed / parts.length;
        notifyListeners();
        UploadNotificationService.showProgress(
          notificationId: notifId,
          progress: completed,
          total: parts.length,
          title: notifTitle,
        );
      }

      if (etags.length != parts.length) {
        ToastService.showError('Upload incomplete: ${etags.length}/${parts.length} parts');
        return null;
      }

      final completeResponse = await getNetworkCaller().postRequest(
        url: Urls.courseAssetsUploadUrl,
        body: {'uploadId': uploadId, 'parts': etags},
      );

      if (!completeResponse.isSuccess) return null;

      final cr = completeResponse.responseData;
      final cw = cr is Map ? cr['data'] : null;
      final cd = cw is Map ? (cw['data'] ?? cw) : cw;
      return cd is Map ? (cd['fileUrl'] as String? ?? fileUrl) : fileUrl;
    } finally {
      client.close();
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

class _PendingUpload {
  final XFile file;
  final String uploadUrl;
  final String contentType;

  const _PendingUpload({
    required this.file,
    required this.uploadUrl,
    required this.contentType,
  });
}

class _PendingMultipartUpload {
  final XFile file;
  final Map<String, dynamic> assetInfo;

  const _PendingMultipartUpload({
    required this.file,
    required this.assetInfo,
  });
}
