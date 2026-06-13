import 'package:edtech/features/profile/avatar/presentation/widgets/avatar_options_bottom_sheet.dart';
import 'package:edtech/features/profile/avatar/presentation/widgets/custom_crop_screen.dart';
import 'package:edtech/features/profile/avatar/presentation/widgets/cover_reposition_screen.dart';
import 'package:edtech/features/profile/mentor/presentation/widgets/mentor_hero_banner.dart';
import 'package:edtech/features/profile/mentor/presentation/widgets/mentor_identity_header.dart';
import 'package:edtech/features/profile/mentor/presentation/widgets/mentor_metrics_bar.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import 'package:edtech/features/profile/avatar/providers/cover_upload_provider.dart';
import '../../../student/presentation/widgets/completed_courses_list.dart';
import '../../../student/presentation/widgets/section_header.dart';
import '../../../student/presentation/widgets/skill_badges_row.dart';
import '../../../student/presentation/widgets/social_links_row.dart';
import '../../../student/presentation/widgets/video_list_section.dart';
import 'package:edtech/features/profile/mentor/providers/mentor_profile_provider.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';

/// Mentor profile page rendered from the provider's [UserProfileEntity].
class MentorProfileScreen extends StatefulWidget {
  final bool isOwnProfile;

  const MentorProfileScreen({super.key, this.isOwnProfile = true});

  @override
  State<MentorProfileScreen> createState() => _MentorProfileScreenState();
}

