import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'dart:ui' as ui;

import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:flutter/material.dart';

class PostOptionsOverlay extends StatelessWidget {
  const PostOptionsOverlay({super.key});

  static void show(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Post options',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const PostOptionsOverlay(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          BlurEffect(onTap: () => Navigator.of(context).pop()),
          Center(
            child: Container(
              width: 343,
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainerLow : Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context)
                        ..pop()
                        ..pushNamed(AppRoutes.uploadCoursePage);
                    },
                    child: Image.asset(Images.uploadCourse),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Divider(thickness: 1, color: isDark ? cs.outlineVariant : AppColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'or',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      Expanded(child: Divider(thickness: 1, color: isDark ? cs.outlineVariant : AppColors.border)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context)
                        ..pop()
                        ..pushNamed(AppRoutes.uploadVideoPage);
                    },
                    child: Image.asset(Images.postVideo),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BlurEffect extends StatelessWidget {
  final VoidCallback onTap;
  const BlurEffect({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
