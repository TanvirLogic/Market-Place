import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:edtech/features/uploads/data/models/upload_enums.dart';
import 'package:edtech/features/uploads/presentation/image_upload_helper.dart';
import 'package:edtech/global/core/services/toast_service.dart';

class CoverUploadProvider extends ChangeNotifier {
  final ImagePicker _imagePicker;
  final Duration uploadTimeout;

  static const double _cropMaxWidth = 1920;
  static const double _cropMaxHeight = 1080;
  static const int _cropQuality = 92;

  CoverUploadProvider({
    ImagePicker? imagePicker,
    this.uploadTimeout = const Duration(seconds: 120),
  }) : _imagePicker = imagePicker ?? ImagePicker();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isCropping = false;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _uploadedCoverUrl;
  String? get uploadedCoverUrl => _uploadedCoverUrl;

  double _uploadProgress = 0.0;
  double get uploadProgress => _uploadProgress;

  bool get isUploading => _isLoading && _uploadProgress > 0.0;

  void Function(String newCoverUrl)? onUploadSuccess;

  void resetState() {
    _isLoading = false;
    _isCropping = false;
    _uploadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();
  }

  Future<XFile?> pickImage() async {
    if (_isCropping || _isLoading) {
      ToastService.showInfo('Upload already in progress');
      return null;
    }
    _isCropping = true;
    notifyListeners();

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (pickedFile == null) {
        _isCropping = false;
        notifyListeners();
      }
      return pickedFile;
    } catch (e) {
      _isCropping = false;
      notifyListeners();
      ToastService.showError('Failed to open gallery. Please try again.');
      return null;
    }
  }

  Future<void> uploadCoverFromFile(XFile file) async {
    _isCropping = false;
    _isLoading = true;
    _errorMessage = null;
    _uploadedCoverUrl = null;
    _uploadProgress = 0.0;
    notifyListeners();

    try {
      await _uploadFile(file);
    } catch (e) {
      _isLoading = false;
      _uploadProgress = 0.0;
      _errorMessage = e.toString();
      ToastService.showError('Failed to upload cover. Please try again.');
      notifyListeners();
    }
  }

  Future<void> uploadCoverFromGallery() async {
    if (_isCropping || _isLoading) {
      ToastService.showInfo('Upload already in progress');
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _uploadedCoverUrl = null;
    _uploadProgress = 0.0;
    notifyListeners();

    try {
      final XFile? croppedFile = await _pickAndCropImage();
      if (croppedFile == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      await _uploadFile(croppedFile);
    } catch (e) {
      _isLoading = false;
      _uploadProgress = 0.0;
      _errorMessage = e.toString();
      ToastService.showError('Failed to upload cover. Please try again.');
      notifyListeners();
    }
  }

  Future<XFile?> _pickAndCropImage() async {
    final XFile? pickedFile;
    try {
      pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
      );
    } catch (e) {
      ToastService.showError('Failed to open gallery. Please try again.');
      return null;
    }

    if (pickedFile == null) return null;

    _isCropping = true;
    notifyListeners();

    try {
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: _cropQuality,
        maxWidth: _cropMaxWidth.toInt(),
        maxHeight: _cropMaxHeight.toInt(),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Cover',
            toolbarColor: const Color(0xFF2563EB),
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            statusBarLight: true,
            activeControlsWidgetColor: const Color(0xFF2563EB),
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
          ),
          IOSUiSettings(
            title: 'Crop Cover',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );

      if (croppedFile == null) {
        _isCropping = false;
        notifyListeners();
        return null;
      }

      _isCropping = false;
      notifyListeners();
      return XFile(croppedFile.path);
    } catch (e) {
      _isCropping = false;
      notifyListeners();
      ToastService.showError('Failed to crop image. Please try again.');
      return null;
    }
  }

  Future<void> _uploadFile(XFile file) async {
    final result = await ImageUploadHelper().upload(
      filePath: file.path,
      type: UploadAssetType.cover,
      title: file.name,
      onProgress: (progress) {
        _uploadProgress = progress;
        notifyListeners();
      },
    );

    _isLoading = false;
    _uploadProgress = 0.0;

    if (result.isSuccess) {
      _uploadedCoverUrl = result.fileUrl;
      onUploadSuccess?.call(result.fileUrl!);
      ToastService.showSuccess('Cover photo updated successfully');
    } else {
      _errorMessage = result.errorMessage;
      ToastService.showError(result.errorMessage ?? 'Failed to upload cover');
    }

    notifyListeners();
  }
}
