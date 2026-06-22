import 'package:edtech/app/app_colors.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/features/auth/providers/sign_in_provider.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RoleSelectionScreen extends StatefulWidget {
  final String idToken;
  const RoleSelectionScreen({super.key, required this.idToken});
  static const String name = '/role-selection';

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  Future<void> _selectRole(String role) async {
    final provider = context.read<SignInProvider>();
    final success = await provider.completeGoogleSignIn(widget.idToken, role);
    if (!mounted) return;

    if (success) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.home,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          // padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBackButton(),
                _AppLogo(),
                SizedBox(
                  width: double.infinity,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusLg2),
                    ),
                    elevation: 0,
                    color: cs.surfaceContainerHighest,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 32,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _WelcomeText(),
                          const SizedBox(height: 32),
                          Text(
                            "Select how you want to use Eduverse",
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _RoleOptionCard(
                            icon: Icons.school_outlined,
                            title: "Student",
                            subtitle: "Join courses and learn",
                            onTap: () => _selectRole('STUDENT'),
                          ),
                          const SizedBox(height: 12),
                          _RoleOptionCard(
                            icon: Icons.auto_awesome,
                            title: "Mentor",
                            subtitle: "Create courses and teach",
                            onTap: () => _selectRole('MENTOR'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<SignInProvider>(
      builder: (context, provider, _) {
        final isLoading = provider.isGoogleLoading || provider.inProgress;
        return GestureDetector(
          onTap: isLoading ? null : onTap,
          child: AnimatedOpacity(
            opacity: isLoading ? 0.6 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                border: Border.all(
                  color: AppColors.themeColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: isLoading
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Icon(icon, color: AppColors.themeColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLoading)
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.themeColor,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WelcomeText extends StatelessWidget {
  const _WelcomeText();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("One Step Ahead!", style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Let's set up your account",
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 80,
        width: 80,
        child: Image.asset(
          Images.eduverseLogo,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
