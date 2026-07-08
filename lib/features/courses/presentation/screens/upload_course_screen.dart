import 'dart:io';

import 'package:edtech/app/app_colors.dart';
import 'package:edtech/features/uploads/presentation/upload_queue_provider.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../widgets/upload_zone.dart';

class UploadCourseScreen extends StatefulWidget {
  const UploadCourseScreen({super.key});
  static const String name = '/upload-course-page';

  @override
  State<UploadCourseScreen> createState() => _UploadCourseScreenState();
}

class _UploadCourseScreenState extends State<UploadCourseScreen> {
  final _titleCtrl = TextEditingController();
  final _shortDescCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _reqCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  String _selectedLanguage = 'English';
  String _selectedLevel = 'Beginner';
  String _courseType = 'FREE';

  XFile? _thumbnailFile;
  XFile? _videoFile;
  bool _isPickingThumbnail = false;
  bool _isPickingVideo = false;
  bool _isUploading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _shortDescCtrl.dispose();
    _descCtrl.dispose();
    _reqCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickThumbnail() async {
    if (_isPickingThumbnail) return;
    setState(() => _isPickingThumbnail = true);
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) setState(() => _thumbnailFile = file);
    } catch (_) {
      ToastService.showError('Failed to open gallery');
    } finally {
      setState(() => _isPickingThumbnail = false);
    }
  }

  Future<void> _pickVideo() async {
    if (_isPickingVideo) return;
    setState(() => _isPickingVideo = true);
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file != null) setState(() => _videoFile = file);
    } catch (_) {
      ToastService.showError('Failed to open gallery');
    } finally {
      setState(() => _isPickingVideo = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_thumbnailFile == null) {
      ToastService.showError('Please select a thumbnail image');
      return;
    }

    final thumbFile = File(_thumbnailFile!.path);
    if (!await thumbFile.exists()) {
      ToastService.showError('Selected thumbnail no longer available');
      return;
    }
    if (_videoFile != null && !await File(_videoFile!.path).exists()) {
      ToastService.showError('Selected video no longer available');
      return;
    }

    final price = _courseType == 'PAID'
        ? double.tryParse(_priceCtrl.text.trim()) ?? 0
        : 0.0;

    if (!mounted) return;
    setState(() => _isUploading = true);

    final provider = context.read<UploadQueueProvider>();
    final title = _titleCtrl.text.trim();

    final id = await provider.createCourse(
      thumbnailPath: _thumbnailFile!.path,
      videoPath: _videoFile?.path,
      title: title,
      shortDescription: _shortDescCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      requirements: _reqCtrl.text.trim(),
      language: _selectedLanguage,
      level: _selectedLevel,
      type: _courseType,
      price: price,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (id > 0) {
      ToastService.showSuccess('Course created successfully!');
      Navigator.of(context).pop();
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
          'Create Course',
          style: TextStyle(fontSize: 20, color: cs.onSurface),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
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
                        _buildLabel('Title', cs),
                        const SizedBox(height: 8),
                        TextFormField(
                          maxLength: 50,
                          controller: _titleCtrl,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style: TextStyle(color: cs.onSurface),
                          decoration: _inputDecoration(
                            cs,
                            'Enter your course title',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty)
                              return 'Title is required';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Short Description', cs),
                        const SizedBox(height: 8),
                        TextFormField(
                          maxLength: 100,
                          controller: _shortDescCtrl,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style: TextStyle(color: cs.onSurface),
                          decoration: _inputDecoration(
                            cs,
                            'Enter short description',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty)
                              return 'Short description is required';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Description', cs),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descCtrl,
                          maxLines: 4,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style: TextStyle(color: cs.onSurface),
                          decoration: _inputDecoration(
                            cs,
                            'Enter your description',
                            borderRadius: 16,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty)
                              return 'Description is required';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Requirements', cs),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _reqCtrl,
                          maxLines: 4,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style: TextStyle(color: cs.onSurface),
                          decoration: _inputDecoration(
                            cs,
                            'Enter your requirements',
                            borderRadius: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Language', cs),
                        const SizedBox(height: 8),
                        _buildDropdownField(
                          cs,
                          _selectedLanguage,
                          ['English', 'Bangla', 'Spanish', 'Arabic', 'Hindi'],
                          (val) => setState(() => _selectedLanguage = val!),
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Thumbnail', cs),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _isPickingThumbnail ? null : _pickThumbnail,
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusDef,
                          ),
                          child: AnimatedOpacity(
                            opacity: _isPickingThumbnail ? 0.5 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: Ink(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? cs.surfaceContainerHighest
                                    : Colors.white,
                                border: Border.all(
                                  color: isDark
                                      ? cs.outlineVariant
                                      : AppColors.border,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppSizes.radiusDef,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _thumbnailFile?.name ?? 'Upload thumbnail',
                                      style: TextStyle(
                                        color: _thumbnailFile != null
                                            ? cs.onSurface
                                            : cs.onSurface.withValues(
                                                alpha: 0.5,
                                              ),
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_thumbnailFile != null)
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _thumbnailFile = null),
                                      child: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: cs.error,
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _thumbnailFile != null ? 'Change' : 'Choose',
                                    style: TextStyle(
                                      color: AppColors.themeColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Intro Video', cs, required: false),
                        const SizedBox(height: 8),
                        UploadZone(
                          cs: cs,
                          isDark: isDark,
                          isPicking: _isPickingVideo,
                          onTap: _isPickingVideo ? null : _pickVideo,
                          selectedFileName: _videoFile?.name,
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Level', cs),
                        const SizedBox(height: 8),
                        _buildDropdownField(
                          cs,
                          _selectedLevel,
                          ['Beginner', 'Intermediate', 'Advanced'],
                          (val) => setState(() => _selectedLevel = val!),
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Type', cs),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildRadioTile(cs, 'FREE')),
                            const SizedBox(width: 16),
                            Expanded(child: _buildRadioTile(cs, 'PAID')),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_courseType == 'PAID') ...[
                          _buildLabel('Price', cs),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _priceCtrl,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            style: TextStyle(color: cs.onSurface),
                            decoration: _inputDecoration(cs, 'Enter price'),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: AuthButton(
                text: _isUploading ? 'Queuing...' : 'Create Course',
                borderRadius: 28,
                onPressed: _isUploading ? null : _handleSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, ColorScheme cs, {bool required = true}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: cs.onSurface,
        ),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    ColorScheme cs,
    String hint, {
    double borderRadius = AppSizes.radiusDef,
  }) {
    final isDark = cs.brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: cs.onSurface.withValues(alpha: 0.5),
        fontSize: 14,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(
          color: isDark ? cs.outlineVariant : AppColors.border,
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: AppColors.themeColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }

  Widget _buildDropdownField(
    ColorScheme cs,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    final isDark = cs.brightness == Brightness.dark;
    return DropdownButtonFormField<String>(
      value: value,
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item, style: TextStyle(color: cs.onSurface)),
        );
      }).toList(),
      onChanged: onChanged,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: cs.onSurface.withValues(alpha: 0.5),
      ),
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: BorderSide(
            color: isDark ? cs.outlineVariant : AppColors.border,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: BorderSide(color: AppColors.themeColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? cs.surfaceContainerHighest : Colors.white,
      ),
      dropdownColor: isDark ? cs.surfaceContainerLow : Colors.white,
    );
  }

  Widget _buildRadioTile(ColorScheme cs, String type) {
    final isSelected = _courseType == type;
    final isDark = cs.brightness == Brightness.dark;
    return InkWell(
      onTap: () => setState(() => _courseType = type),
      borderRadius: BorderRadius.circular(AppSizes.radiusDef),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHighest : Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          border: Border.all(
            color: isDark ? cs.outlineVariant : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? AppColors.themeColor
                  : cs.onSurface.withValues(alpha: 0.5),
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              type,
              style: TextStyle(
                color: isSelected
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.5),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
