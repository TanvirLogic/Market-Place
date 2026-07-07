import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:edtech/global/core/services/toast_service.dart';

/// UI step for the course-create/edit flow. Actual uploading is handled by the
/// unified upload system ([UploadQueueProvider]); this provider only owns the
/// image-picker + form state for the course sheets.
enum UploadStep {
  idle,
  gettingUrl,
  uploadingThumbnail,
  uploadingVideo,
  creatingCourse,
  done,
  error,
}

/// Holds the picked thumbnail/intro-video and lightweight step state for the
/// course create/edit sheets. Uploading is delegated to the unified upload
/// queue, so this no longer performs any network/S3 work itself.
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
        return pct > 0
            ? 'Uploading intro video $pct%'
            : 'Uploading intro video...';
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

  void setStep(UploadStep step) {
    _step = step;
    notifyListeners();
  }

  void reset() {
    _step = UploadStep.idle;
    _errorMessage = null;
    _createdCourseId = null;
    _thumbnailFile = null;
    _videoFile = null;
    _uploadProgress = 0.0;
    notifyListeners();
  }
}
