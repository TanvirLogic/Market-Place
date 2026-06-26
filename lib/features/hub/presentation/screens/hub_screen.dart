import 'package:edtech/features/hub/services/tawk_chat_service.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/widgets/app_alert_dialog.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/features/auth/providers/sign_in_provider.dart';
import 'package:edtech/features/profile/mentor/providers/mentor_profile_provider.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';
import 'package:edtech/features/profile/student/providers/student_profile_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/app/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});
  static const String name = '/hub';

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  bool _fetchTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProfile());
  }

  Future<void> _fetchProfile() async {
    if (_fetchTriggered) return;
    _fetchTriggered = true;

    try {
      final isMentor = AuthController.userModel?.isMentor ?? false;
      if (!mounted) return;
      if (isMentor) {
        context.read<MentorProfileProvider>().fetchProfile();
      } else {
        context.read<StudentProfileProvider>().fetchProfile();
      }
    } catch (_) {}
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await AppAlertDialog.show(
      context: context,
      title: 'Logout',
      content: 'Are you sure you want to logout?',
      confirmText: 'Logout',
      cancelText: 'Cancel',
    );
    if (confirmed == true) {
      context.read<StudentProfileProvider>().clearProfile();
      context.read<MentorProfileProvider>().clearProfile();
      _fetchTriggered = false;

      await context.read<SignInProvider>().logout();
      TawkChatService().logout();
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.login,
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final profile =
        context.watch<StudentProfileProvider>().profile ??
        context.watch<MentorProfileProvider>().profile;

    return SafeArea(
      child: PopScope(
        canPop: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: AppSizes.horizontalPadding,
            right: AppSizes.horizontalPadding,
            top: 8,
            bottom: 24,
          ),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HubHeader(cs: cs, isDark: isDark, profile: profile),
              const SizedBox(height: 16),
              _SettingsGroupCard(
                title: 'General Settings',
                backgroundColor: isDark ? cs.surfaceContainerLow : Colors.white,
                cs: cs,
                isDark: isDark,
                children: [
                  _MenuRowTile(
                    iconAsset: Images.hubProfileDetails,
                    label: 'Profile Details',
                    onTap: () => AppRoutes.navigateToProfile(
                      context,
                      AuthController.userModel?.isMentor == true
                          ? 'MENTOR'
                          : 'STUDENT',
                    ),
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                  _MenuRowTile(
                    iconAsset: Images.hubPasswordSecurity,
                    label: 'Password & Security',
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.passwordAndSecurity,
                    ),
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroupCard(
                title: 'Payment & Activity',
                backgroundColor: isDark ? cs.surfaceContainerLow : Colors.white,
                cs: cs,
                isDark: isDark,
                children: [
                  _MenuRowTile(
                    iconAsset: Images.hubMentorDashboard,
                    label: 'Mentor Dashboard',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.mentorDashboard),
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                  _MenuRowTile(
                    iconAsset: Images.hubTransaction,
                    label: 'Transactions & Revenue',
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.paymentsAndRevenue,
                    ),
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                  _MenuRowTile(
                    iconAsset: Images.hubAdAccount,
                    label: 'Ad Account',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.adsManager),
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroupCard(
                title: 'Personalize',
                backgroundColor: isDark ? cs.surfaceContainerLow : Colors.white,
                cs: cs,
                isDark: isDark,
                children: [
                  _ToggleRowTile(
                    iconAsset: Images.hubDarkMode,
                    label: 'Dark Mode',
                    value: context.watch<ThemeProvider>().isDarkMode,
                    onChanged: (_) =>
                        context.read<ThemeProvider>().toggleTheme(),
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                  _ToggleRowTile(
                    iconAsset: Images.hubNotification,
                    label: 'Notification',
                    value: true,
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                  _ToggleRowTile(
                    iconAsset: Images.hubMail,
                    label: 'Email Notification',
                    value: false,
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroupCard(
                title: 'Links',
                backgroundColor: isDark ? cs.surfaceContainerLow : Colors.white,
                cs: cs,
                isDark: isDark,
                children: [
                  _MenuRowTile(
                    icon: Icons.help_outline_rounded,
                    label: 'Terms & Policy',
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                  _MenuRowTile(
                    icon: Icons.headset_mic_outlined,
                    label: 'Help Center',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.helpCenter),
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                  _MenuRowTile(
                    icon: Icons.phone_android_rounded,
                    label: 'App Version',
                    // trailingText: 'v 2.37.0',
                    cs: cs,
                    isDark: isDark,
                    isGeneral: true,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _LogoutButton(
                cs: cs,
                isDark: isDark,
                onPressed: () => _showLogoutDialog(context),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubHeader extends StatelessWidget {
  final ColorScheme cs;
  final bool isDark;
  final UserProfileEntity? profile;

  const _HubHeader({required this.cs, required this.isDark, this.profile});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? 'User';
    final avatarUrl = profile?.avatarUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    color: isDark ? Colors.white : AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
          CircleAvatar(
            radius: 24,
            backgroundColor: cs.outlineVariant,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl == null
                ? ClipOval(
                    child: Image.asset(
                      Images.profileUser,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final ColorScheme cs;
  final bool isDark;
  final Color? backgroundColor;

  const _SettingsGroupCard({
    required this.title,
    required this.children,
    required this.cs,
    required this.isDark,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) => children[index],
          ),
        ],
      ),
    );
  }
}

class _MenuRowTile extends StatelessWidget {
  final IconData? icon;
  final String? iconAsset;
  final String label;
  final String? trailingText;
  final VoidCallback? onTap;
  final ColorScheme cs;
  final bool isDark;
  final bool isGeneral;

  const _MenuRowTile({
    this.icon,
    this.iconAsset,
    required this.label,
    this.trailingText,
    this.onTap,
    required this.cs,
    required this.isDark,
    this.isGeneral = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = iconAsset != null
        ? SvgPicture.asset(
            iconAsset!,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              isDark ? Colors.white : cs.onSurface,
              BlendMode.srcIn,
            ),
          )
        : Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.6));

    if (isGeneral) {
      return InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 313,
          height: 56,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? cs.surfaceContainerHighest
                : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
                  shape: BoxShape.circle,
                ),
                child: Center(child: iconWidget),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.primaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailingText != null)
                Text(
                  trailingText!,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap ?? () {},
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHighest : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
                shape: BoxShape.circle,
              ),
              child: Center(child: iconWidget),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : AppColors.primaryText,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              )
            else
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRowTile extends StatefulWidget {
  final String? iconAsset;
  final IconData? icon;
  final String label;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final ColorScheme cs;
  final bool isDark;
  final bool isGeneral;

  const _ToggleRowTile({
    this.iconAsset,
    this.icon,
    required this.label,
    this.value,
    this.onChanged,
    required this.cs,
    required this.isDark,
    this.isGeneral = false,
  });

  @override
  State<_ToggleRowTile> createState() => _ToggleRowTileState();
}

class _ToggleRowTileState extends State<_ToggleRowTile> {
  late bool _toggle;

  bool get _effectiveValue =>
      widget.onChanged != null ? (widget.value ?? false) : _toggle;

  @override
  void initState() {
    super.initState();
    _toggle = widget.value ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final iconWidget = widget.iconAsset != null
        ? SvgPicture.asset(
            widget.iconAsset!,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              widget.isDark ? Colors.white : widget.cs.onSurface,
              BlendMode.srcIn,
            ),
          )
        : Icon(
            widget.icon,
            size: 20,
            color: widget.cs.onSurface.withValues(alpha: 0.6),
          );

    if (widget.isGeneral) {
      return Container(
        width: 313,
        height: 56,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: widget.isDark
              ? widget.cs.surfaceContainerHighest
              : const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: widget.isDark
                ? widget.cs.outlineVariant
                : const Color(0xFFEFEFF0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isDark
                    ? widget.cs.outlineVariant
                    : const Color(0xFFEFEFF0),
                shape: BoxShape.circle,
              ),
              child: Center(child: iconWidget),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.isDark ? Colors.white : AppColors.primaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _CustomSwitch(
              value: _effectiveValue,
              onChanged: (value) {
                widget.onChanged?.call(value);
                if (widget.onChanged == null) {
                  setState(() => _toggle = value);
                }
              },
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isDark
            ? widget.cs.surfaceContainerHighest
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.isDark
                  ? widget.cs.outlineVariant
                  : const Color(0xFFEFEFF0),
              shape: BoxShape.circle,
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.white : AppColors.primaryText,
              ),
            ),
          ),
          _CustomSwitch(
            value: _effectiveValue,
            onChanged: (value) {
              widget.onChanged?.call(value);
              if (widget.onChanged == null) {
                setState(() => _toggle = value);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _CustomSwitch({required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged?.call(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 28,
        decoration: BoxDecoration(
          color: value ? AppColors.themeColor : const Color(0xFFEAECF0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final ColorScheme cs;
  final bool isDark;
  final VoidCallback? onPressed;

  const _LogoutButton({required this.cs, required this.isDark, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        backgroundColor: isDark
            ? cs.error.withValues(alpha: 0.18)
            : const Color(0xFFFCF3F3),
        side: BorderSide(
          color: isDark
              ? cs.error.withValues(alpha: 0.4)
              : const Color(0xFFEBADAD),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Logout',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? cs.error : const Color(0xFFC53030),
            ),
          ),
          const SizedBox(width: 8),
          SvgPicture.asset(
            Images.logout,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(
              isDark ? cs.error : const Color(0xFFC53030),
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    );
  }
}
