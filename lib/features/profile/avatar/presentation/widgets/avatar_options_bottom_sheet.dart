import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';

enum AvatarOption { facebook, view, upload }

Future<AvatarOption?> showAvatarOptionsBottomSheet({
  required BuildContext context,
  required String? currentImageUrl,
  required bool isAvatar,
}) {
  final hasImage = currentImageUrl != null && currentImageUrl.isNotEmpty;

  return showModalBottomSheet<AvatarOption>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      final cs = Theme.of(context).colorScheme;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              if (hasImage) ...[
                _OptionTile(
                  icon: Icon(Icons.image_outlined, size: 24, color: AppColors.themeColor),
                  title: isAvatar ? 'View Profile Photo' : 'View Cover Photo',
                  subtitle: 'See the full-size image',
                  onTap: () => Navigator.pop(context, AvatarOption.view),
                  cs: cs,
                ),
                const SizedBox(height: 8),
              ],
              _OptionTile(
                icon: Icon(Icons.upload_outlined, size: 24, color: AppColors.themeColor),
                title: isAvatar ? 'Upload Photo' : 'Upload Cover',
                subtitle: 'Pick and crop a new image from your gallery',
                onTap: () => Navigator.pop(context, AvatarOption.upload),
                cs: cs,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class _OptionTile extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: cs.onSurface.withValues(alpha: 0.3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
