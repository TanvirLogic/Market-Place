import 'package:edtech/app/app_routes.dart';
import 'package:edtech/app/app_theme.dart';
import 'package:edtech/app/providers/theme_provider.dart';
import 'package:edtech/features/auth/providers/sign_in_provider.dart';
import 'package:edtech/features/auth/providers/sign_up_provider.dart';
import 'package:edtech/features/auth/providers/verify_otp_provider.dart';
import 'package:edtech/features/auth/providers/password_reset_provider.dart';
import 'package:edtech/features/profile/student/providers/student_profile_provider.dart';
import 'package:edtech/features/profile/mentor/providers/mentor_profile_provider.dart';
import 'package:edtech/features/profile/student/providers/edit_profile_provider.dart';
import 'package:edtech/features/profile/avatar/providers/avatar_upload_provider.dart';
import 'package:edtech/features/profile/avatar/providers/cover_upload_provider.dart';
import 'package:edtech/features/course_details/providers/course_detail_provider.dart';
import 'package:edtech/features/courses/providers/course_list_provider.dart';
import 'package:edtech/features/courses/providers/course_upload_provider.dart';
import 'package:edtech/features/courses/providers/video_post_provider.dart';
import 'package:edtech/features/courses/providers/course_feed_provider.dart';
import 'package:edtech/features/courses/providers/unified_upload_queue_provider.dart';
import 'package:edtech/features/hub/providers/change_password_provider.dart';
import 'package:edtech/features/hub/providers/global_state_provider.dart';
import 'package:edtech/features/hub/providers/mentor_dashboard_provider.dart';
import 'package:edtech/global/core/providers/video_player_provider.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class App extends StatelessWidget {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final SharedPreferences prefs;

  const App({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SignInProvider()),
        ChangeNotifierProvider(create: (_) => SignUpProvider()),
        ChangeNotifierProvider(create: (_) => VerifyOtpProvider()),
        ChangeNotifierProvider(create: (_) => PasswordResetProvider()),
        ChangeNotifierProvider(create: (_) => StudentProfileProvider()),
        ChangeNotifierProvider(create: (_) => MentorProfileProvider()),
        ChangeNotifierProvider(create: (_) => EditProfileProvider()),
        ChangeNotifierProvider(create: (_) => AvatarUploadProvider()),
        ChangeNotifierProvider(create: (_) => CoverUploadProvider()),
        ChangeNotifierProvider(create: (_) => CourseDetailProvider()),
        ChangeNotifierProvider(create: (_) => CourseListProvider()),
        ChangeNotifierProvider(create: (_) => CourseUploadProvider()),
        ChangeNotifierProvider(create: (_) => ChangePasswordProvider()),
        ChangeNotifierProvider(create: (_) => VideoPostProvider()),
        ChangeNotifierProvider(create: (_) => UnifiedUploadQueueProvider()),
        ChangeNotifierProvider(create: (_) => CourseFeedProvider()),
        ChangeNotifierProvider(create: (_) => MentorDashboardProvider()),
        ChangeNotifierProvider(create: (_) => GlobalStateProvider()),
        ChangeNotifierProvider(create: (_) => VideoPlayerProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Eduverse',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.currentThemeMode,
          navigatorKey: App.navigatorKey,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          initialRoute: AppRoutes.splash,
          builder: (context, child) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final overlay = App.navigatorKey.currentState?.overlay;
              if (overlay != null) {
                ToastService.initOverlay(overlay);
              }
            });
            return child!;
          },
        ),
      ),
    );
  }
}
