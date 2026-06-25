import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/widgets/app_alert_dialog.dart';
import 'package:edtech/features/courses/presentation/widgets/upload_zone.dart';
import 'package:edtech/features/courses/providers/course_upload_provider.dart';

class ManageModuleEditCourseSheet extends StatefulWidget {
  final int courseId;
  final String courseTitle;
  final String courseShortDescription;
  final String courseDescription;
  final String courseRequirements;
  final String courseLanguage;
  final String courseLevel;
  final String courseType;
  final double coursePrice;
  final Future<bool> Function(Map<String, dynamic> body) onSave;
  final VoidCallback onCourseRefreshed;

  const ManageModuleEditCourseSheet({
    super.key,
    required this.courseId,
    required this.courseTitle,
    required this.courseShortDescription,
    required this.courseDescription,
    required this.courseRequirements,
    required this.courseLanguage,
    required this.courseLevel,
    required this.courseType,
    required this.coursePrice,
    required this.onSave,
    required this.onCourseRefreshed,
  });

  static Future<void> show(
    BuildContext context, {
    required int courseId,
    required String courseTitle,
    required String courseShortDescription,
    required String courseDescription,
    required String courseRequirements,
    required String courseLanguage,
    required String courseLevel,
    required String courseType,
    required double coursePrice,
    required Future<bool> Function(Map<String, dynamic> body) onSave,
    required VoidCallback onCourseRefreshed,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ManageModuleEditCourseSheet(
        courseId: courseId,
        courseTitle: courseTitle,
        courseShortDescription: courseShortDescription,
        courseDescription: courseDescription,
        courseRequirements: courseRequirements,
        courseLanguage: courseLanguage,
        courseLevel: courseLevel,
        courseType: courseType,
        coursePrice: coursePrice,
        onSave: onSave,
        onCourseRefreshed: onCourseRefreshed,
      ),
    );
  }

  @override
  State<ManageModuleEditCourseSheet> createState() =>
      _ManageModuleEditCourseSheetState();
}

