import 'package:flutter/material.dart';
import 'package:edtech/app/app_colors.dart';

/// Displays the mentor's name, username, and role.
class MentorIdentityHeader extends StatelessWidget {
  final String name;
  final String username;
  final String role;

  const MentorIdentityHeader({
    super.key,
    required this.name,
    required this.username,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      spacing: 2,
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        Text(
          "@$username",
          style: TextStyle(
            color: AppColors.themeColor,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        Text(
          role.isNotEmpty ? role : 'No Profession added yet',
          style: TextStyle(
            color: role.isNotEmpty ? cs.onSurface : cs.onSurface.withValues(alpha: 0.4),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
