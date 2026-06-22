import 'dart:async';

import 'package:edtech/app/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/password_reset_provider.dart';
import '../../../../global/core/widgets/app_back_button.dart';
import '../../../../global/core/widgets/auth_button.dart';
import '../widgets/otp_input_widget.dart';
import 'package:edtech/global/core/constants/sizes.dart';

class ResetVerificationScreen extends StatefulWidget {
  const ResetVerificationScreen({super.key});
  static const String name = '/reset-verification';

  @override
  State<ResetVerificationScreen> createState() => _ResetVerificationScreenState();
}

class _ResetVerificationScreenState extends State<ResetVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  String? _otpError;
  Timer? _errorTimer;

  void _scheduleErrorClear() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _otpError = null);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PasswordResetProvider>().startResendTimer();
    });
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    for (var controller in _controllers) { controller.dispose(); }
    for (var node in _focusNodes) { node.dispose(); }
    super.dispose();
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    final passwordResetProvider = Provider.of<PasswordResetProvider>(context);

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
                _HeaderSection(email: passwordResetProvider.resetEmail ?? ""),
                const SizedBox(height: 40),
                OtpInputRow(controllers: _controllers, focusNodes: _focusNodes),
                const SizedBox(height: 8),
                if (_otpError != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(_otpError!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ),
                const SizedBox(height: 16),
                const _ResendTimer(),
                const SizedBox(height: 40),
                AuthButton(
                  text: "Verify",
                  isLoading: passwordResetProvider.isLoading,
                  onPressed: () async {
                    if (_otpCode.length == 6) {
                      final email = passwordResetProvider.resetEmail ?? "";
                      final success = await passwordResetProvider.verifyResetOtp(email, _otpCode);
                      if (context.mounted && success) {
                        Navigator.pushNamed(context, AppRoutes.resetPassword);
                      }
                    } else {
                      setState(() => _otpError = "Please enter the 6-digit code");
                      _scheduleErrorClear();
                    }
                  },
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
  final String email;
  const _HeaderSection({required this.email});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Verify Reset Code", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 12),
        Text("Enter the six digit security code we sent to\n$email", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14, height: 1.5)),
      ],
    );
  }
}

class _ResendTimer extends StatelessWidget {
  const _ResendTimer();

  @override
  Widget build(BuildContext context) {
    return Consumer<PasswordResetProvider>(
      builder: (context, provider, _) {
        return Center(
          child: GestureDetector(
            onTap: provider.canResendCode ? () async { provider.startResendTimer(); await provider.forgotPassword(provider.resetEmail ?? ""); } : null,
            child: Text(provider.canResendCode ? "Resend Code" : "Resend in ${provider.resendTimerSeconds}s",
              style: TextStyle(color: provider.canResendCode ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        );
      },
    );
  }
}
