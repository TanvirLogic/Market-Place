import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../../global/core/constants/images/images.dart';

class MetricsGrid extends StatelessWidget {
  final int? totalCourses;
  final int? totalEnrollments;
  final int? totalReviews;
  final double? avgRating;

  const MetricsGrid({
    super.key,
    this.totalCourses,
    this.totalEnrollments,
    this.totalReviews,
    this.avgRating,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                iconPath: 'assets/images/revenue_icons/book_icon.svg',
                valueText: '${totalCourses ?? 12}',
                labelText: 'Total Courses',
                cs: cs,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: MetricCard(
                iconPath: 'assets/images/revenue_icons/total_in.svg',
                valueText: '৳9640',
                labelText: 'Total Earning',
                cs: cs,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                iconPath: Images.totalStudent,
                valueText: '${totalEnrollments ?? 1234}',
                labelText: 'Total Student',
                cs: cs,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: MetricCard(
                iconPath: Images.star,
                valueText: avgRating != null ? avgRating!.toStringAsFixed(1) : '${totalReviews ?? 0}',
                trailingText: totalReviews != null && avgRating != null ? '($totalReviews)' : null,
                labelText: avgRating != null ? 'Reviews' : 'Total Reviews',
                cs: cs,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  final IconData? icon;
  final String? iconPath;
  final String valueText;
  final String? trailingText;
  final String labelText;
  final ColorScheme cs;
  final bool isDark;

  const MetricCard({
    super.key,
    this.icon,
    this.iconPath,
    required this.valueText,
    this.trailingText,
    required this.labelText,
    required this.cs,
    required this.isDark,
  });

  Widget _buildIcon() {
    if (iconPath != null) {
      return SvgPicture.asset(
        iconPath!,
        width: 20,
        height: 20,
        colorFilter: ColorFilter.mode(AppColors.themeColor, BlendMode.srcIn),
      );
    }
    return Icon(icon, color: AppColors.themeColor, size: 20);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.themeColor.withValues(alpha: 0.08),
            child: _buildIcon(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  textBaseline: TextBaseline.alphabetic,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  children: [
                    Flexible(
                      child: Text(
                        valueText,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (trailingText != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        trailingText!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  labelText,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
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
}
