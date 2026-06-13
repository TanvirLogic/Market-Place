import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:edtech/app/app_colors.dart';
import '../../data/entities/user_profile_entity.dart';

/// Vertical list of completed courses from the API.
class CompletedCoursesVerticalListView extends StatelessWidget {
  final List<ProfileCourse> courses;
  final bool isMentorProfile;
  final bool isOwnProfile;
  final void Function(ProfileCourse course)? onActionPressed;

  const CompletedCoursesVerticalListView({
    super.key,
    required this.courses,
    this.isMentorProfile = false,
    this.isOwnProfile = false,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (courses.isEmpty) return const SizedBox.shrink();

    return Column(
      children: List.generate(courses.length * 2 - 1, (index) {
        if (index.isOdd) {
          return Divider(
            height: 1,
            color: cs.outlineVariant,
            thickness: 1,
          );
        }
        final item = courses[index ~/ 2];
        return Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(item.image),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: cs.onSurface,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.by,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              isMentorProfile
                  ? SizedBox(
                      width: isOwnProfile ? 96 : 110,
                      height: 30,
                      child: isOwnProfile
                          ? ElevatedButton(
                              onPressed: onActionPressed == null
                                  ? null
                                  : () => onActionPressed!(item),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.themeColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.zero,
                              ),
                              child: const Text(
                                'Manage',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF134BBF), Color(0xFF5B83FF)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: onActionPressed == null
                                      ? null
                                      : () => onActionPressed!(item),
                                  child: const Center(
                                    child: Text(
                                      'Enroll Now',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF5FB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFACCDEC),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        'Completed',
                        style: TextStyle(
                          color: AppColors.themeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ],
          ),
        );
      }),
    );
  }
}
