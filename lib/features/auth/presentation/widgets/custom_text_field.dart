import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/constants/sizes.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Themed text field with autovalidate-on-interaction.
///
/// When [isRequired] is true, the validator returns null for empty fields
/// (no inline "required" message). Required checks are handled by submit
/// handlers via ToastService to keep the UI clean.
class CustomTextField extends StatelessWidget {
  final String label;
  final String hint;
  final bool isRequired;
  final bool isObscure;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final bool readOnly;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  const CustomTextField({
    super.key,
    required this.label,
    required this.hint,
    this.isRequired = false,
    this.isObscure = false,
    this.controller,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.readOnly = false,
    this.onTap,
    this.focusNode,
    this.onChanged,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: cs.onSurface,
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
        ),
        const SizedBox(height: 8),
        TextFormField(
          autovalidateMode: AutovalidateMode.onUserInteraction,
          controller: controller,
          obscureText: isObscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: (value) {
            if (value == null || value.isEmpty) return null;
            return validator?.call(value);
          },
          readOnly: readOnly,
          onTap: onTap,
          focusNode: focusNode,
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.brightness == Brightness.dark
                ? cs.surfaceContainerHighest
                : AppColors.fill,
            hintText: hint,
            hintStyle: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusDef),
              borderSide: BorderSide(
                color: cs.brightness == Brightness.dark
                    ? cs.outlineVariant
                    : AppColors.border,
                width: 1,
              ),
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
            errorStyle: TextStyle(
              fontSize: 12,
              color: cs.error.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}
