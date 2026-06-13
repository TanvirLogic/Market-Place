import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});
  static const String name = '/courses';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: EdgeInsets.only(left: AppSizes.horizontalPadding, right: AppSizes.horizontalPadding, top: 8, bottom: 24),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset(Images.eduverseP, width: 113, height: 32),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.notifications),
                  onLongPress: () {},
                  child: SvgPicture.asset(Images.notification_icon),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: InputDecoration(
                hintText: 'Course Name, Author...',
                prefixIcon: Icon(Icons.search, color: cs.onSurface.withValues(alpha: 0.6)),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                filled: true,
                fillColor: isDark ? cs.surfaceContainerHighest : Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: const Color(0xFFEFEFF0)),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'My Course (2)',
              style: TextStyle(fontSize: 20, color: isDark ? Colors.white : AppColors.primaryText),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MyCourseCard(
                    cs: cs,
                    isDark: isDark,
                    title: 'Kubernetes Crash Course',
                    level: 'Advanced',
                    lessons: '156 lessons',
                    isFree: false,
                    progress: 0.7,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _MyCourseCard(
                    cs: cs,
                    isDark: isDark,
                    title: 'Data Science Bootcamp',
                    level: 'Advanced',
                    lessons: '156 lessons',
                    isFree: true,
                    progress: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Recommended Course',
              style: TextStyle(fontSize: 20, color: isDark ? Colors.white : AppColors.primaryText),
            ),
            const SizedBox(height: 16),
            _RecommendedCard(cs: cs, isDark: isDark),
          ],
        ),
      ),
    );
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

  const _MyCourseCard({
    required this.cs,
    required this.isDark,
    required this.title,
    required this.level,
    required this.lessons,
    required this.isFree,
    required this.progress,
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFEFEFF0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: double.infinity,
                height: 85,
                child: Stack(
                  children: [
                    Container(color: cs.primary.withValues(alpha: 0.15)),
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
                            level,
                            style: TextStyle(
                              fontSize: 9,
                      color: isDark ? Colors.white : AppColors.primaryText,
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
                      color: isDark ? Colors.white : AppColors.primaryText,
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
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white : AppColors.primaryText),
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
                      SvgPicture.asset(Images.bookNoC, width: 12, height: 12),
                      const SizedBox(width: 3),
                      Text(
                        lessons,
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white.withValues(alpha: 0.6) : AppColors.primaryText),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.enrolledCourse),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(56, 22),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: cs.surfaceContainerHighest,
                      foregroundColor: isDark ? Colors.white : AppColors.primaryText,
                      elevation: 0,
                    ),
                    child: const Text('Continue', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
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
  final ColorScheme cs;
  final bool isDark;

  const _RecommendedCard({required this.cs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.courseDetails),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerLow : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEFEFF0)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 184,
              child: Stack(
                children: [
                  Container(
                    height: 184,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary.withValues(alpha: 0.6), cs.primary.withValues(alpha: 0.2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'by Sarah Wilson',
                        style: TextStyle(fontSize: 12, color: AppColors.primaryText),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Color(0xFFF59E0B), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '4.9',
                            style: TextStyle(fontSize: 12, color: AppColors.primaryText),
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
            'Full-Stack AI Development 2027',
            style: TextStyle(fontSize: 18, color: isDark ? Colors.white : AppColors.primaryText),
          ),
          const SizedBox(height: 4),
          Text(
            'Passionate educator with over a decade of industry experience. Helping aspiring developers master modern to development.',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6), height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _iconChip(Icons.g_translate_outlined, 'French'),
              const SizedBox(width: 12),
              _svgInfoChip(Images.bookNoC, 'Beginner'),
              const SizedBox(width: 12),
              _svgInfoChip(Images.dollar, 'Paid'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\u09F367.67',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: AppColors.themeColor),
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

  Widget _iconChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white : AppColors.themeColor,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : AppColors.primaryText,
          ),
        ),
      ],
    );
  }

  Widget _svgInfoChip(String svgPath, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          svgPath,
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
            fontSize: 13,
            color: isDark ? Colors.white : AppColors.primaryText,
          ),
        ),
      ],
    );
  }
}
