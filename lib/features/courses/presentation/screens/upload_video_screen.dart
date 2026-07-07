import 'dart:io';

import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/features/uploads/presentation/upload_queue_provider.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../widgets/upload_zone.dart';

class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({super.key});
  static const String name = '/upload-video-page';

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  final TextEditingController _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  int _characterCount = 0;
  XFile? _pickedFile;
  bool _isPicking = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() {
      setState(() => _characterCount = _titleController.text.length);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file != null) setState(() => _pickedFile = file);
    } catch (_) {
      ToastService.showError('Failed to open gallery');
    } finally {
      setState(() => _isPicking = false);
    }
  }

  Future<void> _handleUpload() async {
    debugPrint('[UploadVideo] _handleUpload started');
    if (!_formKey.currentState!.validate()) {
      debugPrint('[UploadVideo] form invalid');
      return;
    }
    if (_pickedFile == null) {
      debugPrint('[UploadVideo] no file selected');
      ToastService.showError('Please select a video file');
      return;
    }

    final file = File(_pickedFile!.path);
    if (!await file.exists()) {
      debugPrint('[UploadVideo] file not found: ${_pickedFile!.path}');
      ToastService.showError('Selected file no longer available');
      return;
    }

    if (!mounted) return;
    setState(() => _isUploading = true);
    debugPrint(
      '[UploadVideo] calling addToQueue title="${_titleController.text.trim()}" path=${file.path}',
    );

    try {
      final provider = context.read<UploadQueueProvider>();
      final success = await provider.addToQueue(
        file,
        _titleController.text.trim(),
      );
      debugPrint('[UploadVideo] addToQueue returned success=$success');

      if (!mounted) return;

      if (success) {
        debugPrint('[UploadVideo] popping screen');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[UploadVideo] addToQueue threw: $e');
      if (!mounted) return;
      ToastService.showError('Upload failed');
    } finally {
      if (mounted) setState(() => _isUploading = false);
      debugPrint('[UploadVideo] _handleUpload finished');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16),
          child: AppBackButton(),
        ),
        title: Text(
          'Upload Video',
          style: TextStyle(fontSize: 20, color: cs.onSurface),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.horizontalPadding,
                  vertical: 16,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      UploadZone(
                        cs: cs,
                        isDark: isDark,
                        isPicking: _isPicking,
                        onTap: _isPicking ? null : _pickVideo,
                        selectedFileName: _pickedFile?.name,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Title',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            '$_characterCount/60',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        maxLines: 4,
                        maxLength: 60,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                        style: TextStyle(color: cs.onSurface),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty)
                            return 'Title is required';
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter your video title',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? cs.surfaceContainerHighest
                              : Colors.white,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: isDark
                                  ? cs.outlineVariant
                                  : AppColors.border,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppColors.themeColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFEF4444),
                              width: 1.5,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFEF4444),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: AuthButton(
                text: _pickedFile == null
                    ? 'Select a video first'
                    : 'Upload Video',
                borderRadius: 28,
                isLoading: _isUploading,
                onPressed: (_isPicking || _isUploading) ? null : _handleUpload,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
