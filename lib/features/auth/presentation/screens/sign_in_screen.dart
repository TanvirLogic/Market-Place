import 'dart:async';

import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/sign_in_provider.dart';
import '../../../../global/core/widgets/auth_button.dart';
import '../widgets/custom_text_field.dart';
import 'package:edtech/global/core/constants/sizes.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  static const String name = '/login';

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    _checkAutoFillEmail();
  }

  void _scheduleErrorClear() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _formKey.currentState?.reset();
    });
  }

  void _checkAutoFillEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString('last_used_email');
    if (cachedEmail != null && mounted) {
      _emailController.text = cachedEmail;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args.containsKey('email')) {
        _emailController.text = args['email'];
      }
    });
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      _errorTimer?.cancel();
      final provider = context.read<SignInProvider>();
      final success = await provider.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (mounted) {
        if (success) {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        } else if (provider.errorMessage == 'EMAIL_NOT_VERIFIED') {
          Navigator.pushNamed(
            context,
            AppRoutes.verification,
            arguments: {
              'type': 'registration',
              'email': _emailController.text.trim(),
            },
          );
        }
      }
    } else {
      _scheduleErrorClear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.horizontalPadding,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _AppLogo(),
                  const SizedBox(height: 32),
                  const _WelcomeText(),
                  const SizedBox(height: 40),
                  _LoginForm(
                    emailController: _emailController,
                    passwordController: _passwordController,
                    onLoginPressed: _handleLogin,
                  ),
                  const SizedBox(height: 24),
                  const _SocialDivider(),
                  const SizedBox(height: 24),
                  const _GoogleButton(),
                  const SizedBox(height: 40),
                  const _Footer(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
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

class _WelcomeText extends StatelessWidget {
  const _WelcomeText();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Welcome back!", style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 8),
            Text("👋", style: const TextStyle(fontSize: 24)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Sign in to continue to your account",
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _LoginForm extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onLoginPressed;

  const _LoginForm({
    required this.emailController,
    required this.passwordController,
    required this.onLoginPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          label: "Email",
          hint: "e.g. name@example.com",
          isRequired: true,
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: const Icon(Icons.email_outlined, size: 20),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Email address cannot be empty';
            }
            final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
            if (!emailRegex.hasMatch(value)) {
              return 'Please enter a valid email (e.g., name@example.com)';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        Consumer<SignInProvider>(
          builder: (context, authProvider, _) => CustomTextField(
            label: "Password",
            hint: "••••••••",
            isRequired: true,
            isObscure: authProvider.isPasswordObscure,
            controller: passwordController,
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
            suffixIcon: IconButton(
              onPressed: () => authProvider.togglePasswordVisibility(),
              icon: Icon(
                authProvider.isPasswordObscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Password is required to sign in';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters long';
              }
              if (value.contains(' ')) {
                return 'Password cannot contain spaces';
              }
              return null;
            },
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.forgotPassword);
            },
            child: Text(
              "Forgot Password?",
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Consumer<SignInProvider>(
          builder: (context, authProvider, _) => AuthButton(
            text: "Login",
            isLoading: authProvider.inProgress,
            onPressed: authProvider.isGoogleLoading ? () {} : onLoginPressed,
          ),
        ),
      ],
    );
  }
}

class _SocialDivider extends StatelessWidget {
  const _SocialDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Theme.of(context).dividerColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "or continue with",
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(child: Divider(color: Theme.of(context).dividerColor)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<SignInProvider>(
      builder: (context, authProvider, _) => SizedBox(
        width: double.infinity,
        height: 56,
        child: OutlinedButton(
          onPressed: authProvider.isGoogleLoading || authProvider.inProgress
              ? null
              : () async {
                  final idToken = await authProvider.getGoogleIdToken();
                  if (idToken == null || !context.mounted) return;

                  final statusCode = await authProvider.googleSignIn(idToken);
                  if (statusCode == null || !context.mounted) return;

                  if (statusCode == 200) {
                    Navigator.pushReplacementNamed(context, AppRoutes.home);
                    return;
                  }

                  if (statusCode == 202) {
                    if (!context.mounted) return;
                    Navigator.pushNamed(
                      context,
                      AppRoutes.roleSelection,
                      arguments: {'idToken': idToken},
                    );
                  }
                },
          style: OutlinedButton.styleFrom(
            backgroundColor: Theme.of(context).brightness == Brightness.light
                ? Colors.white
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: Theme.of(context).brightness == Brightness.light
                  ? Theme.of(context).colorScheme.outlineVariant
                  : Colors.transparent,
              width: 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (authProvider.isGoogleLoading)
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                )
              else ...[
                Image.asset(Images.googleIcon, height: 20),
                const SizedBox(width: 8),
                Text(
                  "Login with Google",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't have an account? ",
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.pushNamed(context, AppRoutes.register);
          },
          child: Text(
            "Create Account",
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
