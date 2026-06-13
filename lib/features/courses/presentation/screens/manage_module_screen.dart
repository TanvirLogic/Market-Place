import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/widgets/swipe_action_widget.dart';
import 'package:edtech/features/courses/presentation/models/manage_module_models.dart';
import 'package:edtech/features/courses/presentation/widgets/module_card.dart';

int _nextModuleId = 1;
int _nextLessonId = 1;

class ManageModuleScreen extends StatefulWidget {
  const ManageModuleScreen({super.key});
  static const String name = '/manage-module';

  @override
  State<ManageModuleScreen> createState() => _ManageModuleScreenState();
}

class _ManageModuleScreenState extends State<ManageModuleScreen> {
  final List<CourseModule> _modules = [
    CourseModule(
      id: _nextModuleId++,
      title: "Getting Started with Web Development",
      lessons: [],
      isExpanded: false,
    ),
  ];
  bool _isEditing = false;
  bool _hasUnsavedChanges = false;
  final ValueNotifier<int> _resetNotifier = ValueNotifier(0);

  List<Map<String, dynamic>> getSerializedOrder() {
    return _modules.asMap().entries.map((entry) {
      final module = entry.value;
      return {
        'module_id': module.id,
        'sort_order': entry.key,
        'title': module.title,
        'lessons': module.lessons.asMap().entries.map((le) {
          return {
            'lesson_id': le.value.id,
            'sort_order': le.key,
            'title': le.value.title,
            'type': le.value.type.name,
          };
        }).toList(),
      };
    }).toList();
  }

