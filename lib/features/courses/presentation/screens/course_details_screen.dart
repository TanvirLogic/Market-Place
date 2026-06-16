import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/widgets/shimmer_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/entities/course_entity.dart';
import '../../data/entities/module_entity.dart';
import 'package:edtech/features/courses/providers/course_detail_provider.dart';
import '../widgets/course_expandable_container.dart';
import '../widgets/course_reviews_tab_view.dart';
import '../widgets/course_stats_row.dart';
import '../widgets/instructor_profile_card.dart';
import '../widgets/lesson_row_tile.dart';

class CourseDetailsScreen extends StatelessWidget {
  const CourseDetailsScreen({Key? key}) : super(key: key);
  static const String name = '/course-details';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CourseDetailProvider(),
      child: _CourseDetailsBody(),
    );
  }
}

class _CourseDetailsBody extends StatefulWidget {
  @override
  State<_CourseDetailsBody> createState() => _CourseDetailsBodyState();
}

class _CourseDetailsBodyState extends State<_CourseDetailsBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CourseDetailProvider>().loadCourse('1');
    });
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
            body: const _CourseDetailsSkeleton(),
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
                          border: Border.all(color: AppColors.border),
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
                              course.description,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            CourseStatsRow(
                              videosCount: '${course.videosCount} Video',
                              resourcesCount:
                                  '${course.resourcesCount} Resource',
                              isDark: isDark,
                              cs: cs,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _CourseTabContentView(course: course),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: BottomEnrollmentBar(
                  price: '\u09F3${course.price.toStringAsFixed(2)}',
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 184,
        child: Stack(
          children: [
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
                  'by ${course.instructorName}',
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
    );
  }
}

class _CourseTabContentView extends StatefulWidget {
  final CourseEntity course;
  const _CourseTabContentView({required this.course});

  @override
  State<_CourseTabContentView> createState() => _CourseTabContentViewState();
}

class _CourseTabContentViewState extends State<_CourseTabContentView> {
  int _activeIndex = 0;
  final List<String> _tabs = ['Overview', 'Module', 'Reviews'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
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
                            : const Color(0xFFEFEFF0),
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
        if (_activeIndex == 1) _NativeModuleTabView(modules: course.modules),
        if (_activeIndex == 2) CourseReviewsTabView(reviews: course.reviews),
      ],
    );
  }

  List<Widget> _overviewContent(
    bool isDark,
    ColorScheme cs,
    CourseEntity course,
  ) {
    return [
      InstructorProfileCard(isDark: isDark, cs: cs),
      const SizedBox(height: 16),
      CourseExpandableContainer(
        isDark: isDark,
        cs: cs,
        title: 'Description',
        child: Text(
          '\u2022  Master modern web development with this comprehensive bootcamp. Learn HTML, CSS, JavaScript, React, Node.js, and MongoDB. Build real-world projects and get job-ready skills. Perfect for beginners and intermediate developers looking to advance their careers.',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '\u2022  Basic computer skills',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            Text(
              '\u2022  No prior programming experience needed',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            Text(
              '\u2022  A computer with internet connection',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          ],
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
              'Lessons : 156',
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
  const _NativeModuleTabView({required this.modules});

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? cs.surfaceContainerHighest
                        : const Color(0xFFF9F9F9),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
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
                              module.lessonsCount,
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
                Divider(height: 1, color: const Color(0xFFEFEFF0)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: List.generate(module.lessons.length, (
                      lessonIndex,
                    ) {
                      final lesson = module.lessons[lessonIndex];
                      final isActive = _activeLessonTitle == lesson.title;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LessonRow(
                          title: lesson.title,
                          duration: lesson.duration,
                          isActive: isActive,
                          isDark: isDark,
                          onTap: () {
                            if (!lesson.isLocked) {
                              setState(() => _activeLessonTitle = lesson.title);
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
                ShimmerWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 4),
                ShimmerWidget(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 4),
                ShimmerWidget(width: 140, height: 14, borderRadius: 4),
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

class BottomEnrollmentBar extends StatelessWidget {
  final String price;
  final bool isDark;
  final ColorScheme cs;

  const BottomEnrollmentBar({
    Key? key,
    required this.price,
    required this.isDark,
    required this.cs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              price,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
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
