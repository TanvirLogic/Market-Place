import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LessonRow extends StatelessWidget {
  final String title;
  final String duration;
  final bool isActive;
  final bool isDark;
  final bool isEnrolled;
  final bool isResource;
  final VoidCallback onTap;

  const LessonRow({
    super.key,
    required this.title,
    required this.duration,
    required this.isActive,
    required this.isDark,
    this.isEnrolled = false,
    this.isResource = false,
    required this.onTap,
  });

  Widget _icon(ColorScheme cs) {
    final iconColor = isActive
        ? AppColors.themeColor
        : cs.onSurface.withValues(alpha: 0.6);
    if (isResource) {
      return SvgPicture.asset(
        Images.resource,
        height: 24,
        width: 24,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      );
    }
    if (isEnrolled) return Icon(Icons.play_arrow_rounded, color: iconColor);
    return SvgPicture.asset(
      Images.hubPasswordSecurity,
      height: 24,
      width: 24,
      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final borderRadius = BorderRadius.circular(AppSizes.radiusSm);
    final bgColor = isActive
        ? (isDark ? cs.surfaceContainerHighest : AppColors.surface)
        : Colors.transparent;

    return Container(
      height: 56,
      decoration: BoxDecoration(color: bgColor, borderRadius: borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isDark ? cs.outlineVariant : AppColors.border,
                child: _icon(cs),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? AppColors.themeColor
                        : cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              if (duration.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  duration,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? AppColors.themeColor.withValues(alpha: 0.7)
                        : cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
              if (!isActive) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
