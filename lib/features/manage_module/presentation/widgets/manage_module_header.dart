import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:edtech/global/core/constants/images/images.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';

class ManageModuleHeader extends StatelessWidget {
  final ColorScheme cs;
  final Color iconBg;
  final VoidCallback onEditCourse;
  final String? thumbnailUrl;

  const ManageModuleHeader({
    super.key,
    required this.cs,
    required this.iconBg,
    required this.onEditCourse,
    this.thumbnailUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: 195,
          width: double.infinity,
          child: thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: thumbnailUrl!,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: cs.surfaceContainerHighest,
                ),
        ),
        Container(
          height: 195,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.15),
                Colors.white.withValues(alpha: 0.0),
                cs.brightness == Brightness.dark
                    ? Theme.of(context).scaffoldBackgroundColor
                    : Colors.white,
              ],
              stops: const [0.0, 0.85, 1.0],
            ),
          ),
        ),
        Positioned(top: 48, left: 12, child: const AppBackButton()),
        Positioned(
          top: 48,
          right: 12,
          child: CircleAvatar(
            backgroundColor: iconBg,
            child: IconButton(
              icon: Padding(
                padding: const EdgeInsets.all(3),
                child: SvgPicture.asset(
                  Images.editProfile,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    cs.onSurface,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              onPressed: onEditCourse,
            ),
          ),
        ),
      ],
    );
  }
}
