import 'package:flutter/material.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/features/auth/data/models/user_model.dart';
import 'package:edtech/features/auth/data/services/google_sign_in_service.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignInProvider extends ChangeNotifier {
  final GoogleSignInService _googleSignInService;

  SignInProvider({GoogleSignInService? googleSignInService})
    : _googleSignInService = googleSignInService ?? GoogleSignInService();

  bool _inProgress = false;
  bool get inProgress => _inProgress;

  bool _isGoogleLoading = false;
  bool get isGoogleLoading => _isGoogleLoading;

  bool _isPasswordObscure = true;
  bool get isPasswordObscure => _isPasswordObscure;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  UserModel? _user;
  UserModel? get user => _user;

  Future<bool> signIn(String email, String password) async {
    bool isSuccess = false;
    _inProgress = true;
    _errorMessage = null;
    notifyListeners();

    final response = await getNetworkCaller(isPublic: true).postRequest(
      url: Urls.signInUrl,
      body: {'email': email, 'password': password},
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_used_email', email);

    if (response.isSuccess) {
      final data = response.responseData['data'];
      final user = UserModel.fromJson(
        data['user'] as Map<String, dynamic>,
        token: data['accessToken'],
        refreshToken: data['refreshToken'],
      );
      await AuthController.saveUserData(data['accessToken']?.toString() ?? '', user);
      _user = user;
      _errorMessage = null;
      isSuccess = true;
      ToastService.showSuccess("Welcome back!");
    } else {
      final msg = response.errorMessage ?? '';
      if (msg.contains('Email not verified') || msg.contains('EMAIL_NOT_VERIFIED')) {
        _errorMessage = 'EMAIL_NOT_VERIFIED';
        _user = UserModel(id: '', email: email, firstName: '', lastName: '');
      } else {
        _errorMessage = msg;
        ToastService.showError(msg);
      }
    }

    _inProgress = false;
    notifyListeners();
    return isSuccess;
  }

  Future<String?> getGoogleIdToken() async {
    _isGoogleLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final idToken = await _googleSignInService.signIn();
      if (idToken == null) {
        _isGoogleLoading = false;
        notifyListeners();
        return null;
      }
      return idToken;
    } catch (e) {
      _errorMessage = "Google Sign-In Error: ${e.toString()}";
      ToastService.showError(_errorMessage!);
      _isGoogleLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> completeGoogleSignIn(String idToken, String role) async {
    bool isSuccess = false;
    _isGoogleLoading = true;
    _errorMessage = null;
    notifyListeners();

    final response = await getNetworkCaller(isPublic: true).postRequest(
      url: Urls.googleAuthUrl,
      body: {'idToken': idToken, 'role': role},
    );

    if (response.isSuccess) {
      final data = response.responseData['data'];
      final user = UserModel.fromJson(
        data['user'] as Map<String, dynamic>,
        token: data['accessToken'],
        refreshToken: data['refreshToken'],
      );
      await AuthController.saveUserData(data['accessToken']?.toString() ?? '', user);
      _user = user;
      _errorMessage = null;
      isSuccess = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_used_email', user.email);
      ToastService.showSuccess("Welcome ${user.firstName}!");
    } else {
      _errorMessage = response.errorMessage;
      ToastService.showError(response.errorMessage ?? 'Google Sign-In failed');
    }

    _isGoogleLoading = false;
    notifyListeners();
    return isSuccess;
  }

  Future<bool> tryRefreshToken() async {
    final oldRefreshToken = AuthController.userModel?.refreshToken;
    if (oldRefreshToken == null) return false;

    final response = await getNetworkCaller(isPublic: true).postRequest(
      url: Urls.refreshTokenUrl,
      body: {'refreshToken': oldRefreshToken},
    );

    if (response.isSuccess) {
      final data = response.responseData['data'];
      final newAccessToken = data['accessToken']?.toString() ?? '';
      final newRefreshToken = data['refreshToken']?.toString();
      if (newAccessToken.isNotEmpty) {
        final existing = AuthController.userModel;
        if (existing != null) {
          final updated = UserModel(
            id: existing.id,
            email: existing.email,
            firstName: existing.firstName,
            lastName: existing.lastName,
            token: newAccessToken,
            refreshToken: newRefreshToken ?? oldRefreshToken,
            phone: existing.phone,
            avatarUrl: existing.avatarUrl,
            city: existing.city,
            role: existing.role,
            emailVerified: existing.emailVerified,
            phoneVerified: existing.phoneVerified,
          );
          await AuthController.saveUserData(newAccessToken, updated);
        } else {
          await AuthController.saveUserData(
            newAccessToken,
            UserModel(id: '', email: '', firstName: '', lastName: ''),
          );
        }
        return true;
      }
    }
    await AuthController.clearUserData();
    return false;
  }

  Future<void> logout() async {
    _inProgress = true;
    notifyListeners();

    await getNetworkCaller().postRequest(url: Urls.logoutUrl);
    await _googleSignInService.signOut();
    await AuthController.clearUserData();
    _user = null;

    _inProgress = false;
    notifyListeners();
  }

  void togglePasswordVisibility() {
    _isPasswordObscure = !_isPasswordObscure;
    notifyListeners();
  }
}
