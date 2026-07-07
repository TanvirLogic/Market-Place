import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edtech/features/uploads/presentation/upload_queue_provider.dart';
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
import 'package:edtech/features/manage_module/presentation/widgets/manage_module_shimmer.dart';
import 'package:edtech/global/core/widgets/app_alert_dialog.dart';
import 'package:edtech/app/app_routes.dart' show routeObserver;
import 'package:edtech/global/core/providers/video_player_provider.dart';
import 'package:edtech/features/profile/student/presentation/widgets/video_player_screen.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';

class ManageModuleScreen extends StatelessWidget {
  final int courseId;
  const ManageModuleScreen({super.key, this.courseId = 0});
  static const String name = '/manage-module';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => ManageModuleProvider(
        courseId: courseId,
        queueProvider: ctx.read<UploadQueueProvider>(),
      ),
      child: const _ManageModuleBody(),
    );
  }
}

class _ManageModuleBody extends StatefulWidget {
  const _ManageModuleBody();

  @override
  State<_ManageModuleBody> createState() => _ManageModuleBodyState();
}

class _ManageModuleBodyState extends State<_ManageModuleBody> with RouteAware {
  final ValueNotifier<int> _resetNotifier = ValueNotifier(0);
  final Map<int, ValueNotifier<bool>> _revealNotifiers = {};

  ValueNotifier<bool> _revealNotifier(int moduleId) {
    return _revealNotifiers.putIfAbsent(moduleId, () => ValueNotifier(false));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPushNext() {
    context.read<VideoPlayerProvider>().pause();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    context.read<VideoPlayerProvider>().dismiss();
    super.dispose();
  }

  Future<void> _showRenameDialog(
    String currentName,
    ValueChanged<String> onSaved,
  ) async {
    final value = await AppAlertDialog.showInput(
      context: context,
      title: 'Rename',
      initialValue: currentName,
      hintText: 'Enter new name',
    );
    if (value != null && value.isNotEmpty) {
      onSaved(value);
    }
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
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            context.read<VideoPlayerProvider>().dismiss();
          },
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: RefreshIndicator(
                    onRefresh: provider.refresh,
                    child: provider.isLoading
                        ? const ManageModuleShimmer()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 100),
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ManageModuleHeader(
                                  cs: cs,
                                  iconBg: iconBg,
                                  thumbnailUrl: provider.courseThumbnailUrl,
                                  onEditCourse: () =>
                                      ManageModuleEditCourseSheet.show(
                                        context,
                                        courseId: provider.courseId,
                                        courseTitle: provider.courseTitle,
                                        courseShortDescription:
                                            provider.courseShortDescription,
                                        courseDescription:
                                            provider.courseDescription,
                                        courseRequirements:
                                            provider.courseRequirements,
                                        courseLanguage: provider.courseLanguage,
                                        courseLevel: provider.courseLevel,
                                        courseType: provider.courseType,
                                        coursePrice: provider.coursePrice,
                                        courseThumbnailUrl:
                                            provider.courseThumbnailUrl,
                                        courseIntroVideoUrl:
                                            provider.courseIntroVideoUrl,
                                        onSave: provider.updateCourse,
                                        onCourseRefreshed: provider.refresh,
                                      ),
                                ),
                                ManageModuleMeta(
                                  title: provider.courseTitle,
                                  shortDescription:
                                      provider.courseShortDescription,
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                  ),
                                  child: Divider(
                                    color: const Color(0xFFE3E3E4),
                                    thickness: 1.0,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    "Swipe left to delete or edit",
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
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
                                    final confirmed = await AppAlertDialog.show(
                                      context: context,
                                      title: 'Delete Module',
                                      content: 'Delete "${module.title}"?',
                                      confirmText: 'Delete',
                                      cancelText: 'Cancel',
                                    );
                                    if (confirmed == true) {
                                      final ok = await provider.deleteModule(
                                        module,
                                      );
                                      if (ok) await provider.refresh();
                                      return ok;
                                    }
                                    return false;
                                  },
                                  onEditModule: (module) =>
                                      ManageModuleEditModuleSheet.show(
                                        context,
                                        module: module,
                                        onSave: (title) async {
                                          final success = await provider
                                              .editModule(module, title);
                                          if (success) _resetNotifier.value++;
                                          return success;
                                        },
                                      ),
                                  onToggleExpand: provider.toggleExpand,
                                  onRename: provider.renameModule,
                                  onShowRenameDialog: _showRenameDialog,
                                  pendingLessonsForModule:
                                      provider.pendingLessonsForModule,
                                  onDeletePendingLesson: (queueId) =>
                                      provider.deletePendingLesson(queueId),
                                  onAddVideo: (index) =>
                                      ManageModuleAddLessonSheet.show(
                                        context,
                                        lessonType: LessonType.video,
                                        moduleId: provider.modules[index].id,
                                        courseId: provider.courseId,
                                        onAddLesson: (title, file) =>
                                            provider.addVideoLesson(
                                              index,
                                              title,
                                              file,
                                            ),
                                      ),
                                  onAddResource: (index) =>
                                      ManageModuleAddLessonSheet.show(
                                        context,
                                        lessonType: LessonType.resource,
                                        moduleId: provider.modules[index].id,
                                        courseId: provider.courseId,
                                        onAddLesson: (title, file) =>
                                            provider.addResourceLesson(
                                              index,
                                              title,
                                              file,
                                            ),
                                      ),
                                  onReorderLesson: provider.reorderLesson,
                                  onRenameLesson: provider.renameLesson,
                                  onDeleteLesson: provider.deleteLesson,
                                  onEditLesson: (module, lessonIndex) {
                                    final lesson = module.lessons[lessonIndex];
                                    ManageModuleEditLessonSheet.show(
                                      context,
                                      lesson: lesson,
                                      onSave: (title) => provider.renameLesson(
                                        module,
                                        lessonIndex,
                                        title,
                                      ),
                                    );
                                  },
                                  onTapVideo: (videoUrl, title) {
                                    if (videoUrl.isEmpty) {
                                      ToastService.showError(
                                        'Video URL not available',
                                      );
                                      return;
                                    }
                                    try {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => VideoPlayerScreen(
                                            videoUrl: videoUrl,
                                            title: title,
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      AppLogger.e(
                                        'onTapVideo navigation error: $e',
                                      );
                                      ToastService.showError(
                                        'Could not open video player',
                                      );
                                    }
                                  },
                                  onTapResource: (fileUrl, title) {
                                    if (fileUrl.isEmpty) {
                                      ToastService.showError(
                                        'Resource URL not available',
                                      );
                                      return;
                                    }
                                    try {
                                      launchUrl(
                                        Uri.parse(fileUrl),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } catch (e) {
                                      AppLogger.e(
                                        'onTapResource launchUrl error: $e',
                                      );
                                      ToastService.showError(
                                        'Could not open resource',
                                      );
                                    }
                                  },
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
                    onAddModule: () => ManageModuleAddModuleSheet.show(
                      context,
                      onAddModule: provider.addModule,
                    ),
                    onPublish: () {
                      _resetNotifier.value++;
                      provider.saveOrder();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
