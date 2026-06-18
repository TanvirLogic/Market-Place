import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/widgets/swipe_action_widget.dart';
import 'package:edtech/features/manage_module/data/manage_module_models.dart';

class ModuleCard extends StatelessWidget {
  final CourseModule module;
  final bool isDark;
  final bool isEditing;
  final bool revealed;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onRename;
  final void Function(String, ValueChanged<String>) onShowRenameDialog;
  final VoidCallback onAddVideo;
  final VoidCallback onAddResource;
  final void Function(int, int) onReorderLesson;
  final void Function(int, String) onRenameLesson;
  final Future<bool> Function(int) onDeleteLesson;
  final void Function(int) onEditLesson;

  final ValueNotifier<int>? resetNotifier;

  const ModuleCard({
    super.key,
    required this.module,
    required this.isDark,
    required this.isEditing,
    this.revealed = false,
    required this.onToggleExpand,
    required this.onRename,
    required this.onShowRenameDialog,
    required this.onAddVideo,
    required this.onAddResource,
    required this.onReorderLesson,
    required this.onRenameLesson,
    required this.onDeleteLesson,
    required this.onEditLesson,
    this.resetNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: revealed ? BorderRadius.zero : BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E3E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (isEditing) ...[
                    GestureDetector(
                      onTap: () => onShowRenameDialog(module.title, onRename),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SvgPicture.asset(
                          Images.editProfile,
                          width: 16,
                          height: 16,
                          colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: isEditing ? () => onShowRenameDialog(module.title, onRename) : null,
                          child: Text(
                            module.title,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cs.onSurface),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${module.lessons.length} lessons",
                          style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                  if (!revealed)
                    Icon(
                      module.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: cs.onSurface,
                    ),
                ],
              ),
            ),
          ),
          if (module.isExpanded) ...[
            Container(height: 1, color: const Color(0xFFE3E3E4)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ActionButton(label: "Add Video", onPressed: onAddVideo),
                      const SizedBox(width: 8),
                      _ActionButton(label: "Add Resource", onPressed: onAddResource),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (module.lessons.isNotEmpty)
                    ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: module.lessons.length,
                      onReorder: onReorderLesson,
                      proxyDecorator: (child, index, animation) => AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) => Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        ),
                        child: child,
                      ),
                      itemBuilder: (context, lessonIndex) {
                        final lesson = module.lessons[lessonIndex];
                        return Padding(
                          key: ValueKey('lesson_${lesson.id}'),
                          padding: EdgeInsets.only(top: lessonIndex > 0 ? 4 : 0),
                          child: ReorderableDelayedDragStartListener(
                            index: lessonIndex,
                            child: _LessonSwipeRow(
                              lesson: lesson,
                              lessonIndex: lessonIndex,
                              isDark: isDark,
                              isEditing: isEditing,
                              resetNotifier: resetNotifier,
                              onDeleteLesson: onDeleteLesson,
                              onRenameLesson: onRenameLesson,
                              onShowRenameDialog: onShowRenameDialog,
                              onEditLesson: onEditLesson,
                            ),
                          ),
                        );
                        },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.themeColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _LessonSwipeRow extends StatefulWidget {
  final Lesson lesson;
  final int lessonIndex;
  final bool isDark;
  final bool isEditing;
  final ValueNotifier<int>? resetNotifier;
  final Future<bool> Function(int) onDeleteLesson;
  final void Function(int, String) onRenameLesson;
  final void Function(String, ValueChanged<String>) onShowRenameDialog;
  final void Function(int) onEditLesson;

  const _LessonSwipeRow({
    required this.lesson,
    required this.lessonIndex,
    required this.isDark,
    required this.isEditing,
    this.resetNotifier,
    required this.onDeleteLesson,
    required this.onRenameLesson,
    required this.onShowRenameDialog,
    required this.onEditLesson,
  });

  @override
  State<_LessonSwipeRow> createState() => _LessonSwipeRowState();
}

class _LessonSwipeRowState extends State<_LessonSwipeRow> {
  final ValueNotifier<bool> _revealNotifier = ValueNotifier(false);

  @override
  void dispose() {
    _revealNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lesson = widget.lesson;
    final lessonIndex = widget.lessonIndex;

    return SwipeActionWidget(
      revealNotifier: _revealNotifier,
      editIcon: SvgPicture.asset(
        Images.editProfile,
        width: 20,
        height: 20,
        colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
      ),
      resetNotifier: widget.resetNotifier,
      onDelete: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Delete Lesson', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
            content: Text('Delete "${lesson.title}"?', style: TextStyle(fontSize: 14, color: cs.onSurface)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Delete', style: TextStyle(color: cs.error)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          return await widget.onDeleteLesson(lessonIndex);
        }
        return false;
      },
      onEdit: () => widget.onEditLesson(widget.lessonIndex),
      child: ListenableBuilder(
        listenable: _revealNotifier,
        builder: (context, _) {
          final isRevealed = _revealNotifier.value;
          final borderRadius = isRevealed
              ? BorderRadius.zero
              : BorderRadius.circular(12);

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isDark ? cs.surfaceContainerHighest : const Color(0xFFF8F9FA),
              borderRadius: borderRadius,
              border: Border.all(color: const Color(0xFFEFEFF0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.isDark ? cs.surfaceContainerLow : const Color(0xFFEAEBFE),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      lesson.type == LessonType.video
                          ? Images.learnVideo
                          : Images.resource,
                      width: 16,
                      height: 16,
                      colorFilter: ColorFilter.mode(cs.onSurface, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.isEditing) ...[
                  GestureDetector(
                    onTap: () => widget.onShowRenameDialog(
                      lesson.title,
                      (newName) => widget.onRenameLesson(lessonIndex, newName),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SvgPicture.asset(
                        Images.editProfile,
                        width: 14,
                        height: 14,
                        colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: GestureDetector(
                    onTap: widget.isEditing ? () => widget.onShowRenameDialog(
                      lesson.title,
                      (newName) => widget.onRenameLesson(lessonIndex, newName),
                    ) : null,
                    child: Text(
                      lesson.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  lesson.duration,
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 18, color: cs.onSurface),
              ],
            ),
          );
        },
      ),
    );
  }
}
