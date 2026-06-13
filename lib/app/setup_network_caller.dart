import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/features/auth/providers/sign_in_provider.dart';
import 'package:edtech/global/core/services/network_caller.dart';
import 'package:edtech/app/app.dart';

NetworkCaller getNetworkCaller({bool isPublic = false}) {
  return NetworkCaller(
    decodedErrorMSGKey: 'message',
    headers: isPublic
        ? {'content-type': 'application/json'}
        : {
            'content-type': 'application/json',
            'Authorization': 'Bearer ${AuthController.accessToken ?? ''}',
          },
    onRefreshToken: isPublic ? null : _refreshToken,
    onUnauthorize: isPublic
        ? () {}
        : () {
            AuthController.clearUserData();
            App.navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
          },
  );
}

Future<bool> _refreshToken() async {
  final provider = SignInProvider();
  return provider.tryRefreshToken();
}
