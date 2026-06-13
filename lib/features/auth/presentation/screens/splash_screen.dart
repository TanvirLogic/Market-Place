import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sign_in_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const String name = '/';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _handleStartUp();
  }

  void _handleStartUp() async {
    await AuthController.getUserData();
    final provider = context.read<SignInProvider>();

    await Future.delayed(const Duration(seconds: 3));

    final bool isLoggedIn = await provider.tryRefreshToken();

    if (mounted) {
      if (isLoggedIn) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(Images.eduverseP, width: 200, height: 200, fit: BoxFit.contain, filterQuality: FilterQuality.high),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
