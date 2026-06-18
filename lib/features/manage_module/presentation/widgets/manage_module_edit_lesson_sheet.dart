import 'package:flutter/material.dart';
import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';

class ManageModuleEditLessonSheet extends StatefulWidget {
  final Lesson lesson;
  final Future<bool> Function(String title) onSave;

  const ManageModuleEditLessonSheet({
    super.key,
    required this.lesson,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    required Lesson lesson,
    required Future<bool> Function(String title) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          ManageModuleEditLessonSheet(lesson: lesson, onSave: onSave),
    );
  }

  @override
  State<ManageModuleEditLessonSheet> createState() =>
      _ManageModuleEditLessonSheetState();
}

class _ManageModuleEditLessonSheetState
    extends State<ManageModuleEditLessonSheet> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.lesson.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Edit Lesson',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
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
            TextFormField(
              controller: _titleController,
              maxLines: 4,
              maxLength: 60,
              buildCounter:
                  (_, {required currentLength, required isFocused, maxLength}) =>
                      null,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Enter lesson title',
                hintStyle:
                    TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 14),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(
                    color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AuthButton(
              text: 'Save Changes',
              borderRadius: 24,
              onPressed: () async {
                final title = _titleController.text.trim();
                if (title.isEmpty || title == widget.lesson.title) {
                  Navigator.of(context).pop();
                  return;
                }
                final success = await widget.onSave(title);
                if (success && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
