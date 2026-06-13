import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';

class AuthButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final double borderRadius;
  final double? fontSize;

  const AuthButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.height = 56,
    this.borderRadius = 30,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = isLoading || onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.themeColor,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: disabled ? null : onPressed,
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: disabled ? 0.5 : 1),
                        ),
                      ),
                    )
                  : Opacity(
                      opacity: disabled ? 0.5 : 1,
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: fontSize ?? 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: disabled ? 0.5 : 1),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
