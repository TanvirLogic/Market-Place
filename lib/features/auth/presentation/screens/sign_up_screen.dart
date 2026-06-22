import 'package:edtech/app/app_colors.dart';
import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/services/toast_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/sign_up_provider.dart';
import '../../../../global/core/widgets/auth_button.dart';
import '../../../../global/core/widgets/app_back_button.dart';
import '../widgets/custom_text_field.dart';
import 'package:edtech/global/core/constants/sizes.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  static const String name = '/register';

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  String? _selectedGender;
  String _selectedRole = 'Student';

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const AppBackButton(),
                  const SizedBox(height: 20),
                  const _HeaderSection(),
                  const SizedBox(height: 32),
                  _RegistrationForm(
                    formKey: _formKey,
                    nameController: _nameController,
                    usernameController: _usernameController,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    phoneController: _phoneController,
                    ageController: _ageController,
                    selectedGender: _selectedGender,
                    selectedRole: _selectedRole,
                    onGenderChanged: (val) =>
                        setState(() => _selectedGender = val),
                    onRoleChanged: (val) => setState(() => _selectedRole = val),
                  ),
                  const SizedBox(height: 40),
                  const _FooterSection(),
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

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Create your account",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Join our community and get started",
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

class _RegistrationForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController usernameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController phoneController;
  final TextEditingController ageController;
  final String? selectedGender;
  final String selectedRole;
  final ValueChanged<String?> onGenderChanged;
  final ValueChanged<String> onRoleChanged;

  const _RegistrationForm({
    required this.formKey,
    required this.nameController,
    required this.usernameController,
    required this.emailController,
    required this.passwordController,
    required this.phoneController,
    required this.ageController,
    this.selectedGender,
    required this.selectedRole,
    required this.onGenderChanged,
    required this.onRoleChanged,
  });

  @override
  State<_RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<_RegistrationForm> {
  String? _emailError;
  final FocusNode _emailFocusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SignUpProvider>(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNameField(),
        const SizedBox(height: 20),
        _buildUsernameField(),
        const SizedBox(height: 20),
        _buildPhoneField(),
        const SizedBox(height: 20),
        _buildEmailField(),
        const SizedBox(height: 8),
        if (_emailError != null) _buildEmailErrorBanner(),
        const SizedBox(height: 20),
        _buildPasswordField(provider),
        const SizedBox(height: 20),
        _buildGenderField(cs),
        const SizedBox(height: 20),
        _buildAgeField(cs),
        const SizedBox(height: 20),
        _buildRoleSelector(),
        const SizedBox(height: 32),
        _buildRegisterButton(provider),
      ],
    );
  }

  Widget _buildNameField() {
    return CustomTextField(
      label: "Full name",
      hint: "Enter your name",
      isRequired: true,
      controller: widget.nameController,
      prefixIcon: const Icon(Icons.person_outline, size: 20),
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      validator: (value) {
        if (value == null || value.isEmpty)
          return 'Please enter your full name';
        if (value.trim().split(' ').length < 2)
          return 'Please enter at least two names';
        return null;
      },
      onChanged: _formatName,
    );
  }

  void _formatName(String value) {
    if (value.isNotEmpty) {
      final words = value.split(' ');
      final capitalizedWords = words.map((word) {
        if (word.isEmpty) return word;
        if (word.length == 1) return word.toUpperCase();
        return word[0].toUpperCase() + word.substring(1);
      }).toList();
      final formattedName = capitalizedWords.join(' ');
      if (widget.nameController.text != formattedName) {
        widget.nameController.value = TextEditingValue(
          text: formattedName,
          selection: widget.nameController.selection,
        );
      }
    }
  }

  Widget _buildUsernameField() {
    return CustomTextField(
      label: "Username",
      hint: "Enter your Username",
      isRequired: true,
      controller: widget.usernameController,
      prefixIcon: const Icon(Icons.alternate_email, size: 20),
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      validator: (value) {
        if (value == null || value.isEmpty) return 'Username is required';
        if (value.length < 3) return 'Username must be at least 3 characters';
        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value))
          return 'Only letters, numbers, and underscores allowed';
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return CustomTextField(
      label: "Phone Number",
      hint: "01XXXXXXXXX",
      isRequired: false,
      controller: widget.phoneController,
      keyboardType: TextInputType.phone,
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("+88", style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            const SizedBox(height: 24, child: VerticalDivider(thickness: 1)),
          ],
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Phone number is required';
        if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(value.trim()))
          return 'Enter a valid 11-digit Bangladeshi number';
        return null;
      },
    );
  }

  Widget _buildEmailField() {
    return CustomTextField(
      label: "Email",
      hint: "Enter your Email",
      isRequired: true,
      controller: widget.emailController,
      keyboardType: TextInputType.emailAddress,
      prefixIcon: const Icon(Icons.email_outlined, size: 20),
      focusNode: _emailFocusNode,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Email address is required';
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value))
          return 'Enter a valid email';
        if (_emailError != null) return _emailError;
        return null;
      },
    );
  }

  Widget _buildEmailErrorBanner() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'registered_email',
            widget.emailController.text.trim(),
          );
          if (!context.mounted) return;
          Navigator.pushNamed(
            context,
            AppRoutes.login,
            arguments: {'email': widget.emailController.text.trim()},
          );
        },
        child: Text(
          "Already have an account? Log in",
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(SignUpProvider provider) {
    return CustomTextField(
      label: "Password",
      hint: "Enter your Password",
      isRequired: true,
      isObscure: provider.isPasswordObscure,
      controller: widget.passwordController,
      prefixIcon: const Icon(Icons.lock_outline, size: 20),
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      suffixIcon: IconButton(
        onPressed: () => provider.togglePasswordVisibility(),
        icon: Icon(
          provider.isPasswordObscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Password is required';
        if (value.length < 8) return 'Password should be at least 8 characters';
        if (!value.contains(RegExp(r'[A-Z]')))
          return 'Add at least one uppercase letter';
        if (!value.contains(RegExp(r'[0-9]'))) return 'Add at least one number';
        return null;
      },
    );
  }

  Widget _buildGenderField(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InputLabel(label: "Gender", isRequired: true),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: widget.selectedGender,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            fillColor: AppColors.fill,
            hintText: "Select your gender",
            hintStyle: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusDef),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusDef),
              borderSide: const BorderSide(color: AppColors.border, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusDef),
              borderSide: BorderSide(color: AppColors.themeColor, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusDef),
              borderSide: const BorderSide(
                color: Color(0xFFEF4444),
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusDef),
              borderSide: const BorderSide(
                color: Color(0xFFEF4444),
                width: 1.5,
              ),
            ),
            errorStyle: const TextStyle(fontSize: 12, color: Colors.redAccent),
          ),
          validator: (value) {
            if (value == null || value.isEmpty)
              return 'Please select your gender';
            return null;
          },
          dropdownColor: Colors.white,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
          items: ['Male', 'Female']
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Row(
                    children: [
                      Icon(
                        e == 'Male' ? Icons.male : Icons.female,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 12),
                      Text(e),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: widget.onGenderChanged,
        ),
      ],
    );
  }

  Widget _buildAgeField(ColorScheme cs) {
    return CustomTextField(
      label: "Date of Birth",
      hint: "Select your Date of Birth",
      isRequired: true,
      controller: widget.ageController,
      readOnly: true,
      prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
      onTap: () => _showDatePicker(cs),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Date of Birth is required';
        return null;
      },
    );
  }

  void _showDatePicker(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusLg2),
        ),
      ),
      builder: (BuildContext context) {
        return Container(
          height: 450,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSizes.radiusLg2),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Select Date of Birth",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme(
                      brightness: cs.brightness,
                      primary: AppColors.themeColor,
                      onPrimary: cs.onPrimary,
                      secondary: cs.secondary,
                      onSecondary: cs.onSecondary,
                      error: cs.error,
                      onError: cs.onError,
                      surface: cs.surface,
                      onSurface: cs.onSurface,
                    ),
                  ),
                  child: CalendarDatePicker(
                    initialDate: widget.ageController.text.isNotEmpty
                        ? DateTime.parse(widget.ageController.text)
                        : DateTime.now().subtract(
                            const Duration(days: 365 * 18),
                          ),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    onDateChanged: (DateTime picked) {
                      widget.ageController.text =
                          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InputLabel(label: "Role", isRequired: true),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                label: "Student",
                isSelected: widget.selectedRole == 'Student',
                onTap: () => widget.onRoleChanged('Student'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _RoleCard(
                label: "Mentor",
                isSelected: widget.selectedRole == 'Mentor',
                onTap: () => widget.onRoleChanged('Mentor'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRegisterButton(SignUpProvider provider) {
    return AuthButton(
      text: "Register",
      isLoading: provider.inProgress,
      onPressed: () async {
        setState(() => _emailError = null);

        // if (widget.nameController.text.trim().isEmpty) {
        //   ToastService.showError('Full name is required');
        //   return;
        // }
        // if (widget.usernameController.text.trim().isEmpty) {
        //   ToastService.showError('Username is required');
        //   return;
        // }
        // if (widget.emailController.text.trim().isEmpty) {
        //   ToastService.showError('Email is required');
        //   return;
        // }
        // if (widget.passwordController.text.isEmpty) {
        //   ToastService.showError('Password is required');
        //   return;
        // }
        // if (widget.ageController.text.isEmpty) {
        //   ToastService.showError('Date of Birth is required');
        //   return;
        // }
        // if (widget.selectedGender == null) {
        //   ToastService.showError('Please select your gender');
        //   return;
        // }

        if (widget.formKey.currentState!.validate()) {
          final genderInt = (widget.selectedGender == 'Male') ? 1 : 0;
          final roleEnum = widget.selectedRole.toUpperCase();

          final success = await provider.register(
            name: widget.nameController.text.trim(),
            username: widget.usernameController.text.trim(),
            email: widget.emailController.text.trim(),
            dob: widget.ageController.text,
            password: widget.passwordController.text,
            phone: widget.phoneController.text.trim().isEmpty
                ? null
                : widget.phoneController.text.trim(),
            gender: genderInt,
            role: roleEnum,
          );

          if (context.mounted) {
            if (success) {
              Navigator.pushNamed(
                context,
                AppRoutes.verification,
                arguments: {
                  'type': 'registration',
                  'email': widget.emailController.text.trim(),
                },
              );
            } else {
              final errorMsg = provider.errorMessage?.toLowerCase() ?? '';
              if (errorMsg.contains('email') &&
                  (errorMsg.contains('exists') ||
                      errorMsg.contains('registered') ||
                      errorMsg.contains('already'))) {
                setState(
                  () => _emailError = 'This email is already registered',
                );
                FocusScope.of(context).requestFocus(_emailFocusNode);
                widget.formKey.currentState!.validate();
              } else {
                if (provider.errorMessage != null)
                  ToastService.showError(provider.errorMessage!);
              }
            }
          }
        }
      },
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scBg = Theme.of(context).scaffoldBackgroundColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: scBg,
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          border: Border.all(
            color: isSelected ? AppColors.themeColor : AppColors.border,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? AppColors.themeColor
                  : cs.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  final String label;
  final bool isRequired;
  const _InputLabel({required this.label, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        children: isRequired
            ? [
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red),
                ),
              ]
            : [],
      ),
    );
  }
}

class _FooterSection extends StatelessWidget {
  const _FooterSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Already have an account? ",
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Text(
            "Log in",
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
