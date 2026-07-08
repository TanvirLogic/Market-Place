import 'package:edtech/app/app.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/features/uploads/engine/native_upload_bridge.dart';
import 'package:edtech/global/core/services/network_caller.dart';

NetworkCaller getNetworkCaller({bool isPublic = false}) {
  return NetworkCaller(
    decodedErrorMSGKey: 'message',
    headers: _buildHeaders(isPublic),
    onRefreshToken: isPublic ? null : _refreshToken,
    onUnauthorize: isPublic
        ? () {}
        : _onUnauthorized,
  );
}

Map<String, String> _buildHeaders(bool isPublic) {
  if (isPublic) {
    return {'content-type': 'application/json'};
  }
  return {
    'content-type': 'application/json',
    'Authorization': 'Bearer ${AuthController.accessToken ?? ''}',
  };
}

void _onUnauthorized() {
  AuthController.clearUserData();
  App.navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
}

Future<bool> _refreshToken() async {
  final oldRefreshToken = AuthController.userModel?.refreshToken;
  if (oldRefreshToken == null) return false;

  final response = await NetworkCaller(
    decodedErrorMSGKey: 'message',
    headers: {'content-type': 'application/json'},
    onUnauthorize: () {},
  ).postRequest(
    url: Urls.refreshTokenUrl,
    body: {'refreshToken': oldRefreshToken},
  );

  if (!response.isSuccess) return false;

  final data = response.responseData['data'];
  final newAccessToken = data['accessToken']?.toString() ?? '';
  if (newAccessToken.isEmpty) return false;

  final existing = AuthController.userModel;
  if (existing != null) {
    final updated = existing.copyWith(
      token: newAccessToken,
      refreshToken: data['refreshToken']?.toString(),
    );
    await AuthController.saveUserData(newAccessToken, updated);
    // Keep the native upload pipeline's token mirror in sync so background
    // uploads (which may run while the app is killed) keep authenticating.
    await NativeUploadBridge.syncTokens(
      accessToken: newAccessToken,
      refreshToken: updated.refreshToken ?? '',
      refreshUrl: Urls.refreshTokenUrl,
    );
  }
  return true;
}
