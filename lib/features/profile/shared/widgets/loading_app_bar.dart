import 'package:flutter/material.dart';

class LoadingAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LoadingAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: const Padding(
        padding: EdgeInsets.only(left: 24),
        child: SizedBox.shrink(),
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 24),
          child: SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
