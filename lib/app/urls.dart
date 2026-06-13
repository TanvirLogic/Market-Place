import 'package:edtech/global/core/config/app_config.dart';

class Urls {
  static const String _baseUrl = AppConfig.baseUrl;
  static const String signInUrl = '$_baseUrl/auth/login';
  static const String signUpUrl = '$_baseUrl/auth/register';
  static const String googleAuthUrl = '$_baseUrl/auth/google';
  static const String verifyEmailUrl = '$_baseUrl/auth/verify-email';
  static const String resendEmailVerificationUrl = '$_baseUrl/auth/resend-email-verification';
  static const String refreshTokenUrl = '$_baseUrl/auth/refresh';
  static const String logoutUrl = '$_baseUrl/auth/logout';
  static const String forgotPasswordUrl = '$_baseUrl/auth/forgot-password';
  static const String verifyResetOtpUrl = '$_baseUrl/auth/verify-reset-otp';
  static const String resetPasswordUrl = '$_baseUrl/auth/reset-password';
  static const String changePasswordUrl = '$_baseUrl/auth/change-password';
  static const String profileUrl = '$_baseUrl/profile/me';
  static const String profileUpdateUrl = '$_baseUrl/profile/update';
  static const String avatarUploadUrl = '$_baseUrl/profile/avatar/upload-url';
  static const String avatarConfirmUrl = '$_baseUrl/profile/avatar/confirm';
  static const String coverUploadUrl = '$_baseUrl/profile/cover/upload-url';
  static const String coverConfirmUrl = '$_baseUrl/profile/cover/confirm';
  static const String courseAssetsUploadUrl = '$_baseUrl/course/assets/upload';
  static const String createCourseUrl = '$_baseUrl/course';
}
