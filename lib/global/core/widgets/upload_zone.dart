import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../../global/core/widgets/dashed_border.dart';

class UploadZone extends StatelessWidget {
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback? onTap;
  final String? selectedFileName;
  final String label;
  final IconData iconData;
  final bool isPicking;

  const UploadZone({
    super.key,
    required this.cs,
    required this.isDark,
    this.onTap,
    this.selectedFileName,
    this.label = 'Upload Video File',
    this.iconData = Icons.cloud_upload_outlined,
    this.isPicking = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isPicking ? null : onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: AnimatedOpacity(
        opacity: isPicking ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 180,
          decoration: ShapeDecoration(
            color: isDark
                ? cs.surfaceContainerLow.withValues(alpha: 0.6)
                : const Color(0x99F5F5F5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
          ),
          foregroundDecoration: ShapeDecoration(
            shape: DashedBorder(
              color: isDark ? cs.outlineVariant : const Color(0xFFDEDEDE),
              width: 2.5,
              radius: 16,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isPicking)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                _UploadIcon(cs: cs, iconData: iconData),
              const SizedBox(height: 12),
              Text(
                isPicking ? 'Opening gallery...' : (selectedFileName ?? label),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
                  children: [
                    if (selectedFileName == null && !isPicking) ...[
                      const TextSpan(
                        text: 'Drag & drop your file here or tap to\n',
                      ),
                      TextSpan(
                        text: 'browse',
                        style: TextStyle(
                          color: AppColors.themeColor,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ] else if (!isPicking)
                      TextSpan(
                        text: 'Tap to change file',
                        style: TextStyle(color: AppColors.themeColor),
                      ),
                  ],
                ),
              ),
              if (selectedFileName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.4),
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

class _UploadIcon extends StatelessWidget {
  final ColorScheme cs;
  final IconData iconData;
  const _UploadIcon({
    required this.cs,
    this.iconData = Icons.cloud_upload_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: ShapeDecoration(
        color: cs.outlineVariant.withValues(alpha: 0.3),
        shape: const CircleBorder(),
      ),
      foregroundDecoration: ShapeDecoration(
        shape: DashedBorder(
          color: cs.brightness == Brightness.dark
              ? cs.outlineVariant
              : const Color(0xFFDEDEDE),
          width: 2.5,
          radius: 28,
        ),
      ),
      child: Icon(iconData, color: cs.onSurface, size: 28),
    );
  }
}
