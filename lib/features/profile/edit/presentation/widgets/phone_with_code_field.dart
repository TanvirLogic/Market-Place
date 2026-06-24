import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edtech/features/profile/edit/data/country.dart';

class PhoneWithCodeField extends StatelessWidget {
  final TextEditingController controller;
  final Country? selectedCountry;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const PhoneWithCodeField({
    super.key,
    required this.controller,
    this.selectedCountry,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dialCode = selectedCountry?.dialCode ?? '+1';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone Number',
          style: TextStyle(fontSize: 14, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          onChanged: onChanged,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(15),
          ],
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            filled: true,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dialCode,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Image.network(
                      selectedCountry?.flagPng ?? '',
                      width: 20,
                      height: 14,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 20, height: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 24,
                    child: VerticalDivider(
                      thickness: 1,
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            errorText: errorText,
            errorMaxLines: 2,
            errorStyle: TextStyle(
              fontSize: 11,
              color: cs.error,
              fontWeight: FontWeight.w400,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.outlineVariant, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.error, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: cs.error, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