  void _saveOrder() {
    final serialized = getSerializedOrder();
    debugPrint('Saving order: $serialized');
    setState(() => _hasUnsavedChanges = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Module order saved')));
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

  void _addLessonToModule(int moduleIndex, LessonType type) {
    setState(() {
      if (type == LessonType.video) {
        _modules[moduleIndex].lessons.add(
          Lesson(
            id: _nextLessonId++,
            title: "Setting Up Your Environment",
            duration: "18:20",
            type: LessonType.video,
          ),
        );
      } else {
        _modules[moduleIndex].lessons.add(
          Lesson(
            id: _nextLessonId++,
            title: "HTML Fundamentals",
            duration: "18:20",
            type: LessonType.resource,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final iconBg = isDark
        ? cs.surfaceContainerHighest
        : const Color(0xFFF5F5F5);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _resetNotifier.value++,
              onVerticalDragDown: (_) => _resetNotifier.value++,
              child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderImage(cs, iconBg),
                  _buildCourseMeta(cs),
                  _buildDescriptionSection("Description", cs),
                  _buildDescriptionSection("Requirements", cs),
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
                  _buildModulesList(cs, isDark),
                ],
              ),
            ),
          ),
        ),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
        ],
      ),
    );
  }

  Widget _buildHeaderImage(ColorScheme cs, Color iconBg) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: 195,
          width: double.infinity,
          child: CachedNetworkImage(
            imageUrl:
                'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe',
            fit: BoxFit.cover,
          ),
        ),
        Container(
          height: 195,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.white.withValues(alpha: 0.0),
                cs.brightness == Brightness.dark
                    ? Theme.of(context).scaffoldBackgroundColor
                    : Colors.white,
              ],
              stops: const [0.0, 0.85, 1.0],
            ),
          ),
        ),
        Positioned(top: 48, left: 12, child: const AppBackButton()),
        Positioned(
          top: 48,
          right: 12,
          child: CircleAvatar(
            backgroundColor: iconBg,
            child: IconButton(
              icon: _isEditing
                  ? const Icon(Icons.check, size: 20)
                  : Padding(
                      padding: const EdgeInsets.all(3),
                      child: SvgPicture.asset(
                        Images.edit_profile,
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(
                          cs.onSurface,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
              onPressed: () {
                setState(() => _isEditing = !_isEditing);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCourseMeta(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "App Development with flutter & AI",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "With 70 live classes, you'll learn everything from the very basics to advanced levels of app development!",
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTag(Images.languageIcon, "Bangla", cs),
              const SizedBox(width: 12),
              _buildTag(Images.bookNoC, "Advanced", cs),
              const SizedBox(width: 12),
              _buildTag(Images.dollar, "Paid", cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String assetPath, String label, ColorScheme cs) {
    return Row(
      children: [
        SvgPicture.asset(
          assetPath,
          width: 16,
          height: 16,
          colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionSection(String title, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text:
                  "Passionate educator with over a decade of industry experience. Helping aspiring ",
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: "See More...",
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModulesList(ColorScheme cs, bool isDark) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _modules.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final module = _modules.removeAt(oldIndex);
          _modules.insert(newIndex, module);
          _hasUnsavedChanges = true;
        });
      },
      proxyDecorator: (child, index, animation) {
        final module = _modules[index];
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
        final module = _modules[index];
        return Padding(
          key: ValueKey('module_${module.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: SwipeActionWidget(
              editIcon: SvgPicture.asset(
                Images.edit_profile,
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
              ),
              resetNotifier: _resetNotifier,
              onDelete: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text('Delete Module', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    content: Text('Delete "${module.title}"?', style: TextStyle(fontSize: 14, color: cs.onSurface)),
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
                if (confirmed == true && mounted) {
                  setState(() {
                    _modules.removeAt(index);
                    _hasUnsavedChanges = true;
                  });
                }
                return confirmed == true;
              },
              onEdit: () => _showRenameDialog(module.title, (newName) {
                setState(() {
                  module.title = newName;
                  _hasUnsavedChanges = true;
                });
              }),
              child: ModuleCard(
              resetNotifier: _resetNotifier,
              module: module,
              isDark: isDark,
              isEditing: _isEditing,
              onToggleExpand: () => setState(() => module.isExpanded = !module.isExpanded),
              onRename: (newName) => setState(() {
                module.title = newName;
                _hasUnsavedChanges = true;
              }),
              onShowRenameDialog: _showRenameDialog,
              onAddVideo: () => _addLessonToModule(index, LessonType.video),
              onAddResource: () => _addLessonToModule(index, LessonType.resource),
              onReorderLesson: (oldLessonIndex, newLessonIndex) {
                setState(() {
                  if (newLessonIndex > oldLessonIndex) newLessonIndex--;
                  final lesson = module.lessons.removeAt(oldLessonIndex);
                  module.lessons.insert(newLessonIndex, lesson);
                  _hasUnsavedChanges = true;
                });
              },
              onRenameLesson: (lessonIndex, newName) {
                setState(() {
                  module.lessons[lessonIndex].title = newName;
                  _hasUnsavedChanges = true;
                });
              },
              onDeleteLesson: (lessonIndex) {
                setState(() {
                  module.lessons.removeAt(lessonIndex);
                  _hasUnsavedChanges = true;
                });
              },
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: _hasUnsavedChanges
          ? Row(
              children: [
                Expanded(
                  flex: 3,
                  child: AuthButton(
                    text: "Add Module",
                    height: 50,
                    borderRadius: 24,
                    fontSize: 14,
                    onPressed: () {
                      _resetNotifier.value++;
                      setState(() {
                        _modules.add(
                          CourseModule(
                            id: _nextModuleId++,
                            title: "New Dynamic Module #${_modules.length + 1}",
                            lessons: [],
                            isExpanded: true,
                          ),
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        side: BorderSide(color: cs.primary),
                      ),
                      onPressed: () {
                        _resetNotifier.value++;
                        _saveOrder();
                      },
                      child: Text(
                        "Save Changes",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : AuthButton(
              text: "Add Module",
              height: 50,
              borderRadius: 24,
              onPressed: () {
                _resetNotifier.value++;
                setState(() {
                  _modules.add(
                    CourseModule(
                      id: _nextModuleId++,
                      title: "New Dynamic Module #${_modules.length + 1}",
                      lessons: [],
                      isExpanded: true,
                    ),
                  );
                });
              },
            ),
    );
  }
}
