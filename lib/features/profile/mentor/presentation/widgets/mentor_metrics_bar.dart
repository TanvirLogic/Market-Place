import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../global/core/constants/images/images.dart';
import 'package:edtech/app/app_colors.dart';

/// Metrics bar showing video count, course count, and location.
class MentorMetricsBar extends StatelessWidget {
  final int videoCount;
  final int courseCount;
  final String? location;

  const MentorMetricsBar({
    super.key,
    required this.videoCount,
    required this.courseCount,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          Images.video_icon,
          width: 16,
          height: 16,
          colorFilter: ColorFilter.mode(
            AppColors.themeColor,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 2),
          Text(
            '$videoCount Video',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          SvgPicture.asset(
            Images.book_icon,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              AppColors.themeColor,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            '$courseCount Course',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (location != null && location!.isNotEmpty) ...[
            const SizedBox(width: 8),
            SvgPicture.asset(
              Images.location,
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(
                AppColors.themeColor,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              location!,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
      ],
    );
  }
}
