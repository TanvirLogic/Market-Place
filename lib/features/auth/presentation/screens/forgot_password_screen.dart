import 'dart:async';

import 'package:edtech/app/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/password_reset_provider.dart';
import '../widgets/custom_text_field.dart';
import '../../../../global/core/widgets/app_back_button.dart';
import '../../../../global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/constants/sizes.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  static const String name = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Timer? _errorTimer;

  void _scheduleErrorClear() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _formKey.currentState?.reset();
    });
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _handleForgotPassword() async {
    if (!_formKey.currentState!.validate()) {
      _scheduleErrorClear();
      return;
    }
    final email = _emailController.text.trim();

    final provider = context.read<PasswordResetProvider>();
    final success = await provider.forgotPassword(email);

    if (mounted && success) {
      Navigator.pushNamed(context, AppRoutes.resetVerification);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const AppBackButton(),
                const SizedBox(height: 40),
                const _HeaderSection(),
                const SizedBox(height: 32),
                Form(
                  key: _formKey,
                  child: _ForgotForm(emailController: _emailController, onSendPressed: _handleForgotPassword),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Forgot Password?", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 12),
        Text("Don't worry! It happens. Please enter your details.", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14, height: 1.5)),
      ],
    );
  }
}

class _ForgotForm extends StatelessWidget {
  final TextEditingController emailController;
  final VoidCallback onSendPressed;
  const _ForgotForm({required this.emailController, required this.onSendPressed});

  @override
  Widget build(BuildContext context) {
    final passwordResetProvider = Provider.of<PasswordResetProvider>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          label: "Email Address",
          hint: "joy411935@gmail.com",
          isRequired: true,
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.isEmpty) return 'Email address is required';
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return 'Please enter a valid email address';
            return null;
          },
        ),
        const SizedBox(height: 20),
        Text("We'll send you a verification code to reset your password.", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 32),
        AuthButton(text: "Send Verification Code", isLoading: passwordResetProvider.isLoading, onPressed: onSendPressed),
      ],
    );
  }
}
