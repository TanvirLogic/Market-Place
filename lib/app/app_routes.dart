import 'package:edtech/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:edtech/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:edtech/features/auth/presentation/screens/splash_screen.dart';
import 'package:edtech/features/auth/presentation/screens/verify_otp_screen.dart';
import 'package:edtech/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:edtech/features/auth/presentation/screens/reset_verification_screen.dart';
import 'package:edtech/features/auth/presentation/screens/set_new_password_screen.dart';
import 'package:edtech/features/auth/presentation/screens/password_success_screen.dart';
import 'package:edtech/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:edtech/features/home/presentation/pages/main_nav_shell.dart';
import 'package:edtech/features/course_details/presentation/screens/course_details_screen.dart';
import 'package:edtech/features/courses/presentation/screens/payment_success_screen.dart';
import 'package:edtech/features/courses/presentation/screens/upload_course_screen.dart';
import 'package:edtech/features/courses/presentation/screens/upload_video_screen.dart';
import 'package:edtech/features/manage_module/presentation/screens/manage_module_screen.dart';
import 'package:edtech/features/hub/presentation/screens/password_and_security_screen.dart';
import 'package:edtech/features/hub/presentation/screens/payments_and_revenue_screen.dart';
import 'package:edtech/features/hub/presentation/screens/ads_create_screen.dart';
import 'package:edtech/features/hub/presentation/screens/ads_manager_screen.dart';
import 'package:edtech/features/hub/presentation/screens/help_center_screen.dart';
import 'package:edtech/features/hub/presentation/screens/mentor_dashboard_screen.dart';
import 'package:edtech/features/notifications/presentation/pages/notifications_page.dart';
import 'package:edtech/features/profile/avatar/presentation/screens/full_screen_image_viewer_screen.dart';
import 'package:edtech/features/profile/edit/presentation/screens/profile_editing_screen.dart';
import 'package:edtech/features/profile/mentor/presentation/screens/mentor_profile_screen.dart';
import 'package:edtech/features/profile/student/presentation/screens/student_profile_screen.dart';
import 'package:flutter/material.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String forgotPassword = '/forgot-password';
  static const String verification = '/verification';
  static const String resetVerification = '/reset-verification';
  static const String passwordSuccess = '/password-success';
  static const String resetPassword = '/reset-password';
  static const String profilePage = '/profile';
  static const String mentorProfilePage = '/mentor-profile';
  static const String editProfilePage = '/edit-profile';
  static const String passwordAndSecurity = '/password-and-security';
  static const String paymentsAndRevenue = '/payments-and-revenue';
  static const String mentorDashboard = '/mentor-dashboard';
  static const String fullScreenImage = '/full-screen-image';
  static const String uploadVideoPage = '/upload-video-page';
  static const String uploadCoursePage = '/upload-course-page';
  static const String courseDetails = '/course-details';
  static const String paymentSuccess = '/payment-success';
  static const String notifications = '/notifications';
  static const String manageModule = '/manage-module';
  static const String adsManager = '/ads-manager';
  static const String adsCreate = '/ads-create';
  static const String roleSelection = '/role-selection';
  static const String helpCenter = '/help-center';

  static Future<void> navigateToProfile(BuildContext context, String role) {
    final route = role == 'MENTOR' ? mentorProfilePage : profilePage;
    return Navigator.pushNamed(context, route);
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const SignInScreen());
      case register:
        return MaterialPageRoute(builder: (_) => const SignUpScreen());
      case forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case verification:
        final args = settings.arguments as Map?;
        final email = (args?['email'] as String?) ?? '';
        return MaterialPageRoute(builder: (_) => VerifyOtpScreen(email: email));
      case resetVerification:
        return MaterialPageRoute(
          builder: (_) => const ResetVerificationScreen(),
        );
      case resetPassword:
        return MaterialPageRoute(builder: (_) => const SetNewPasswordScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const MainNavShell());
      case passwordSuccess:
        return MaterialPageRoute(builder: (_) => const PasswordSuccessScreen());
      case profilePage:
        return MaterialPageRoute(builder: (_) => const StudentProfileScreen());
      case mentorProfilePage:
        return MaterialPageRoute(builder: (_) => const MentorProfileScreen());
      case editProfilePage:
        return MaterialPageRoute(builder: (_) => const EditProfileScreen());
      case uploadVideoPage:
        return MaterialPageRoute(builder: (_) => const UploadVideoScreen());
      case uploadCoursePage:
        return MaterialPageRoute(builder: (_) => const UploadCourseScreen());
      case courseDetails:
        final args = settings.arguments as Map?;
        final courseId = (args?['courseId'] as int?) ?? 0;
        return MaterialPageRoute(
          builder: (_) => CourseDetailsScreen(courseId: courseId),
        );
      case paymentSuccess:
        return MaterialPageRoute(builder: (_) => const PaymentSuccessScreen());
      case passwordAndSecurity:
        return MaterialPageRoute(
          builder: (_) => const PasswordAndSecurityScreen(),
        );
      case paymentsAndRevenue:
        return MaterialPageRoute(
          builder: (_) => const PaymentsAndRevenueScreen(),
        );
      case mentorDashboard:
        return MaterialPageRoute(builder: (_) => const MentorDashboardScreen());
      case notifications:
        return MaterialPageRoute(builder: (_) => const NotificationsPage());
      case manageModule:
        final args = settings.arguments as Map?;
        final courseId = (args?['courseId'] as int?) ?? 0;
        return MaterialPageRoute(
          builder: (_) => ManageModuleScreen(courseId: courseId),
        );
      case adsManager:
        return MaterialPageRoute(builder: (_) => const AdsManagerScreen());
      case adsCreate:
        return MaterialPageRoute(builder: (_) => const AdsCreateScreen());
      case roleSelection:
        final args = settings.arguments as Map<String, dynamic>?;
        final idToken = args?['idToken'] as String? ?? '';
        return MaterialPageRoute(
          builder: (_) => RoleSelectionScreen(idToken: idToken),
        );
      case helpCenter:
        return MaterialPageRoute(
          builder: (_) => const HelpCenterScreen(
            directChatLink:
                'https://tawk.to/chat/6a39527486fba91d4a3bdef0/1jrnuk622',
          ),
        );
      case fullScreenImage:
        final args = settings.arguments as Map<String, dynamic>;
        final imageUrl = args['imageUrl'] as String;
        final heroTag = args['heroTag'] as String?;
        return MaterialPageRoute(
          builder: (_) =>
              FullScreenImageViewerScreen(imageUrl: imageUrl, heroTag: heroTag),
        );

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
