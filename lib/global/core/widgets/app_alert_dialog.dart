import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class AppAlertDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? contentWidget;
  final String? confirmText;
  final String? cancelText;
  final Color? confirmColor;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final Widget? headerIcon;

  const AppAlertDialog({
    super.key,
    required this.title,
    this.content,
    this.contentWidget,
    this.confirmText,
    this.cancelText,
    this.confirmColor,
    this.onConfirm,
    this.onCancel,
    this.headerIcon,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    String content = '',
    Widget? contentWidget,
    String? confirmText,
    String? cancelText,
    Color? confirmColor,
    Widget? headerIcon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: title,
        content: content,
        contentWidget: contentWidget,
        confirmText: confirmText,
        cancelText: cancelText,
        confirmColor: confirmColor,
        headerIcon: headerIcon,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
  }

  static Future<String?> showInput({
    required BuildContext context,
    required String title,
    String? initialValue,
    String hintText = '',
    String? confirmText,
    String? cancelText,
    Color? confirmColor,
    Widget? headerIcon,
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: title,
        contentWidget: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) {
              Navigator.pop(ctx, trimmed);
            }
          },
          decoration: InputDecoration(
            hintText: hintText,
            border: InputBorder.none,
          ),
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(ctx).colorScheme.onSurface,
          ),
        ),
        confirmText: confirmText ?? 'Save',
        cancelText: cancelText ?? 'Cancel',
        confirmColor: confirmColor ?? AppColors.themeColor,
        headerIcon: headerIcon,
        onConfirm: () {
          final trimmed = controller.text.trim();
          if (trimmed.isNotEmpty) {
            Navigator.pop(ctx, trimmed);
          }
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  static const Color _cancelFill = Color(0xFFEDEDED);
  static const Color _cancelText = Color(0xFF6C6C6C);
  static const Color _deleteFill = Color(0xFFC53030);
  static const Color _deleteStroke = Color(0xFFEBADAD);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg2),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // if (headerIcon != null) ...[headerIcon!, const SizedBox(width: 8)],
          SvgPicture.asset(
            'assets/images/icons/action/danger.svg',
            width: 20,
            height: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Danger',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFC53030),
            ),
          ),
        ],
      ),
      content:
          contentWidget ??
          (content != null
              ? Text(
                  content!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: cs.onSurface),
                )
              : null),
      actions: [
        Row(
          children: [
            if (cancelText != null) ...[
              Expanded(
                child: _DialogButton(
                  text: cancelText!,
                  fillColor: _cancelFill,
                  textColor: _cancelText,
                  onPressed: onCancel,
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (confirmText != null)
              Expanded(
                child: _DialogButton(
                  text: confirmText!,
                  fillColor: confirmColor ?? _deleteFill,
                  strokeColor: confirmColor == null ? _deleteStroke : null,
                  onPressed: onConfirm,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String text;
  final Color? fillColor;
  final Color? strokeColor;
  final Color textColor;
  final VoidCallback? onPressed;

  const _DialogButton({
    required this.text,
    this.fillColor,
    this.strokeColor,
    this.textColor = Colors.white,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      height: 40,
      child: Material(
        borderRadius: BorderRadius.circular(30),
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: fillColor?.withValues(alpha: disabled ? 0.5 : 1) ?? Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            border: strokeColor != null
                ? Border.all(color: strokeColor!)
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: disabled ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: disabled ? 0.5 : 1),
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
