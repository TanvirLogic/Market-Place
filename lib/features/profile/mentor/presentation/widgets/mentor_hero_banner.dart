import 'package:cached_network_image/cached_network_image.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../../../global/core/constants/images/images.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import 'package:edtech/features/profile/avatar/providers/cover_upload_provider.dart';

/// Hero banner with cover image, back/edit buttons, and overlapping avatar.
///
/// The cover image displays as edge-to-edge with a height of 195px.
/// The avatar overlaps the bottom of the banner by 45px.
///
/// Pass [onAvatarTap] to allow the user to change their profile photo.
/// Pass [onCoverTap] to allow the user to change their cover photo.
///
/// For best cover quality, users should upload images cropped to 16:9
/// at 1920x1080 resolution — this ensures the banner looks sharp on all
/// screen sizes without pixelation or excessive compression artifacts.
class MentorHeroBanner extends StatelessWidget {
  final String? coverUrl;
  final String? avatarUrl;
  final VoidCallback? onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onCoverTap;
  final bool isOwnProfile;

  const MentorHeroBanner({
    super.key,
    this.coverUrl,
    this.avatarUrl,
    this.onBack,
    this.onEdit,
    this.onAvatarTap,
    this.onCoverTap,
    this.isOwnProfile = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconBg = cs.surfaceContainerHighest;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Background banner image with gradient overlay — tappable for cover photo upload
        Consumer<CoverUploadProvider>(
          builder: (context, coverProvider, _) {
            final isUploading = coverProvider.isUploading;
            final progress = coverProvider.uploadProgress;

            return GestureDetector(
              onTap: isUploading ? null : onCoverTap,
              child: Container(
                height: 195,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: (coverUrl != null && coverUrl!.isNotEmpty)
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(coverUrl!),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        )
                      : null,
                  color: cs.surfaceContainerHighest,
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.white.withValues(alpha: 0.8),
                            Colors.white,
                          ],
                          stops: const [0.0, 0.85, 1.0],
                        ),
                      ),
                    ),
                    if (isUploading)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Uploading cover... ${(progress * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        // Back button
        Positioned(
          top: 48,
          left: 12,
          child: CircleAvatar(
            backgroundColor: iconBg,
            radius: 22,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 14, color: cs.onSurface),
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
          ),
        ),

        // Edit button
        if (isOwnProfile)
          Positioned(
            top: 48,
            right: 12,
            child: CircleAvatar(
              backgroundColor: iconBg,
              radius: 22,
              child: IconButton(
                icon: Padding(
                  padding: const EdgeInsets.all(3),
                  child: SvgPicture.asset(
                    Images.editProfile,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(cs.onSurface, BlendMode.srcIn),
                  ),
                ),
                onPressed: onEdit,
              ),
            ),
          ),

        // Overlapping avatar — entire area is tappable for photo upload
        Positioned(
          bottom: -45,
          child: Consumer<AvatarUploadProvider>(
            builder: (context, avatarProvider, _) {
              final isUploading = avatarProvider.isUploading;
              final progress = avatarProvider.uploadProgress;

              return GestureDetector(
                onTap: isUploading ? null : onAvatarTap,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: ClipOval(
                          child: CachedNetworkImage(
                            key: ValueKey(avatarUrl),
                            imageUrl: avatarUrl ?? '',
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.high,
                            placeholder: (context, url) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Center(
                                child: Image.asset(
                                  Images.profileUser,
                                  fit: BoxFit.cover,
                                  width: 38,
                                  height: 38,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Center(
                                child: Image.asset(
                                  Images.profileUser,
                                  fit: BoxFit.cover,
                                  width: 38,
                                  height: 38,
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
                                  width: 24,
                                  height: 24,
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
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (!isUploading && isOwnProfile)
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
                              decoration: BoxDecoration(
                                color: AppColors.themeColor,
                                shape: BoxShape.circle,
                              ),
                              child: SvgPicture.asset(
                                Images.cameraIcon,
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
        ),
      ],
    );
  }
}
