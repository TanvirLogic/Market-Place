import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/features/profile/avatar/presentation/widgets/avatar_options_bottom_sheet.dart';
import 'package:edtech/features/profile/avatar/presentation/widgets/custom_crop_screen.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';

Future<void> showAvatarOptions(
  BuildContext context,
  UserProfileEntity profile, {
  required String heroTag,
}) async {
  final option = await showAvatarOptionsBottomSheet(
    context: context,
    currentImageUrl: profile.avatarUrl,
    isAvatar: true,
  );

  if (option == null) return;
  if (!context.mounted) return;

  switch (option) {
    case AvatarOption.facebook:
      await openFacebookProfile(context, profile);
    case AvatarOption.view:
      if (profile.avatarUrl == null || profile.avatarUrl!.isEmpty) return;
      Navigator.pushNamed(
        context,
        AppRoutes.fullScreenImage,
        arguments: {'imageUrl': profile.avatarUrl, 'heroTag': heroTag},
      );
    case AvatarOption.upload:
      await pickAndCropAvatar(context);
  }
}

Future<void> pickAndCropAvatar(BuildContext context) async {
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

  if (croppedFile != null && context.mounted) {
    await avatarProvider.uploadAvatarFromFile(XFile(croppedFile.path));
  } else if (context.mounted) {
    avatarProvider.resetState();
  }
}

Future<void> openFacebookProfile(
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
