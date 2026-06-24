import 'package:edtech/features/courses/presentation/widgets/upload_zone.dart';
import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ManageModuleAddLessonSheet extends StatefulWidget {
  final LessonType lessonType;
  final int moduleId;
  final int courseId;
  final Future<bool> Function(
    String title,
    XFile file,
    void Function(double) onProgress,
  ) onAddLesson;

  const ManageModuleAddLessonSheet({
    super.key,
    required this.lessonType,
    required this.moduleId,
    required this.courseId,
    required this.onAddLesson,
  });

  static Future<void> show(
    BuildContext context, {
    required LessonType lessonType,
    required int moduleId,
    required int courseId,
    required Future<bool> Function(
      String title,
      XFile file,
      void Function(double) onProgress,
    ) onAddLesson,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ManageModuleAddLessonSheet(
        lessonType: lessonType,
        moduleId: moduleId,
        courseId: courseId,
        onAddLesson: onAddLesson,
      ),
    );
  }

  @override
  State<ManageModuleAddLessonSheet> createState() =>
      _ManageModuleAddLessonSheetState();
}

class _ManageModuleAddLessonSheetState
    extends State<ManageModuleAddLessonSheet> {
  final _titleController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  XFile? _selectedFile;
  bool _isUploading = false;
  bool _isPicking = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _isPicking = true);
    XFile? file;
    if (widget.lessonType == LessonType.video) {
      file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
        ],
      );
      if (result != null && result.files.single.path != null) {
        file = XFile(result.files.single.path!);
      }
    }
    if (mounted) setState(() => _isPicking = false);
    if (file != null) setState(() => _selectedFile = file);
  }

  Future<void> _handleUpload() async {
    if (_selectedFile == null) {
      ToastService.showError('Please select a file first');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final title = _titleController.text.trim();

    if (!mounted) return;
    setState(() => _isUploading = true);

    final success = await widget.onAddLesson(
      title,
      _selectedFile!,
      (_) {},
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.lessonType == LessonType.video;
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Text(
            isVideo ? 'Upload Video' : 'Upload Resource',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          UploadZone(
            cs: cs,
            isDark: isDark,
            isPicking: _isPicking,
            onTap: _isUploading || _isPicking ? null : _pickFile,
            selectedFileName: _selectedFile?.name,
            label: isVideo ? 'Upload Video File' : 'Upload Resource',
            iconData: isVideo
                ? Icons.cloud_upload_outlined
                : Icons.description_outlined,
          ),
          const SizedBox(height: 20),
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
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _titleController,
                builder: (_, val, _) => Text(
                  '${val.text.length}/60',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Form(
            key: _formKey,
            child: TextFormField(
            controller: _titleController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            maxLines: 4,
            maxLength: 60,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
            style: TextStyle(color: cs.onSurface),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter a title';
              return null;
            },
            decoration: InputDecoration(
              hintText: isVideo
                  ? 'Enter your video title'
                  : 'Enter your resource title',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(
                  color: isDark
                      ? cs.outlineVariant
                      : const Color(0xFFEFEFF0),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
            ),
          ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isUploading ? null : _handleUpload,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _isUploading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isVideo ? 'Upload Video' : 'Upload Resource',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
