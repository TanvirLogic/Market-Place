import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/features/profile/shared/widgets/loading_app_bar.dart';
import 'package:edtech/features/profile/shared/helpers/profile_helpers.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import 'package:edtech/features/profile/student/providers/student_profile_provider.dart';
import 'package:edtech/global/core/providers/video_player_provider.dart';
import '../widgets/completed_courses_list.dart';
import '../widgets/profile_app_bar.dart';
import '../widgets/profile_header_card.dart';
import '../widgets/section_header.dart';
import '../widgets/skill_badges_row.dart';
import '../widgets/social_links_row.dart';
import '../widgets/video_list_section.dart';

/// Student profile page rendered from the provider's [UserProfileEntity].
///
/// Videos, courses, and social platforms are read directly from the
/// [StudentProfileProvider] which fetches data from the `profile/me` endpoint.
class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});
  static const String name = '/profile';

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch profile data on page load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentProfileProvider>().fetchProfile();

      // ── Set up avatar upload success callback ──
      context.read<AvatarUploadProvider>().onUploadSuccess = (newAvatarUrl) {
        final currentProfile = context.read<StudentProfileProvider>().profile;
        if (currentProfile != null) {
          context.read<StudentProfileProvider>().fetchProfile();
        }
      };
    });
  }

  @override
  void dispose() {
    context.read<VideoPlayerProvider>().dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        context.read<VideoPlayerProvider>().dismiss();
      },
      child: Consumer<StudentProfileProvider>(
      builder: (context, provider, _) {
        // ── No profile loaded yet: loading or error ──
        if (provider.profile == null) {
          // Error state
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

          // Loading or initial idle state
          return Scaffold(
            appBar: const LoadingAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // ── Profile data available ──
        return _ProfileBody(profile: provider.profile!);
      },
      ),
    );
  }
}

/// Main profile body rendered once data is available.
class _ProfileBody extends StatelessWidget {
  final UserProfileEntity profile;

  const _ProfileBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ProfileAppBar(),
      body: RefreshIndicator(
        color: AppColors.themeColor,
        onRefresh: () => context.read<StudentProfileProvider>().fetchProfile(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 24,
          ),
          children: [
            ProfileHeaderCard(
              student: profile,
              onAvatarTap: () => showAvatarOptions(context, profile, heroTag: 'student_avatar'),
            ),
            const SizedBox(height: 12),
            const SectionHeader(title: 'Skill Badges'),
            const SkillBadgesRow(),
            if (profile.socialLinks.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionHeader(title: 'Social Links'),
              SocialLinksRow(socialLinks: profile.socialLinks),
            ],
            if (profile.videos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionHeader(title: 'Videos'),
              VideosHorizontalListView(videos: profile.videos),
            ],
            if (profile.courses.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionHeader(title: 'Completed Courses'),
              CompletedCoursesVerticalListView(courses: profile.courses),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}


