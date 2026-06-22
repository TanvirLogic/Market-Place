import 'dart:async';

import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/password_reset_provider.dart';
import '../../../../global/core/widgets/app_back_button.dart';
import '../../../../global/core/widgets/auth_button.dart';
import '../widgets/custom_text_field.dart';
import 'package:edtech/global/core/constants/sizes.dart';

class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key});
  static const String name = '/reset-password';

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
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
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      _errorTimer?.cancel();
      final passwordResetProvider = context.read<PasswordResetProvider>();
      final email = passwordResetProvider.resetEmail ?? '';
      final code = passwordResetProvider.resetCode ?? '';

      if (email.isEmpty || code.isEmpty) {
        ToastService.showError('Session expired. Please restart the forgot password process.');
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
        return;
      }

      final success = await passwordResetProvider.resetPassword(email, code, _passwordController.text);

      if (mounted && success) {
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.passwordSuccess, (route) => false, arguments: {
          'title': 'Password Changed!',
          'subtitle': 'Your password has been successfully reset. You can now use your new password to log in.',
          'buttonText': 'Back to Login',
        });
      }
    } else {
      _scheduleErrorClear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<PasswordResetProvider>();

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  const AppBackButton(),
                  const SizedBox(height: 40),
                  Text('Set new password', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.onSurface)),
                  const SizedBox(height: 12),
                  Text('Use at least 8 characters with a mix of letters, numbers, and symbols.', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 14, height: 1.5)),
                  const SizedBox(height: 32),
                  CustomTextField(label: 'New Password', hint: '••••••••', isRequired: true, isObscure: true, controller: _passwordController,
                    inputFormatters: [LengthLimitingTextInputFormatter(20)],
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'New password is required';
                      if (value.length < 8) return 'Password must be at least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  CustomTextField(label: 'Confirm Password', hint: '••••••••', isRequired: true, isObscure: true, controller: _confirmPasswordController,
                    inputFormatters: [LengthLimitingTextInputFormatter(20)],
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Confirm password is required';
                      if (value != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  AuthButton(text: 'Submit', isLoading: provider.isLoading, onPressed: _handleSubmit),
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