class _ManageModuleEditCourseSheetState
    extends State<ManageModuleEditCourseSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _shortDescCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _reqCtrl;
  late final TextEditingController _priceCtrl;
  late String _language;
  late String _level;
  late String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.courseTitle);
    _shortDescCtrl = TextEditingController(text: widget.courseShortDescription);
    _descCtrl = TextEditingController(text: widget.courseDescription);
    _reqCtrl = TextEditingController(text: widget.courseRequirements);
    _priceCtrl = TextEditingController(
      text: widget.coursePrice > 0 ? widget.coursePrice.toStringAsFixed(0) : '',
    );
    _language = widget.courseLanguage;
    _level = widget.courseLevel;
    _type = widget.courseType;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _shortDescCtrl.dispose();
    _descCtrl.dispose();
    _reqCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  bool _nothingChanged() {
    return _titleCtrl.text.trim() == (widget.courseTitle)
        && _shortDescCtrl.text.trim() == widget.courseShortDescription
        && _descCtrl.text.trim() == widget.courseDescription
        && _reqCtrl.text.trim() == widget.courseRequirements
        && _language == widget.courseLanguage
        && _level == widget.courseLevel
        && _type == widget.courseType
        && _priceCtrl.text.trim() == (widget.coursePrice > 0 ? widget.coursePrice.toStringAsFixed(0) : '')
        && context.read<CourseUploadProvider>().thumbnailFile == null
        && context.read<CourseUploadProvider>().videoFile == null;
  }

  Future<void> _handleSave() async {
    try {
      if (_nothingChanged()) {
        Navigator.of(context).pop();
        return;
      }
      final body = <String, dynamic>{
        'courseId': widget.courseId,
      };

      if (_titleCtrl.text.trim().isNotEmpty) {
        body['title'] = _titleCtrl.text.trim();
      }
      if (_shortDescCtrl.text.trim().isNotEmpty) {
        body['shortDescription'] = _shortDescCtrl.text.trim();
      }
      if (_descCtrl.text.trim().isNotEmpty) {
        body['description'] = _descCtrl.text.trim();
      }
      if (_reqCtrl.text.trim().isNotEmpty) {
        body['requirements'] = _reqCtrl.text.trim();
      }
      body['language'] = _language;
      body['level'] = _level;
      body['type'] = _type;
      final price = int.tryParse(_priceCtrl.text.trim());
      body['price'] = _type == 'FREE' ? 0 : (price ?? 0);

      final uploadProvider = context.read<CourseUploadProvider>();
      final thumbnail = uploadProvider.thumbnailFile;
      final video = uploadProvider.videoFile;

      if (thumbnail != null || video != null) {
        final ok = await uploadProvider.uploadEditAssets(
          thumbnail: thumbnail,
          video: video,
          callbackBody: body,
          courseId: widget.courseId,
          onCourseUpdated: widget.onCourseRefreshed,
        );
        if (!ok) return;
      } else {
        setState(() => _saving = true);
        await widget.onSave(body);
        setState(() => _saving = false);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      AppLogger.e('_handleSave error: $e');
      if (mounted) {
        setState(() => _saving = false);
        ToastService.showError('Failed to save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Edit Course',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLabel('Title', cs),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: TextStyle(color: cs.onSurface),
                    decoration: _inputDeco(cs, 'Enter your course title'),
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Short Description', cs),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _shortDescCtrl,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: TextStyle(color: cs.onSurface),
                    decoration: _inputDeco(cs, 'Enter short description'),
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
                    decoration: _inputDeco(cs, 'Enter your description', borderRadius: 16),
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
                    decoration: _inputDeco(cs, 'Enter your requirements', borderRadius: 16),
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Language', cs),
                  const SizedBox(height: 8),
                  _dropdown(cs, _language,
                      ['English', 'Bangla', 'Spanish', 'Arabic', 'Hindi'],
                      (val) {
                    if (val != null) setState(() => _language = val);
                  }),
                  const SizedBox(height: 16),
                  _buildLabel('Thumbnail', cs),
                  const SizedBox(height: 8),
                  Consumer<CourseUploadProvider>(
                    builder: (context, provider, _) {
                      final name = provider.thumbnailFile?.name;
                      return InkWell(
                        onTap: () async {
                          final confirmed = await AppAlertDialog.show(
                            context: context,
                            title: 'Replace Thumbnail',
                            content: 'Existing thumbnail will be deleted. Continue?',
                            confirmText: 'Okay',
                            cancelText: 'Cancel',
                            confirmColor: AppColors.themeColor,
                          );
                          if (confirmed == true) {
                            provider.pickThumbnail();
                          }
                        },
                        borderRadius:
                            BorderRadius.circular(AppSizes.radiusDef),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? cs.surfaceContainerHighest
                                : Colors.white,
                            border: Border.all(
                              color:
                                  isDark ? cs.outlineVariant : AppColors.border,
                              width: 1,
                            ),
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusDef),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  name ?? 'Upload thumbnail',
                                  style: TextStyle(
                                    color: name != null
                                        ? cs.onSurface
                                        : cs.onSurface.withValues(alpha: 0.5),
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (name != null)
                                GestureDetector(
                                  onTap: () => provider.clearThumbnail(),
                                  child: Icon(Icons.close,
                                      size: 18, color: cs.error),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                name != null ? 'Change' : 'Choose',
                                style: TextStyle(
                                    color: AppColors.themeColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Intro Video', cs, required: false),
                  const SizedBox(height: 8),
                  Consumer<CourseUploadProvider>(
                    builder: (context, provider, _) {
                      return UploadZone(
                        cs: cs,
                        isDark: isDark,
                        onTap: () async {
                          final confirmed = await AppAlertDialog.show(
                            context: context,
                            title: 'Replace Video',
                            content: 'Existing intro video will be deleted. Continue?',
                            confirmText: 'Okay',
                            cancelText: 'Cancel',
                            confirmColor: AppColors.themeColor,
                          );
                          if (confirmed == true) {
                            provider.pickVideo();
                          }
                        },
                        selectedFileName: provider.videoFile?.name,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Level', cs),
                  const SizedBox(height: 8),
                  _dropdown(cs, _level,
                      ['BEGINNER', 'INTERMEDIATE', 'ADVANCED'], (val) {
                    if (val != null) setState(() => _level = val);
                  }),
                  const SizedBox(height: 16),
                  _buildLabel('Type', cs),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _radioTile(
                              cs, 'FREE', _type, isDark, (v) {
                        setState(() => _type = v);
                      })),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _radioTile(
                              cs, 'PAID', _type, isDark, (v) {
                        setState(() => _type = v);
                      })),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_type == 'PAID') ...[
                    _buildLabel('Price', cs),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextStyle(color: cs.onSurface),
                      decoration: _inputDeco(cs, 'Enter price'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AuthButton(
            text: 'Save Changes',
            borderRadius: 24,
            isLoading: _saving,
            onPressed: _saving ? null : _handleSave,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLabel(String text, ColorScheme cs, {bool required = true}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
        children: [
          if (required)
            const TextSpan(
                text: ' *',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(ColorScheme cs, String hint, {double borderRadius = AppSizes.radiusDef}) {
    final isDark = cs.brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.5), fontSize: 14),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(
            color: isDark ? cs.outlineVariant : AppColors.border, width: 1),
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

  Widget _dropdown(ColorScheme cs, String value, List<String> items,
      ValueChanged<String?> onChanged) {
    final isDark = cs.brightness == Brightness.dark;
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items
          .map((item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, style: TextStyle(color: cs.onSurface))))
          .toList(),
      onChanged: onChanged,
      icon: Icon(Icons.keyboard_arrow_down_rounded,
          color: cs.onSurface.withValues(alpha: 0.5)),
      style: TextStyle(
          color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: BorderSide(
              color: isDark ? cs.outlineVariant : AppColors.border, width: 1),
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
      dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
    );
  }

  Widget _radioTile(ColorScheme cs, String tileType, String currentType,
      bool isDark, ValueChanged<String> onChanged) {
    final isSelected = currentType == tileType;
    return InkWell(
      onTap: () => onChanged(tileType),
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
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected
                  ? AppColors.themeColor
                  : cs.onSurface.withValues(alpha: 0.5),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              tileType,
              style: TextStyle(
                color: isSelected
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.5),
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}