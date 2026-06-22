import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/features/auth/presentation/widgets/custom_text_field.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/features/hub/providers/change_password_provider.dart';

class PasswordAndSecurityScreen extends StatefulWidget {
  const PasswordAndSecurityScreen({super.key});
  static const String name = '/password-and-security';

  @override
  State<PasswordAndSecurityScreen> createState() =>
      _PasswordAndSecurityScreenState();
}

class _PasswordAndSecurityScreenState extends State<PasswordAndSecurityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isCurrentObscure = true;
  bool _isNewObscure = true;
  bool _isConfirmObscure = true;
  String? _formError;
  Timer? _errorTimer;

  void _scheduleErrorClear() {
    _formError = null;
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _formKey.currentState?.reset();
    });
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool get _isPasswordFormFilled =>
      _currentPasswordController.text.isNotEmpty ||
      _newPasswordController.text.isNotEmpty ||
      _confirmPasswordController.text.isNotEmpty;

  bool get _isEmailFormFilled => _emailController.text.isNotEmpty;

  Future<void> _handleSubmit() async {
    _errorTimer?.cancel();
    if (_isPasswordFormFilled && _isEmailFormFilled) {
      setState(() => _formError = 'Fill in only one section at a time');
      _scheduleErrorClear();
      return;
    }

    if (_isPasswordFormFilled) {
      if (!_formKey.currentState!.validate()) {
        _scheduleErrorClear();
        return;
      }

      final provider = context.read<ChangePasswordProvider>();
      await provider.changePassword(
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      if (mounted && provider.errorMessage == null) {
        ToastService.showSuccess('Password changed successfully!');
        Navigator.pop(context);
      }
      return;
    }

    if (_isEmailFormFilled) {
      final provider = context.read<ChangePasswordProvider>();
      await provider.changeEmail(_emailController.text.trim());
      if (mounted && provider.errorMessage == null) {
        _emailController.clear();
      }
      return;
    }

    setState(() => _formError = 'Fill in a section to submit');
    _scheduleErrorClear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: AppBackButton(),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        'Change password',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use at least 8 characters with a mix of letters, numbers, and symbols.',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CustomTextField(
                        label: 'Current Password',
                        hint: '••••••••••••••',
                        isRequired: true,
                        isObscure: _isCurrentObscure,
                        controller: _currentPasswordController,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isCurrentObscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _isCurrentObscure = !_isCurrentObscure,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'Current password is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        label: 'New Password',
                        hint: '••••••••••••••',
                        isRequired: true,
                        isObscure: _isNewObscure,
                        controller: _newPasswordController,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isNewObscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _isNewObscure = !_isNewObscure),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'New password is required';
                          if (value.length < 8)
                            return 'Must be at least 8 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        label: 'Confirm Password',
                        hint: '••••••••••••••',
                        isRequired: true,
                        isObscure: _isConfirmObscure,
                        controller: _confirmPasswordController,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmObscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _isConfirmObscure = !_isConfirmObscure,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'Please confirm your password';
                          if (value != _newPasswordController.text)
                            return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
                Text(
                  'Change Email',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Update your email address securely',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                CustomTextField(
                  label: 'Confirm Email Address',
                  hint: 'Enter your new email',
                  isRequired: true,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 32),
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _formError!,
                      style: TextStyle(fontSize: 13, color: cs.error),
                    ),
                  ),
                Consumer<ChangePasswordProvider>(
                  builder: (context, provider, _) => AuthButton(
                    text: 'Submit',
                    isLoading: provider.isLoading,
                    onPressed: _handleSubmit,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
