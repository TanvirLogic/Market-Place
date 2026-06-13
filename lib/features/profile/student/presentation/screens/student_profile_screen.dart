import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import '../../../avatar/presentation/widgets/avatar_options_bottom_sheet.dart';
import '../../../avatar/presentation/widgets/custom_crop_screen.dart';
import 'package:edtech/features/profile/avatar/presentation/screens/full_screen_image_viewer_screen.dart';
import 'package:edtech/features/profile/student/providers/student_profile_provider.dart';
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
  Widget build(BuildContext context) {
    return Consumer<StudentProfileProvider>(
      builder: (context, provider, _) {
        // ── No profile loaded yet: loading or error ──
        if (provider.profile == null) {
          // Error state
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

          // Loading or initial idle state
          return Scaffold(
            appBar: const _LoadingAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // ── Profile data available ──
        return _ProfileBody(profile: provider.profile!);
      },
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
              onAvatarTap: () => _showAvatarOptions(context, profile),
            ),
            const SizedBox(height: 12),
            const SectionHeader(title: 'Skill Badges'),
            const SkillBadgesRow(),
            if (profile.socialLinks.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SectionHeader(title: 'Social Links'),
              SocialLinksRow(socialLinks: profile.socialLinks),
            ],
            const SizedBox(height: 12),
            const SectionHeader(title: 'Videos'),
            VideosHorizontalListView(videos: profile.videos),
            const SizedBox(height: 12),
            const SectionHeader(title: 'Completed Courses'),
            CompletedCoursesVerticalListView(courses: profile.courses),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Shows the avatar options bottom sheet (Facebook / View / Upload).
Future<void> _showAvatarOptions(
  BuildContext context,
  UserProfileEntity profile,
) async {
  final option = await showAvatarOptionsBottomSheet(
    context: context,
    currentImageUrl: profile.avatarUrl,
    isAvatar: true,
  );

  if (option == null || context.mounted == false) return;

  switch (option) {
    case AvatarOption.facebook:
      _openFacebookProfile(context, profile);
    case AvatarOption.view:
      if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenImageViewerScreen(
              imageUrl: profile.avatarUrl!,
              heroTag: 'student_avatar',
            ),
          ),
        );
      }
    case AvatarOption.upload:
      await _pickAndCropThenUpload(context, profile);
  }
}

/// Pick image at full phone quality → show custom crop UI → upload.
Future<void> _pickAndCropThenUpload(
  BuildContext context,
  UserProfileEntity profile,
) async {
  final provider = context.read<AvatarUploadProvider>();

  // 1. Pick at full phone quality (no downsampling).
  final pickedFile = await provider.pickImage();
  if (pickedFile == null || !context.mounted) return;

  // 2. Navigate to custom crop screen.
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

  // 3. Upload the cropped result.
  if (croppedFile != null && context.mounted) {
    await provider.uploadAvatarFromFile(XFile(croppedFile.path));
  } else {
    // User cancelled the crop screen — reset provider state to unblock
    // future upload attempts.
    if (context.mounted) provider.resetState();
  }
}

/// Opens the user's Facebook profile URL, or shows a toast if none is set.
Future<void> _openFacebookProfile(
  BuildContext context,
  UserProfileEntity profile,
) async {
  // Try to find a Facebook link in the user's social links
  final facebookLink = profile.socialLinks
      .where((link) => link.platform.toLowerCase() == 'facebook')
      .firstOrNull;

  if (facebookLink != null && facebookLink.url.isNotEmpty) {
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
