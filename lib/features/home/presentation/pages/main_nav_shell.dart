import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../global/core/constants/images/images.dart';
import 'package:edtech/app/app_colors.dart';
import '../../../social/presentation/pages/social_page.dart';
import 'package:edtech/features/courses/presentation/screens/courses_screen.dart';
import 'package:edtech/features/hub/presentation/screens/hub_screen.dart';
import '../widgets/post_options_overlay.dart';

class MainNavShell extends StatefulWidget {
  const MainNavShell({super.key});
  static const String name = '/home';

  @override
  State<MainNavShell> createState() => _MainNavShellState();
}

class _MainNavShellState extends State<MainNavShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    SocialPage(),
    SizedBox.shrink(),
    CoursesScreen(),
    HubScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.onSurface.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.themeColor,
                );
              }
              return TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.6),
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              if (index == 1) {
                PostOptionsOverlay.show(context);
              } else {
                setState(() => _currentIndex = index);
              }
            },
            elevation: 0,
            backgroundColor: Colors.transparent,
            indicatorColor: Colors.transparent,
            destinations: [
              _navDestination(Images.navSocial, 'Social', cs),
              _navDestination(Images.navPost, 'Post', cs),
              _navDestination(Images.navCourses, 'Courses', cs),
              _navDestination(Images.navHub, 'Hub', cs),
            ],
          ),
        ),
      ),
    );
  }

  NavigationDestination _navDestination(String icon, String label, ColorScheme cs) {
    return NavigationDestination(
      icon: SvgPicture.asset(
        icon,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          cs.onSurface.withValues(alpha: 0.6),
          BlendMode.srcIn,
        ),
      ),
      selectedIcon: SvgPicture.asset(
        icon,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          AppColors.themeColor,
          BlendMode.srcIn,
        ),
      ),
      label: label,
    );
  }
}
