import 'package:edtech/features/profile/avatar/presentation/widgets/avatar_options_bottom_sheet.dart';
import 'package:edtech/features/profile/avatar/presentation/widgets/cover_reposition_screen.dart';
import 'package:edtech/features/profile/mentor/presentation/widgets/mentor_hero_banner.dart';
import 'package:edtech/features/profile/mentor/presentation/widgets/mentor_identity_header.dart';
import 'package:edtech/features/profile/mentor/presentation/widgets/mentor_metrics_bar.dart';
import 'package:edtech/app/app_routes.dart' show AppRoutes, routeObserver;
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:edtech/features/profile/avatar/providers/cover_upload_provider.dart';
import 'package:edtech/features/profile/shared/widgets/loading_app_bar.dart';
import 'package:edtech/features/profile/shared/helpers/profile_helpers.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import '../../../student/presentation/widgets/completed_courses_list.dart';
import '../../../student/presentation/widgets/section_header.dart';
import '../../../student/presentation/widgets/skill_badges_row.dart';
import '../../../student/presentation/widgets/social_links_row.dart';
import '../../../student/presentation/widgets/video_list_section.dart';
import 'package:edtech/features/profile/mentor/providers/mentor_profile_provider.dart';
import 'package:edtech/global/core/providers/video_player_provider.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';

/// Mentor profile page rendered from the provider's [UserProfileEntity].
class MentorProfileScreen extends StatefulWidget {
  final bool isOwnProfile;

  const MentorProfileScreen({super.key, this.isOwnProfile = true});

  @override
  State<MentorProfileScreen> createState() => _MentorProfileScreenState();
}

class _MentorProfileScreenState extends State<MentorProfileScreen>
    with RouteAware {
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPushNext() {
    context.read<VideoPlayerProvider>().pause();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        context.read<VideoPlayerProvider>().dismiss();
      },
      child: Consumer<MentorProfileProvider>(
      builder: (context, provider, _) {
        if (provider.profile == null) {
          if (provider.errorMessage != null) {
            return Scaffold(
              appBar: const LoadingAppBar(),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 48,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ToastService.friendlyMessage(provider.errorMessage!),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
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
            appBar: const LoadingAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return _MentorProfileBody(
          profile: provider.profile!,
          isOwnProfile: widget.isOwnProfile,
        );
      },
      ),
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
                onAvatarTap: isOwnProfile
                    ? () => showAvatarOptions(context, profile, heroTag: 'mentor_avatar')
                    : null,
                onCoverTap: isOwnProfile
                    ? () => _showCoverOptions(context, profile)
                    : null,
                onEdit: isOwnProfile
                    ? () => Navigator.pushNamed(
                        context,
                        AppRoutes.editProfilePage,
                      )
                    : null,
              ),
              const SizedBox(height: 45), // 12px between sections
              // ── Remaining content with 16px horizontal padding ──
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.horizontalPadding,
                ),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      )
                    else
                      Text(
                        "Tell others about your skills, interests, experiences and what you're currently learning.",
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 12),
                    // ── Section 4: Skill Badges (left-aligned under start) ──
                    if (profile.skills.isNotEmpty) ...[
                      const SectionHeader(title: 'Skill Badges'),
                      SkillBadgesRow(skills: profile.skills),
                    ],
                    if (profile.socialLinks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const SectionHeader(title: 'Social Links'),
                      SocialLinksRow(socialLinks: profile.socialLinks),
                    ],
                    const SizedBox(height: 12), // 12px between sections
                    // ── Section 6: Videos ──
                    if (profile.videos.isNotEmpty) ...[
                      const SectionHeader(title: 'Videos'),
                      VideosHorizontalListView(videos: profile.videos),
                    ],
                    // const SizedBox(height: 12), // 12px between sections
                    // ── Section 7: Completed Courses ──
                    if (profile.courses.isNotEmpty) ...[
                      const SectionHeader(title: 'Featured Courses'),
                      CompletedCoursesVerticalListView(
                        courses: profile.courses,
                        isMentorProfile: true,
                        isOwnProfile: isOwnProfile,
                        onActionPressed: (course) {
                          if (isOwnProfile) {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.manageModule,
                              arguments: {'courseId': course.id},
                            );
                          } else {
                            Navigator.pushNamed(context, AppRoutes.courseDetails);
                          }
                        },
                      ),
                    ],
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
/// Mentor-specific helpers (cover image is unique to mentor profile)
/// ─────────────────────────────────────────────────────────────────────────────

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
