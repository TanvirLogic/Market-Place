import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/widgets/swipe_action_widget.dart';
import 'package:edtech/features/manage_module/data/manage_module_models.dart';
import 'package:edtech/features/manage_module/presentation/widgets/module_card.dart';

class ManageModuleList extends StatelessWidget {
  final List<CourseModule> modules;
  final bool isDark;
  final ColorScheme cs;
  final ValueNotifier<bool> Function(int moduleId) revealNotifier;
  final ValueNotifier<int> resetNotifier;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Future<bool> Function(CourseModule module, int index) onDeleteModule;
  final void Function(CourseModule module) onEditModule;
  final void Function(CourseModule module) onToggleExpand;
  final void Function(CourseModule module, String newName) onRename;
  final void Function(String currentName, ValueChanged<String> onSaved) onShowRenameDialog;
  final void Function(int index) onAddVideo;
  final void Function(int index) onAddResource;
  final void Function(CourseModule module, int oldLessonIndex, int newLessonIndex) onReorderLesson;
  final Future<void> Function(CourseModule module, int lessonIndex, String newName) onRenameLesson;
  final Future<bool> Function(CourseModule module, int lessonIndex) onDeleteLesson;
  final void Function(CourseModule module, int lessonIndex) onEditLesson;
  final void Function(String videoUrl, String title) onTapVideo;
  final void Function(String fileUrl, String title) onTapResource;
  final List<PendingLesson> Function(int moduleId) pendingLessonsForModule;
  final Future<void> Function(int queueId) onDeletePendingLesson;
  final Future<void> Function(int queueId) onRetryPendingLesson;

  const ManageModuleList({
    super.key,
    required this.modules,
    required this.isDark,
    required this.cs,
    required this.revealNotifier,
    required this.resetNotifier,
    required this.onReorder,
    required this.onDeleteModule,
    required this.onEditModule,
    required this.onToggleExpand,
    required this.onRename,
    required this.onShowRenameDialog,
    required this.onAddVideo,
    required this.onAddResource,
    required this.onReorderLesson,
    required this.onRenameLesson,
    required this.onDeleteLesson,
    required this.onEditLesson,
    required this.onTapVideo,
    required this.onTapResource,
    required this.pendingLessonsForModule,
    required this.onDeletePendingLesson,
    required this.onRetryPendingLesson,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modules.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onReorderItem: onReorder,
      proxyDecorator: (child, index, animation) {
        final module = modules[index];
        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainerLow : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE3E3E4)),
            ),
            child: Text(
              module.title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
      itemBuilder: (context, index) {
        final module = modules[index];
        return Padding(
          key: ValueKey('module_${module.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: SwipeActionWidget(
              revealNotifier: revealNotifier(module.id),
              editIcon: SvgPicture.asset(
                Images.editProfile,
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
              ),
              resetNotifier: resetNotifier,
              onDelete: () => onDeleteModule(module, index),
              onEdit: () => onEditModule(module),
              child: ListenableBuilder(
                listenable: revealNotifier(module.id),
                builder: (context, _) => ModuleCard(
                  revealed: revealNotifier(module.id).value,
                  resetNotifier: resetNotifier,
                  module: module,
                  isDark: isDark,
                  isEditing: false,
                  pendingLessons: pendingLessonsForModule(module.id),
                  onDeletePendingLesson: onDeletePendingLesson,
                  onRetryPendingLesson: onRetryPendingLesson,
                  onToggleExpand: () => onToggleExpand(module),
                  onRename: (newName) => onRename(module, newName),
                  onShowRenameDialog: onShowRenameDialog,
                  onAddVideo: () => onAddVideo(index),
                  onAddResource: () => onAddResource(index),
                  onReorderLesson: (oldLessonIndex, newLessonIndex) => onReorderLesson(module, oldLessonIndex, newLessonIndex),
                  onRenameLesson: (lessonIndex, newName) => onRenameLesson(module, lessonIndex, newName),
                  onDeleteLesson: (lessonIndex) => onDeleteLesson(module, lessonIndex),
                  onEditLesson: (lessonIndex) => onEditLesson(module, lessonIndex),
                  onTapVideo: onTapVideo,
                  onTapResource: onTapResource,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
