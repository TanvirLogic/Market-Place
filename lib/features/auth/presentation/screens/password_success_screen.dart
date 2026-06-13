import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sign_in_provider.dart';
import '../../../../global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/constants/sizes.dart';

class PasswordSuccessScreen extends StatelessWidget {
  const PasswordSuccessScreen({super.key});
  static const String name = '/password-success';

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final title = args?['title'] as String? ?? "Congrats!";
    final subtitle = args?['subtitle'] as String? ?? "Your operation was completed successfully.";
    final buttonText = args?['buttonText'] as String? ?? "Continue";
    final email = args?['email'] as String?;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Expanded(flex: 2, child: SizedBox.shrink()),
                      const _SuccessIllustration(),
                      const SizedBox(height: 60),
                      _SuccessMessage(title: title, subtitle: subtitle),
                      const Expanded(flex: 3, child: SizedBox.shrink()),
                      AuthButton(
                        text: buttonText,
                        onPressed: () async {
                          final provider = context.read<SignInProvider>();
                          final userEmail = provider.user?.email ?? email;
                          Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false, arguments: userEmail != null ? {'email': userEmail} : null);
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SuccessIllustration extends StatelessWidget {
  const _SuccessIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(child: Container(height: 280, width: 280, child: Image.asset(Images.passwordSuccess)));
  }
}

class _SuccessMessage extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SuccessMessage({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, height: 1.2, color: cs.onSurface)),
      const SizedBox(height: 16),
      Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 14, height: 1.5)),
    ]);
  }
}
