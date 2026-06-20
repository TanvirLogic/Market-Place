import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CourseStatsRow extends StatelessWidget {
  final String videosCount;
  final String resourcesCount;
  final bool isDark;
  final ColorScheme cs;

  const CourseStatsRow({
    super.key,
    required this.videosCount,
    required this.resourcesCount,
    required this.isDark,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Row(
          children: [
            SvgPicture.asset(
              Images.videoIcon,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(AppColors.themeColor, BlendMode.srcIn),
            ),
            const SizedBox(width: 6),
            Text(
              videosCount,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? cs.onSurface.withValues(alpha: 0.8) : const Color(0xFF4B5563),
              ),
            ),
          ],
        ),
        const SizedBox(width: 24),
        Row(
          children: [
            SvgPicture.asset(
              Images.resource,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(AppColors.themeColor, BlendMode.srcIn),
            ),
            const SizedBox(width: 6),
            Text(
              resourcesCount,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? cs.onSurface.withValues(alpha: 0.8) : const Color(0xFF4B5563),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
