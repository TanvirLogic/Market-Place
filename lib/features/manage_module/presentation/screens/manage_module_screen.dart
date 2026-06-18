import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:edtech/features/manage_module/providers/manage_module_provider.dart';
import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_header.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_meta.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_description.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_list.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_bottom_bar.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_add_lesson_sheet.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_edit_course_sheet.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_add_module_sheet.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_edit_module_sheet.dart';
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_edit_lesson_sheet.dart';

class ManageModuleScreen extends StatelessWidget {
  final int courseId;
  const ManageModuleScreen({super.key, this.courseId = 0});
  static const String name = '/manage-module';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ManageModuleProvider(courseId: courseId),
      child: const _ManageModuleBody(),
    );
  }
}

class _ManageModuleBody extends StatefulWidget {
  const _ManageModuleBody();

  @override
  State<_ManageModuleBody> createState() => _ManageModuleBodyState();
}

class _ManageModuleBodyState extends State<_ManageModuleBody> {
  final ValueNotifier<int> _resetNotifier = ValueNotifier(0);
  final Map<int, ValueNotifier<bool>> _revealNotifiers = {};

  ValueNotifier<bool> _revealNotifier(int moduleId) {
    return _revealNotifiers.putIfAbsent(moduleId, () => ValueNotifier(false));
  }

  void _showRenameDialog(String currentName, ValueChanged<String> onSaved) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            final newName = controller.text.trim();
            if (newName.isNotEmpty) {
              onSaved(newName);
              Navigator.pop(context);
            }
          },
          decoration: const InputDecoration(hintText: 'Enter new name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                onSaved(newName);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final iconBg = isDark
        ? cs.surfaceContainerHighest
        : const Color(0xFFF5F5F5);

    return Consumer<ManageModuleProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  onRefresh: provider.refresh,
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManageModuleHeader(
                        cs: cs,
                        iconBg: iconBg,
                        thumbnailUrl: provider.courseThumbnailUrl,
                        onEditCourse: () => ManageModuleEditCourseSheet.show(
                          context,
                          courseId: provider.courseId,
                          onSave: provider.updateCourse,
                        ),
                      ),
                      ManageModuleMeta(
                        title: provider.courseTitle,
                        shortDescription: provider.courseShortDescription,
                        language: provider.courseLanguage,
                        level: provider.courseLevel,
                        type: provider.courseType,
                      ),
                      ManageModuleDescription(
                        title: "Description",
                        text: provider.courseDescription,
                      ),
                      ManageModuleDescription(
                        title: "Requirements",
                        text: provider.courseRequirements,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Divider(
                          color: const Color(0xFFE3E3E4),
                          thickness: 1.0,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "Swipe left to delete or edit",
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ManageModuleList(
                        modules: provider.modules,
                        isDark: isDark,
                        cs: cs,
                        revealNotifier: _revealNotifier,
                        resetNotifier: _resetNotifier,
                        onReorder: provider.reorderModule,
                        onDeleteModule: (module, index) async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(
                                'Delete Module',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              content: Text(
                                'Delete "${module.title}"?',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: cs.error),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            return provider.deleteModule(module);
                          }
                          return false;
                        },
                        onEditModule: (module) =>
                            ManageModuleEditModuleSheet.show(
                              context,
                              module: module,
                              onSave: (title) async {
                                final success = await provider.editModule(
                                  module,
                                  title,
                                );
                                if (success) _resetNotifier.value++;
                                return success;
                              },
                            ),
                        onToggleExpand: provider.toggleExpand,
                        onRename: provider.renameModule,
                        onShowRenameDialog: _showRenameDialog,
                        onAddVideo: (index) => ManageModuleAddLessonSheet.show(
                          context,
                          lessonType: LessonType.video,
                          moduleId: provider.modules[index].id,
                          courseId: provider.courseId,
                          onAddLesson: (title, file, onProgress) =>
                              provider.addVideoLesson(
                                index,
                                title,
                                file,
                                onProgress: onProgress,
                              ),
                        ),
                        onAddResource: (index) =>
                            ManageModuleAddLessonSheet.show(
                              context,
                              lessonType: LessonType.resource,
                              moduleId: provider.modules[index].id,
                              courseId: provider.courseId,
                              onAddLesson: (title, file, _) =>
                                  provider.addResourceLesson(
                                    index,
                                    title,
                                    file,
                                  ),
                            ),
                        onReorderLesson: provider.reorderLesson,
                        onRenameLesson: provider.renameLesson,
                        onDeleteLesson: provider.deleteLesson,
                        onEditLesson: (module, lessonIndex) =>
                            ManageModuleEditLessonSheet.show(
                              context,
                              lesson: module.lessons[lessonIndex],
                              onSave: (title) => provider.renameLesson(
                                module,
                                lessonIndex,
                                title,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ManageModuleBottomBar(
                  hasUnsavedChanges: provider.hasUnsavedChanges,
                  onAddModule: () => ManageModuleAddModuleSheet.show(
                    context,
                    onAddModule: provider.addModule,
                  ),
                  onSaveOrder: () {
                    _resetNotifier.value++;
                    provider.saveOrder();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
