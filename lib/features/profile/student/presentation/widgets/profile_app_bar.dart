import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:edtech/features/profile/student/providers/student_profile_provider.dart';

/// Custom app bar for the profile page with back button and edit action.
class ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ProfileAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scBg = Theme.of(context).scaffoldBackgroundColor;
    final iconBg = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFF5F5F5)
        : cs.surfaceContainerHighest;
    final profileName = context.watch<StudentProfileProvider>().profile?.name;
    return SafeArea(
      child: AppBar(
        backgroundColor: scBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          profileName ?? 'Profile',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: CircleAvatar(
            backgroundColor: iconBg,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 14, color: cs.onSurface),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundColor: iconBg,
              child: IconButton(
                icon: Padding(
                  padding: const EdgeInsets.all(3),
                  child: SvgPicture.asset(
                    Images.edit_profile,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(cs.onSurface, BlendMode.srcIn),
                  ),
                ),
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.editProfilePage);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
