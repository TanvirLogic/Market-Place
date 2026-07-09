import 'dart:io';

import 'package:edtech/app/app_colors.dart';
import 'package:edtech/features/uploads/presentation/upload_queue_provider.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/widgets/dashed_border.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:edtech/global/core/widgets/upload_zone.dart';

class UploadCourseScreen extends StatefulWidget {
  const UploadCourseScreen({super.key});
  static const String name = '/upload-course-page';

  @override
  State<UploadCourseScreen> createState() => _UploadCourseScreenState();
}

class _UploadCourseScreenState extends State<UploadCourseScreen>
    with SingleTickerProviderStateMixin {
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
  int? _videoSizeBytes;
  bool _isPickingThumbnail = false;
  bool _isPickingVideo = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStage = '';

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
      if (file != null) {
        final size = await File(file.path).length();
        setState(() {
          _videoFile = file;
          _videoSizeBytes = size;
        });
      }
    } catch (_) {
      ToastService.showError('Failed to open gallery');
    } finally {
      setState(() => _isPickingVideo = false);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadStage = 'Preparing...';
    });
    _pulseController.repeat(reverse: true);

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
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _uploadProgress = progress;
            if (progress < 0.3) {
              _uploadStage = 'Uploading thumbnail...';
            } else if (progress < 0.9) {
              _uploadStage = 'Uploading video...';
            } else {
              _uploadStage = 'Finalizing...';
            }
          });
        }
      },
    );

    _pulseController.stop();
    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _uploadProgress = 0.0;
      _uploadStage = '';
    });

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
            // ── Upload progress bar (top) ────────────────────────────
            if (_isUploading)
              _UploadProgressBar(
                progress: _uploadProgress,
                stage: _uploadStage,
                cs: cs,
                pulseController: _pulseController,
              ),
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
                            if (value == null || value.trim().isEmpty) {
                              return 'Title is required';
                            }
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
                            if (value == null || value.trim().isEmpty) {
                              return 'Short description is required';
                            }
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
                            if (value == null || value.trim().isEmpty) {
                              return 'Description is required';
                            }
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

                        // ── Thumbnail with image preview ─────────────────
                        _buildLabel('Thumbnail', cs),
                        const SizedBox(height: 8),
                        _buildThumbnailPicker(cs, isDark),
                        const SizedBox(height: 16),

                        // ── Intro Video with file info ───────────────────
                        _buildLabel('Intro Video', cs, required: false),
                        const SizedBox(height: 8),
                        _buildVideoPicker(cs, isDark),
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
            // ── Bottom button ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: _isUploading
                  ? _UploadingButton(
                      progress: _uploadProgress,
                      stage: _uploadStage,
                    )
                  : AuthButton(
                      text: 'Create Course',
                      borderRadius: 28,
                      onPressed: _handleSubmit,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Thumbnail picker with image preview ─────────────────────────────

  Widget _buildThumbnailPicker(ColorScheme cs, bool isDark) {
    if (_thumbnailFile != null) {
      return _ThumbnailPreview(
        filePath: _thumbnailFile!.path,
        fileName: _thumbnailFile!.name,
        cs: cs,
        isDark: isDark,
        onRemove: () => setState(() => _thumbnailFile = null),
        onChangeTap: _pickThumbnail,
      );
    }

    return InkWell(
      onTap: _isPickingThumbnail ? null : _pickThumbnail,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: AnimatedOpacity(
        opacity: _isPickingThumbnail ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 160,
          decoration: ShapeDecoration(
            color: isDark
                ? cs.surfaceContainerLow.withValues(alpha: 0.6)
                : const Color(0x99F5F5F5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
          ),
          foregroundDecoration: ShapeDecoration(
            shape: DashedBorder(
              color: isDark ? cs.outlineVariant : const Color(0xFFDEDEDE),
              width: 2.5,
              radius: 16,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isPickingThumbnail)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: ShapeDecoration(
                    color: AppColors.themeColor.withValues(alpha: 0.1),
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppColors.themeColor,
                    size: 28,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _isPickingThumbnail ? 'Opening gallery...' : 'Add Thumbnail',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                  children: [
                    const TextSpan(text: 'Tap to '),
                    TextSpan(
                      text: 'browse',
                      style: TextStyle(
                        color: AppColors.themeColor,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const TextSpan(text: ' from gallery'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Video picker with file info ─────────────────────────────────────

  Widget _buildVideoPicker(ColorScheme cs, bool isDark) {
    if (_videoFile != null) {
      return _VideoFileCard(
        fileName: _videoFile!.name,
        fileSize: _videoSizeBytes != null ? _formatFileSize(_videoSizeBytes!) : null,
        cs: cs,
        isDark: isDark,
        onRemove: () => setState(() {
          _videoFile = null;
          _videoSizeBytes = null;
        }),
        onChangeTap: _pickVideo,
      );
    }

    return UploadZone(
      cs: cs,
      isDark: isDark,
      isPicking: _isPickingVideo,
      onTap: _isPickingVideo ? null : _pickVideo,
      selectedFileName: null,
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────────

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
      initialValue: value,
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
            color: isSelected
                ? AppColors.themeColor
                : (isDark ? cs.outlineVariant : AppColors.border),
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

// ══════════════════════════════════════════════════════════════════════════════
// Private widgets
// ══════════════════════════════════════════════════════════════════════════════

/// Thumbnail image preview with remove/change actions.
class _ThumbnailPreview extends StatelessWidget {
  final String filePath;
  final String fileName;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onRemove;
  final VoidCallback onChangeTap;

  const _ThumbnailPreview({
    required this.filePath,
    required this.fileName,
    required this.cs,
    required this.isDark,
    required this.onRemove,
    required this.onChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: AppColors.themeColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image preview
          SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: Image.file(
                    File(filePath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                // Gradient overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                  ),
                ),
                // Remove button
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onRemove,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // File info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainerHighest : const Color(0xFFF8F9FB),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, size: 18, color: AppColors.themeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onChangeTap,
                  child: Text(
                    'Change',
                    style: TextStyle(
                      color: AppColors.themeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Video file card with file name, size, and remove/change actions.
class _VideoFileCard extends StatelessWidget {
  final String fileName;
  final String? fileSize;
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback onRemove;
  final VoidCallback onChangeTap;

  const _VideoFileCard({
    required this.fileName,
    this.fileSize,
    required this.cs,
    required this.isDark,
    required this.onRemove,
    required this.onChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: AppColors.themeColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.themeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.videocam_rounded,
              color: AppColors.themeColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fileSize != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    fileSize!,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: onChangeTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Change',
                style: TextStyle(
                  color: AppColors.themeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 16, color: cs.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top progress bar shown during upload.
class _UploadProgressBar extends StatelessWidget {
  final double progress;
  final String stage;
  final ColorScheme cs;
  final AnimationController pulseController;

  const _UploadProgressBar({
    required this.progress,
    required this.stage,
    required this.cs,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: AppColors.themeColor.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stage,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.themeColor,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.themeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.themeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uploading button with embedded progress.
class _UploadingButton extends StatelessWidget {
  final double progress;
  final String stage;

  const _UploadingButton({
    required this.progress,
    required this.stage,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.gradientStart, AppColors.gradientEnd],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Stack(
            children: [
              // Progress fill
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
              // Content
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Uploading ${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
