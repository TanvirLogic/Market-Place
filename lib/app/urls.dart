import 'package:edtech/global/core/config/app_config.dart';

class Urls {
  static const String _baseUrl = AppConfig.baseUrl;

  Urls._();

  // ──────────────────────────────────────────────
  // Auth Endpoints
  // ──────────────────────────────────────────────
  static const String signInUrl = '$_baseUrl/auth/login';
  static const String signUpUrl = '$_baseUrl/auth/register';
  static const String googleAuthUrl = '$_baseUrl/auth/google';
  static const String verifyEmailUrl = '$_baseUrl/auth/verify-email';
  static const String resendEmailVerificationUrl =
      '$_baseUrl/auth/resend-email-verification';
  static const String refreshTokenUrl = '$_baseUrl/auth/refresh';
  static const String logoutUrl = '$_baseUrl/auth/logout';
  static const String forgotPasswordUrl = '$_baseUrl/auth/forgot-password';
  static const String verifyResetOtpUrl = '$_baseUrl/auth/verify-reset-otp';
  static const String resetPasswordUrl = '$_baseUrl/auth/reset-password';
  static const String changePasswordUrl = '$_baseUrl/auth/change-password';

  // ──────────────────────────────────────────────
  // Profile Endpoints
  // ──────────────────────────────────────────────
  static const String profileUrl = '$_baseUrl/profile/me';
  static const String profileUpdateUrl = '$_baseUrl/profile/update';
  static const String profileEmailUrl = '$_baseUrl/profile/email';

  // ──────────────────────────────────────────────
  // Avatar & Cover Upload Endpoints
  // ──────────────────────────────────────────────
  static const String avatarUploadUrl = '$_baseUrl/profile/avatar/upload-url';
  static const String avatarConfirmUrl = '$_baseUrl/profile/avatar/confirm';
  static const String coverUploadUrl = '$_baseUrl/profile/cover/upload-url';
  static const String coverConfirmUrl = '$_baseUrl/profile/cover/confirm';

  // ──────────────────────────────────────────────
  // Course Endpoints
  // ──────────────────────────────────────────────
  static const String courseAssetsUploadUrl = '$_baseUrl/course/assets/upload';
  static const String createCourseUrl = '$_baseUrl/course';
  static const String courseListUrl = '$_baseUrl/courses';
  static const String courseDetailUrl = '$_baseUrl/courses'; // append /{id}
  static const String enrolledCourseUrl =
      '$_baseUrl/courses'; // append /{id}/enrolled
  static const String manageModulesUrl =
      '$_baseUrl/courses'; // append /{id}/modules
  static const String courseModuleUrl = '$_baseUrl/course/module';
  static const String courseModuleUploadUrl =
      '$_baseUrl/course/module/lesson/upload';
  static const String courseModuleLessonUrl = '$_baseUrl/course/module/lesson';
  static const String courseLessonUrl = '$_baseUrl/course/lesson';
  static const String updateCourseUrl = '$_baseUrl/course';

  // ──────────────────────────────────────────────
  // Video Post Endpoints
  // ──────────────────────────────────────────────
  static const String videoPostAssetsUploadUrl =
      '$_baseUrl/video-post/assets/upload';
  static const String videoPostUrl = '$_baseUrl/video-post';

  // ──────────────────────────────────────────────
  // Dashboard Endpoints
  // ──────────────────────────────────────────────
  static const String dashboardMetricsUrl = '$_baseUrl/dashboard/metrics';
  static const String dashboardTransactionsUrl =
      '$_baseUrl/dashboard/transactions';

  // ──────────────────────────────────────────────
  // Ads Endpoints
  // ──────────────────────────────────────────────
  static const String adsCreateUrl = '$_baseUrl/ads/create';
  static const String adsListUrl = '$_baseUrl/ads/list';

  // ──────────────────────────────────────────────
  // Social Endpoints
  // ──────────────────────────────────────────────
  static const String socialFeedUrl = '$_baseUrl/course/feed';

  // ──────────────────────────────────────────────
  // Notification Endpoints
  // ──────────────────────────────────────────────
  static const String notificationsUrl = '$_baseUrl/notifications';
}
