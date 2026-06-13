import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../../../../../global/core/constants/images/images.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import '../../data/entities/user_profile_entity.dart';

/// Displays the student's avatar, username, role, stats (videos/courses), and bio.
///
/// Pass [onAvatarTap] to allow the user to change their profile photo.
/// Shows a camera icon overlay on the avatar to hint at the upload capability.
class ProfileHeaderCard extends StatelessWidget {
  final UserProfileEntity student;
  final VoidCallback? onAvatarTap;

  const ProfileHeaderCard({super.key, required this.student, this.onAvatarTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Consumer<AvatarUploadProvider>(
          builder: (context, uploadProvider, _) {
            final isUploading = uploadProvider.isUploading;
            final progress = uploadProvider.uploadProgress;

            return GestureDetector(
              onTap: isUploading ? null : onAvatarTap,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFEFEFF0), width: 1),
                    ),
                      child: SizedBox(
                        width: 110,
                        height: 110,
                        child: ClipOval(
                          child: CachedNetworkImage(
                            key: ValueKey(student.avatarUrl),
                            imageUrl: student.avatarUrl ?? '',
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.high,
                          placeholder: (context, url) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Center(
                              child: Image.asset(
                                'assets/images/profile_icons/user.png',
                                fit: BoxFit.cover,
                                width: 44,
                                height: 44,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Center(
                              child: Image.asset(
                                'assets/images/profile_icons/user.png',
                                fit: BoxFit.cover,
                                width: 44,
                                height: 44,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isUploading)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!isUploading)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: onAvatarTap,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.themeColor,
                              shape: BoxShape.circle,
                            ),
                            child: SvgPicture.asset(
                              Images.camera_icon,
                              width: 12,
                              height: 12,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            spacing: 2,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "@${student.username}",
                style: TextStyle(
                  color: AppColors.themeColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                student.profession != null && student.profession!.isNotEmpty
                    ? student.profession!
                    : 'No Profession added yet',
                style: TextStyle(
                  color: student.profession != null && student.profession!.isNotEmpty
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.4),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  SvgPicture.asset(
                    Images.video_icon,
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(AppColors.themeColor, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${student.videoCount} Video',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SvgPicture.asset(
                    Images.book_icon,
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(AppColors.themeColor, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${student.courseCount} Course',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (student.bio != null && student.bio!.isNotEmpty)
                Text(
                  student.bio!,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                )
              else
                Text(
                  "Tell others about your skills, interests, experiences and what you're currently learning.",
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