class _MentorProfileScreenState extends State<MentorProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch profile data on page load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MentorProfileProvider>().fetchProfile();

      // ── Set up avatar upload success callback ──
      context.read<AvatarUploadProvider>().onUploadSuccess = (newAvatarUrl) {
        final currentProfile = context.read<MentorProfileProvider>().profile;
        if (currentProfile != null) {
          context.read<MentorProfileProvider>().fetchProfile();
        }
      };

      // ── Set up cover upload success callback ──
      context.read<CoverUploadProvider>().onUploadSuccess = (newCoverUrl) {
        final currentProfile = context.read<MentorProfileProvider>().profile;
        if (currentProfile != null) {
          context.read<MentorProfileProvider>().fetchProfile();
        }
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MentorProfileProvider>(
      builder: (context, provider, _) {
        if (provider.profile == null) {
          if (provider.errorMessage != null) {
            return Scaffold(
              appBar: const _LoadingAppBar(),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ToastService.friendlyMessage(provider.errorMessage!),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => provider.fetchProfile(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: const _LoadingAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return _MentorProfileBody(profile: provider.profile!, isOwnProfile: widget.isOwnProfile);
      },
    );
  }
}

/// Main body of the mentor profile page once data is available.
class _MentorProfileBody extends StatelessWidget {
  final UserProfileEntity profile;
  final bool isOwnProfile;

  const _MentorProfileBody({required this.profile, this.isOwnProfile = true});

  String _aboutTitle() {
    if (isOwnProfile) return 'About Me';
    return profile.gender == 1 ? 'About Him' : 'About Her';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () => context.read<MentorProfileProvider>().fetchProfile(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // ── Section 1: Hero banner (edge-to-edge, no horizontal padding) ──
              MentorHeroBanner(
                coverUrl: profile.coverUrl,
                avatarUrl: profile.avatarUrl,
                isOwnProfile: isOwnProfile,
                onAvatarTap: isOwnProfile ? () => _showAvatarOptions(context, profile) : null,
                onCoverTap: isOwnProfile ? () => _showCoverOptions(context, profile) : null,
                onEdit: isOwnProfile
                    ? () => Navigator.pushNamed(context, AppRoutes.editProfilePage)
                    : null,
              ),
              const SizedBox(height: 45), // 12px between sections
              // ── Remaining content with 16px horizontal padding ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Section 2: Identity header & metrics (centered) ──
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        spacing: 4,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          MentorIdentityHeader(
                            name: profile.name,
                            username: profile.username,
                            role: profile.profession ?? "",
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Center(
                              child: MentorMetricsBar(
                                videoCount: profile.videoCount,
                                courseCount: profile.courseCount,
                                location: profile.country,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12), // 12px between sections
                    // ── Section 3: About ──
                    SectionHeader(title: _aboutTitle()),
                    if (profile.bio != null && profile.bio!.isNotEmpty)
                      Text(
                        profile.bio!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      )
                    else
                      Text(
                        "Tell others about your skills, interests, experiences and what you're currently learning.",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 12),
                    // ── Section 4: Skill Badges (left-aligned under start) ──
                    const SectionHeader(title: 'Skill Badges'),
                    const SkillBadgesRow(),
                    if (profile.socialLinks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const SectionHeader(title: 'Social Links'),
                      SocialLinksRow(socialLinks: profile.socialLinks),
                    ],
                    const SizedBox(height: 12), // 12px between sections
                    // ── Section 6: Videos ──
                    const SectionHeader(
                      title: 'Videos',
                    ),
                    VideosHorizontalListView(videos: profile.videos),
                    const SizedBox(height: 12), // 12px between sections
                    // ── Section 7: Completed Courses ──
                    const SectionHeader(
                      title: 'Completed Courses',
                    ),
                    CompletedCoursesVerticalListView(
                      courses: profile.courses,
                      isMentorProfile: true,
                      isOwnProfile: isOwnProfile,
                      onActionPressed: (course) {
                        if (isOwnProfile) {
                          Navigator.pushNamed(context, AppRoutes.manageModule);
                        } else {
                          Navigator.pushNamed(context, AppRoutes.courseDetails);
                        }
                      },
                    ),
                    const SizedBox(height: 24), // bottom padding
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Helper functions called from [_MentorProfileBody.build]
/// ─────────────────────────────────────────────────────────────────────────────

/// Shows the avatar options bottom sheet (Facebook / View / Upload) for mentors.
Future<void> _showAvatarOptions(
  BuildContext context,
  UserProfileEntity profile,
) async {
  final option = await showAvatarOptionsBottomSheet(
    context: context,
    currentImageUrl: profile.avatarUrl,
    isAvatar: true,
  );

  if (option == null) return;
  if (!context.mounted) return;

  switch (option) {
    case AvatarOption.facebook:
      _openFacebookProfile(context, profile);
    case AvatarOption.view:
      if (profile.avatarUrl == null || profile.avatarUrl!.isEmpty) return;
      Navigator.pushNamed(
        context,
        AppRoutes.fullScreenImage,
        arguments: {'imageUrl': profile.avatarUrl, 'heroTag': 'mentor_avatar'},
      );
    case AvatarOption.upload:
      await _pickAndCropAvatarThenUpload(context);
  }
}

/// Pick image at full phone quality → custom crop (circular) → upload avatar.
Future<void> _pickAndCropAvatarThenUpload(BuildContext context) async {
  final avatarProvider = context.read<AvatarUploadProvider>();

  final pickedFile = await avatarProvider.pickImage();
  if (pickedFile == null || !context.mounted) return;

  final croppedFile = await Navigator.push<CroppedFile>(
    context,
    MaterialPageRoute(
      builder: (_) => CustomCropScreen(
        imageFile: pickedFile,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        outputMaxWidth: 1024,
        outputMaxHeight: 1024,
        outputQuality: 95,
        isCircular: true,
        toolbarTitle: 'Crop Avatar',
      ),
    ),
  );

  if (croppedFile != null) {
    await avatarProvider.uploadAvatarFromFile(XFile(croppedFile.path));
  } else {
    if (context.mounted) avatarProvider.resetState();
  }
}

/// Shows the cover options bottom sheet (View / Upload) for mentors.
Future<void> _showCoverOptions(
  BuildContext context,
  UserProfileEntity profile,
) async {
  final option = await showAvatarOptionsBottomSheet(
    context: context,
    currentImageUrl: profile.coverUrl,
    isAvatar: false,
  );

  if (option == null) return;
  if (!context.mounted) return;

  switch (option) {
    case AvatarOption.facebook:
      break;
    case AvatarOption.view:
      if (profile.coverUrl == null || profile.coverUrl!.isEmpty) return;
      Navigator.pushNamed(
        context,
        AppRoutes.fullScreenImage,
        arguments: {'imageUrl': profile.coverUrl, 'heroTag': 'mentor_cover'},
      );
    case AvatarOption.upload:
      await _pickAndCropCoverThenUpload(context, profile);
  }
}

/// Pick image at full phone quality → Facebook-style reposition → upload cover.
Future<void> _pickAndCropCoverThenUpload(
  BuildContext context,
  UserProfileEntity profile,
) async {
  final coverProvider = context.read<CoverUploadProvider>();

  final pickedFile = await coverProvider.pickImage();
  if (pickedFile == null || !context.mounted) return;

  final croppedFile = await Navigator.push<CroppedFile>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          CoverRepositionScreen(imageFile: pickedFile, bannerHeight: 195),
    ),
  );

  if (croppedFile != null) {
    await coverProvider.uploadCoverFromFile(XFile(croppedFile.path));
  } else {
    if (context.mounted) coverProvider.resetState();
  }
}

/// Opens the mentor's Facebook profile URL in the default browser.
Future<void> _openFacebookProfile(
  BuildContext context,
  UserProfileEntity profile,
) async {
  final facebookLink = profile.socialLinks.firstWhere(
    (link) =>
        link.platform.toLowerCase() == 'facebook' ||
        link.url.toLowerCase().contains('facebook.com'),
    orElse: () => const SocialLink(platform: '', url: ''),
  );

  if (facebookLink.url.isNotEmpty) {
    final uri = Uri.tryParse(facebookLink.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Minimal app bar shown while loading / error state.
class _LoadingAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _LoadingAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: const SizedBox.shrink(),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 24),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
