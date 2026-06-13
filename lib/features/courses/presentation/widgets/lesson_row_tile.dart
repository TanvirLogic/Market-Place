import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';

class LessonRow extends StatelessWidget {
  final String title;
  final String duration;
  final bool isActive;
  final bool isDark;
  final bool isEnrolled;
  final VoidCallback onTap;

  const LessonRow({
    super.key,
    required this.title,
    required this.duration,
    required this.isActive,
    required this.isDark,
    this.isEnrolled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isActive) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHighest : const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: AppColors.themeColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.themeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  duration,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.themeColor.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.themeColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHighest : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
                child: Icon(
                  isEnrolled ? Icons.play_arrow_rounded : Icons.lock_outline_rounded,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                duration,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
