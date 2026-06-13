import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
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
    final bytes = await file.readAsBytes();
    final filename = file.name;
    final contentType = _inferContentType(filename);

    final uploadUrlResponse = await getNetworkCaller().postRequest(
      url: Urls.coverUploadUrl,
      body: {'filename': filename, 'contentType': contentType},
    );

    if (!uploadUrlResponse.isSuccess) {
      _isLoading = false;
      _errorMessage = uploadUrlResponse.errorMessage;
      ToastService.showError(uploadUrlResponse.errorMessage ?? 'Failed to get upload URL');
      notifyListeners();
      return;
    }

    final dataObj = uploadUrlResponse.responseData is Map
        ? (uploadUrlResponse.responseData as Map)['data']
        : null;
    if (dataObj is! Map || dataObj['uploadUrl'] == null || dataObj['fileUrl'] == null) {
      _isLoading = false;
      _errorMessage = 'Invalid response from server';
      ToastService.showError('Failed to get upload URL. Invalid server response.');
      notifyListeners();
      return;
    }
    final uploadUrl = dataObj['uploadUrl'] as String;
    final fileUrl = dataObj['fileUrl'] as String;

    try {
      await _streamUpload(url: uploadUrl, bytes: bytes, contentType: contentType);
    } catch (e) {
      _isLoading = false;
      _uploadProgress = 0.0;
      _errorMessage = 'Failed to upload image to storage';
      ToastService.showError('Failed to upload image to storage');
      notifyListeners();
      return;
    }

    final confirmResponse = await getNetworkCaller().putRequest(
      url: Urls.coverConfirmUrl,
      body: {'fileUrl': fileUrl},
    );

    if (confirmResponse.isSuccess) {
      _isLoading = false;
      _uploadProgress = 0.0;
      _uploadedCoverUrl = fileUrl;
      onUploadSuccess?.call(fileUrl);
      ToastService.showSuccess('Cover photo updated successfully');
    } else {
      _isLoading = false;
      _uploadProgress = 0.0;
      _errorMessage = confirmResponse.errorMessage;
      ToastService.showError(confirmResponse.errorMessage ?? 'Failed to confirm upload');
    }
    notifyListeners();
  }

  Future<void> _streamUpload({
    required String url,
    required List<int> bytes,
    required String contentType,
  }) async {
    final totalBytes = bytes.length;
    const chunkSize = 65536;

    final request = http.StreamedRequest('PUT', Uri.parse(url));
    request.headers['Content-Type'] = contentType;
    request.contentLength = totalBytes;

    final responseFuture = request.send().timeout(uploadTimeout);

    int offset = 0;
    while (offset < totalBytes) {
      final end = (offset + chunkSize).clamp(0, totalBytes);
      request.sink.add(bytes.sublist(offset, end));
      offset = end;
      _uploadProgress = offset / totalBytes;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 8));
    }
    await request.sink.close();

    final streamedResponse = await responseFuture;
    if (streamedResponse.statusCode != 200) {
      throw HttpException(
        'S3 upload failed with status ${streamedResponse.statusCode}',
        uri: Uri.parse(url),
      );
    }
  }

  String _inferContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      default: return 'image/jpeg';
    }
  }
}
