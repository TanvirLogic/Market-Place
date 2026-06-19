import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/widgets/shimmer_widget.dart';
import 'package:edtech/features/profile/student/presentation/widgets/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/entities/course_entity.dart';
import '../../data/entities/module_entity.dart';
import 'package:edtech/features/courses/providers/course_detail_provider.dart';
import '../widgets/course_expandable_container.dart';
import '../widgets/course_reviews_tab_view.dart';
import '../widgets/course_stats_row.dart';
import '../widgets/instructor_profile_card.dart';
import '../widgets/lesson_row_tile.dart';

class CourseDetailsScreen extends StatelessWidget {
  final int courseId;
  const CourseDetailsScreen({Key? key, this.courseId = 0}) : super(key: key);
  static const String name = '/course-details';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CourseDetailProvider()..loadCourse(courseId),
      child: _CourseDetailsBody(courseId: courseId),
    );
  }
}

class _CourseDetailsBody extends StatefulWidget {
  final int courseId;
  const _CourseDetailsBody({required this.courseId});

  @override
  State<_CourseDetailsBody> createState() => _CourseDetailsBodyState();
}

class _CourseDetailsBodyState extends State<_CourseDetailsBody> {
  Player? _player;
  VideoController? _videoController;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CourseDetailProvider>().loadCourse(widget.courseId);
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _playIntroVideo(String url) {
    _player?.dispose();
    _player = null;
    _videoController = null;
    _isInitialized = false;
    _isPlaying = false;
    _hasError = false;

    final player = Player();
    _player = player;
    _videoController = VideoController(player);

    player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _isPlaying = playing;
        _showControls = true;
      });
    });

    player.stream.error.listen((_) {
      if (mounted) setState(() => _hasError = true);
    });

    player.open(Media(url)).then((_) => player.play()).catchError((_) {
      if (mounted) setState(() => _hasError = true);
    });
  }

  void _stopIntroVideo() {
    _player?.pause();
    _player?.dispose();
    _player = null;
    _videoController = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _isPlaying = false;
        _hasError = false;
      });
    }
  }

  void _togglePlayPause() {
    if (_player == null || !_isInitialized) return;
    if (_isPlaying) {
      _player!.pause();
      setState(() => _isPlaying = false);
    } else {
      _player!.play();
      setState(() => _isPlaying = true);
    }
  }

  void _openFullScreen(String url, String title) {
    _player?.pause();
    setState(() => _isPlaying = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(videoUrl: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Consumer<CourseDetailProvider>(
      builder: (context, provider, _) {
        final course = provider.course;
        if (course == null) {
          return Scaffold(
            appBar: _buildAppBar(context, cs, isDark),
            body: provider.errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: cs.error),
                        const SizedBox(height: 12),
                        Text(
                          provider.errorMessage!,
                          style: TextStyle(color: cs.error),
                        ),
                        const SizedBox(height: 12),
                        AuthButton(
                          text: 'Retry',
                          onPressed: () => provider.loadCourse(
                            course?.id ?? widget.courseId,
                          ),
                        ),
                      ],
                    ),
                  )
                : const _CourseDetailsSkeleton(),
          );
        }

        return Scaffold(
          appBar: _buildAppBar(context, cs, isDark),
          body: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSizes.horizontalPadding,
                    8,
                    AppSizes.horizontalPadding,
                    110,
                  ),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildThumbnail(cs, isDark, course),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? cs.surfaceContainerLow : Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusLg,
                          ),
                          border: Border.all(
                            color: isDark
                                ? cs.outlineVariant
                                : AppColors.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              course.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              course.shortDescription.isNotEmpty
                                  ? course.shortDescription
                                  : course.description,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            CourseStatsRow(
                              videosCount: '${course.totalLessons} Video',
                              resourcesCount:
                                  '${course.totalResources} Resource',
                              isDark: isDark,
                              cs: cs,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _CourseTabContentView(
                        course: course,
                        isDark: isDark,
                        cs: cs,
                      ),
                    ],
                  ),
                ),
              ),
              if (!course.isStudent)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _BottomEnrollmentBar(
                    price: course.type == 'PAID'
                        ? '\u09F3${course.price.toStringAsFixed(2)}'
                        : 'Free',
                    isDark: isDark,
                    cs: cs,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ColorScheme cs,
    bool isDark,
  ) {
    return AppBar(
      leading: const Padding(
        padding: EdgeInsets.only(left: 8),
        child: AppBackButton(),
      ),
      title: Image.asset(Images.eduverseP, width: 113, height: 32),
      centerTitle: true,
    );
  }

  Widget _buildThumbnail(ColorScheme cs, bool isDark, CourseEntity course) {
    final hasIntroVideo = course.introVideoUrl.isNotEmpty;

    if (_isInitialized && _player != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          child: SizedBox(
            height: 184,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_hasError)
                    const Center(
                      child: Icon(
                        Icons.videocam_off,
                        color: Colors.white54,
                        size: 32,
                      ),
                    )
                  else
                    Video(
                      controller: _videoController!,
                      fit: BoxFit.contain,
                      controls: null,
                    ),
                  if (_showControls) ...[
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _stopIntroVideo,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () =>
                            _openFullScreen(course.introVideoUrl, course.title),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: hasIntroVideo
            ? () => _playIntroVideo(course.introVideoUrl)
            : null,
        child: SizedBox(
          height: 184,
          child: Stack(
            children: [
              if (course.thumbnailUrl.isNotEmpty)
                Image.network(
                  course.thumbnailUrl,
                  width: double.infinity,
                  height: 184,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 184,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.6),
                          cs.primary.withValues(alpha: 0.2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  height: 184,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.6),
                        cs.primary.withValues(alpha: 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? cs.surfaceContainerHighest : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'by ${course.mentorName}',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      (isDark ? cs.surfaceContainerHighest : Colors.white)
                          .withValues(alpha: 0.9),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 36,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseTabContentView extends StatefulWidget {
  final CourseEntity course;
  final bool isDark;
  final ColorScheme cs;

  const _CourseTabContentView({
    required this.course,
    required this.isDark,
    required this.cs,
  });

  @override
  State<_CourseTabContentView> createState() => _CourseTabContentViewState();
}

class _CourseTabContentViewState extends State<_CourseTabContentView> {
  int _activeIndex = 0;
  final List<String> _tabs = ['Overview', 'Module', 'Reviews'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = widget.isDark;
    final cs = widget.cs;
    final course = widget.course;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_tabs.length, (index) {
            final isSelected = _activeIndex == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeIndex = index),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected
                            ? AppColors.themeColor
                            : (isDark
                                  ? cs.outlineVariant
                                  : const Color(0xFFEFEFF0)),
                        width: isSelected ? 2.5 : 1.0,
                      ),
                    ),
                  ),
                  child: Text(
                    _tabs[index],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSelected
                          ? AppColors.themeColor
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.6)
                                : AppColors.primaryText),
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        if (_activeIndex == 0) ..._overviewContent(isDark, cs, course),
        if (_activeIndex == 1)
          _NativeModuleTabView(
            modules: course.modules,
            isDark: isDark,
            cs: cs,
            isStudent: course.isStudent,
          ),
        if (_activeIndex == 2)
          CourseReviewsTabView(
            reviews: course.reviews,
            isDark: isDark,
            cs: cs,
            courseId: course.id,
          ),
      ],
    );
  }

  List<Widget> _overviewContent(
    bool isDark,
    ColorScheme cs,
    CourseEntity course,
  ) {
    final requirements = course.requirements.isNotEmpty
        ? course.requirements
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList()
        : <String>[];

    return [
      InstructorProfileCard(
        isDark: isDark,
        cs: cs,
        mentorName: course.mentorName,
        avatarUrl: course.mentorAvatarUrl,
      ),
      const SizedBox(height: 16),
      CourseExpandableContainer(
        isDark: isDark,
        cs: cs,
        title: 'Description',
        child: Text(
          '\u2022  ${course.description.isNotEmpty ? course.description : "No description available"}',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.6),
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
      const SizedBox(height: 16),
      CourseExpandableContainer(
        isDark: isDark,
        cs: cs,
        title: 'Requirements',
        child: requirements.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: requirements
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '\u2022  $r',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6),
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              )
            : Text(
                'No requirements',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  height: 1.5,
                ),
              ),
      ),
      const SizedBox(height: 16),
      CourseExpandableContainer(
        isDark: isDark,
        cs: cs,
        title: 'Course Info',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Level : ${course.level}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Language : ${course.language}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Lessons : ${course.totalLessons}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Resources : ${course.totalResources}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _NativeModuleTabView extends StatefulWidget {
  final List<ModuleEntity> modules;
  final bool isDark;
  final ColorScheme cs;
  final bool isStudent;

  const _NativeModuleTabView({
    required this.modules,
    required this.isDark,
    required this.cs,
    required this.isStudent,
  });

  @override
  State<_NativeModuleTabView> createState() => _NativeModuleTabViewState();
}

class _NativeModuleTabViewState extends State<_NativeModuleTabView> {
  String _activeLessonTitle = '';
  final Set<int> _expandedModules = {0};

  @override
  void initState() {
    super.initState();
    if (widget.modules.isNotEmpty && widget.modules[0].lessons.isNotEmpty) {
      _activeLessonTitle = widget.modules[0].lessons[0].title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cs = widget.cs;

    if (widget.modules.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No modules yet',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    return Column(
      children: List.generate(widget.modules.length, (index) {
        final module = widget.modules[index];
        final isExpanded = _expandedModules.contains(index);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerLow : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedModules.remove(index);
                    } else {
                      _expandedModules.add(index);
                    }
                  });
                },
                borderRadius: isExpanded
                    ? const BorderRadius.vertical(
                        top: Radius.circular(16),
                      )
                    : BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? cs.surfaceContainerHighest
                        : const Color(0xFFF9F9F9),
                    borderRadius: isExpanded
                        ? const BorderRadius.vertical(
                            top: Radius.circular(16),
                          )
                        : BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              module.title,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: cs.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${module.lessons.length} items',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: cs.onSurface,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                Divider(
                  height: 1,
                  color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: List.generate(module.lessons.length, (
                      lessonIndex,
                    ) {
                      final lesson = module.lessons[lessonIndex];
                      final isActive = _activeLessonTitle == lesson.title;
                      final isLocked = !widget.isStudent && !lesson.isResource;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LessonRow(
                          title: lesson.title,
                          duration: lesson.duration,
                          isActive: isActive,
                          isDark: isDark,
                          isEnrolled: widget.isStudent,
                          isResource: lesson.isResource,
                          onTap: () {
                            if (!isLocked) {
                              setState(() => _activeLessonTitle = lesson.title);
                              if (lesson.isResource && lesson.fileUrl != null) {
                                launchUrl(
                                  Uri.parse(lesson.fileUrl!),
                                  mode: LaunchMode.externalApplication,
                                );
                              } else if (!lesson.isResource &&
                                  lesson.videoUrl != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoPlayerScreen(
                                      videoUrl: lesson.videoUrl!,
                                      title: lesson.title,
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _CourseDetailsSkeleton extends StatelessWidget {
  const _CourseDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSizes.horizontalPadding,
              8,
              AppSizes.horizontalPadding,
              110,
            ),
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ShimmerWidget(
                  width: double.infinity,
                  height: 184,
                  borderRadius: 16,
                ),
                const SizedBox(height: 16),
                const ShimmerWidget(width: 240, height: 22, borderRadius: 4),
                const SizedBox(height: 8),
                const ShimmerWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 4),
                const ShimmerWidget(width: 180, height: 14, borderRadius: 4),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ShimmerWidget(width: 80, height: 14, borderRadius: 4),
                    const SizedBox(width: 24),
                    ShimmerWidget(width: 90, height: 14, borderRadius: 4),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: List.generate(
                    3,
                    (i) => Expanded(
                      child: Column(
                        children: [
                          ShimmerWidget(width: 60, height: 14, borderRadius: 4),
                          const SizedBox(height: 8),
                          Container(
                            height: 2,
                            color: cs.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    ShimmerWidget(width: 60, height: 60, borderRadius: 30),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerWidget(width: 120, height: 16, borderRadius: 4),
                        const SizedBox(height: 4),
                        ShimmerWidget(width: 80, height: 12, borderRadius: 4),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const ShimmerWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 4),
                const ShimmerWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 4),
                const ShimmerWidget(width: 140, height: 14, borderRadius: 4),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 24),
            decoration: const BoxDecoration(color: Colors.transparent),
            child: Row(
              children: [
                const ShimmerWidget(width: 100, height: 42, borderRadius: 30),
                const SizedBox(width: 8),
                const Expanded(
                  child: ShimmerWidget(
                    width: double.infinity,
                    height: 54,
                    borderRadius: 30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomEnrollmentBar extends StatelessWidget {
  final String price;
  final bool isDark;
  final ColorScheme cs;

  const _BottomEnrollmentBar({
    required this.price,
    required this.isDark,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 24),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          Container(
            width: 78,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainerLow : Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDark ? cs.outlineVariant : AppColors.border,
              ),
            ),
            child: Text(
              price,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.primaryText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AuthButton(
              text: 'Enroll Now',
              height: 48,
              borderRadius: 30,
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.paymentSuccess),
            ),
          ),
        ],
      ),
    );
  }
}
