import 'package:edtech/app/app_colors.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/features/courses/data/models/course_feed_model.dart';
import 'package:edtech/features/courses/providers/course_feed_provider.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});
  static const String name = '/courses';

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CourseFeedProvider>().fetchFeed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Consumer<CourseFeedProvider>(
      builder: (context, provider, _) {
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification &&
                notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 300 &&
                provider.hasNextPage &&
                !provider.isLoadingMore) {
              provider.fetchMore();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: provider.refresh,
            child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(
              left: AppSizes.horizontalPadding,
              right: AppSizes.horizontalPadding,
              top: 8,
              bottom: 24,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Image.asset(Images.eduverseP, width: 113, height: 32),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.notifications,
                        ),
                        onLongPress: () {},
                        child: SvgPicture.asset(Images.notificationIcon),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: 'Course Name, Author...',
                      prefixIcon: Icon(
                        Icons.search,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      filled: true,
                      fillColor: isDark
                          ? cs.surfaceContainerHighest
                          : Colors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
                        borderSide: BorderSide(
                          color: isDark ? cs.outlineVariant : AppColors.border,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (provider.isLoading && provider.courses.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (provider.errorMessage != null &&
                      provider.courses.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Column(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: cs.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              provider.errorMessage!,
                              style: TextStyle(color: cs.error),
                            ),
                            const SizedBox(height: 12),
                            AuthButton(
                              text: 'Retry',
                              onPressed: provider.refresh,
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    if (provider.enrolledCourses.isNotEmpty) ...[
                      Text(
                        'My Course (${provider.enrolledCourses.length})',
                        style: TextStyle(
                          fontSize: 20,
                          color: isDark ? Colors.white : AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._buildMyCourses(provider.enrolledCourses, cs, isDark),
                      const SizedBox(height: 24),
                    ],
                    if (provider.courses.isNotEmpty) ...[
                      Text(
                        'Recommended Course',
                        style: TextStyle(
                          fontSize: 20,
                          color: isDark ? Colors.white : AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...provider.courses.map(
                        (course) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RecommendedCard(
                            course: course,
                            cs: cs,
                            isDark: isDark,
                          ),
                        ),
                      ),
                      if (provider.isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.only(top: 12, bottom: 24),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  }

  List<Widget> _buildMyCourses(
    List<CourseFeedModel> enrolledCourses,
    ColorScheme cs,
    bool isDark,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < enrolledCourses.length; i += 2) {
      final first = enrolledCourses[i];
      final second = i + 1 < enrolledCourses.length
          ? enrolledCourses[i + 1]
          : null;

      widgets.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MyCourseCard(
                cs: cs,
                isDark: isDark,
                title: first.title,
                level: first.level,
                lessons: '',
                isFree: first.type == 'FREE',
                progress: 0.0,
                courseId: first.id,
              ),
            ),
            if (second != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _MyCourseCard(
                  cs: cs,
                  isDark: isDark,
                  title: second.title,
                  level: second.level,
                  lessons: '',
                  isFree: second.type == 'FREE',
                  progress: 0.0,
                  courseId: second.id,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return widgets;
  }
}

class _MyCourseCard extends StatelessWidget {
  final ColorScheme cs;
  final bool isDark;
  final String title;
  final String level;
  final String lessons;
  final bool isFree;
  final double progress;
  final int courseId;

  const _MyCourseCard({
    required this.cs,
    required this.isDark,
    required this.title,
    required this.level,
    required this.lessons,
    required this.isFree,
    required this.progress,
    required this.courseId,
  });

  Color _progressColor() {
    if (progress < 0.33) return const Color(0xFFEF4444);
    if (progress < 0.66) return const Color(0xFFEAB308);
    return const Color(0xFF22C55E);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(
          color: isDark ? cs.outlineVariant : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              child: SizedBox(
                width: double.infinity,
                height: 85,
                child: Stack(
                  children: [
                    Container(
                      color: AppColors.themeColor.withValues(alpha: 0.15),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            Images.bookNoC,
                            width: 12,
                            height: 12,
                            colorFilter: ColorFilter.mode(
                              isDark ? Colors.white : Colors.black87,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            level.isNotEmpty ? level : 'All Levels',
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            Images.dollar,
                            width: 12,
                            height: 12,
                            colorFilter: ColorFilter.mode(
                              isDark ? Colors.white : Colors.black87,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isFree ? 'Free' : 'Paid',
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        color: cs.onSurface.withValues(alpha: 0.12),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(color: _progressColor()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white : AppColors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset(
                        Images.bookNoC,
                        width: 12,
                        height: 12,
                        colorFilter: ColorFilter.mode(
                          isDark ? Colors.white : AppColors.primaryText,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        lessons.isNotEmpty ? lessons : level,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.6)
                              : AppColors.primaryText,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppRoutes.courseDetails,
                      arguments: {'courseId': courseId},
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(56, 22),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: isDark
                          ? cs.surfaceContainerHighest
                          : AppColors.surface,
                      foregroundColor: isDark
                          ? Colors.white
                          : AppColors.primaryText,
                      elevation: 0,
                      side: BorderSide(
                        color: isDark ? cs.outlineVariant : AppColors.border,
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final CourseFeedModel course;
  final ColorScheme cs;
  final bool isDark;

  const _RecommendedCard({
    required this.course,
    required this.cs,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.courseDetails,
        arguments: {'courseId': course.id},
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerLow : Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(
            color: isDark ? cs.outlineVariant : AppColors.border,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
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
                                AppColors.themeColor.withValues(alpha: 0.6),
                                AppColors.themeColor.withValues(alpha: 0.2),
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
                              AppColors.themeColor.withValues(alpha: 0.6),
                              AppColors.themeColor.withValues(alpha: 0.2),
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusLg2,
                          ),
                        ),
                        child: Text(
                          'by ${course.mentor.name}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusSm,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              color: Color(0xFFF59E0B),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(course.updatedAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              course.title,
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.white : AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              course.shortDescription.isNotEmpty
                  ? course.shortDescription
                  : 'No description available',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (course.language.isNotEmpty)
                  _svgChip(Images.language, course.language),
                _svgChip(Images.bookNoC, course.level),
                _svgChip(
                  Images.dollar,
                  course.type == 'PAID' ? 'Paid' : 'Free',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  course.type == 'PAID' ? '\u09F3${course.price}' : 'Free',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: AppColors.themeColor,
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: AuthButton(
                    text: 'Enroll now',
                    height: 44,
                    borderRadius: 22,
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _svgChip(String asset, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          asset,
          width: 16,
          height: 16,
          colorFilter: ColorFilter.mode(
            isDark ? Colors.white : AppColors.themeColor,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isDark ? Colors.white : AppColors.primaryText,
          ),
        ),
      ],
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      if (diff.inDays < 1) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${diff.inDays ~/ 7}w ago';
    } catch (_) {
      return 'New';
    }
  }
}
