import 'dart:convert';

import 'package:edtech/global/core/config/app_config.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Service that encapsulates the Google Sign-In SDK interactions.
///
/// Lives in the **data** layer so that presentation providers never import
/// platform-specific packages such as `google_sign_in`.
class GoogleSignInService {
  /// Persistent [GoogleSignIn] instance — must be kept alive across calls
  /// so the SDK properly manages account state on Android.
  late final GoogleSignIn _googleSignIn;

  GoogleSignInService() {
    // ── Android native behaviour (google_sign_in_android 6.2.1) ─────────
    //
    // In GoogleSignInPlugin.java the init() method:
    //   1. Checks `params.getServerClientId()` first.
    //   2. If serverClientId is null but clientId is set → clientId is
    //      **re-interpreted as serverClientId** on Android (with a log
    //      warning).  The native `clientId` param is explicitly documented
    //      as "not supported on Android".
    //   3. If both are null → falls back to `default_web_client_id` from
    //      android/app/src/main/res/values/strings.xml (via
    //      `context.getResources().getIdentifier(...)`).
    //   4. Calls `optionsBuilder.requestIdToken(serverClientId)` — this is
    //      what sets the `aud` (audience) claim in the issued idToken.
    //
    // So the idToken's `aud` = whichever serverClientId wins above.
    // The **backend** verifies this idToken via Google's tokeninfo endpoint
    // and checks that `aud` matches its own Web Client ID.
    //
    // To fix "Invalid Google token" (HTTP 401), both sides must agree on
    // the same Web Client ID.
    // ─────────────────────────────────────────────────────────────────────

    // Explicitly pass the Web client ID as serverClientId (Android) and
    // clientId (Web/PWA).  On Android this overrides the resource lookup of
    // default_web_client_id; on the Web the clientId is required.
    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      clientId: AppConfig.googleClientId,
      serverClientId: AppConfig.googleClientId,
    );
  }

  /// Decodes the **payload** (middle segment) of a JWT idToken and returns
  /// its `aud` (audience) claim, or the entire payload as a string on error.
  String _decodeIdTokenAudience(String idToken) {
    try {
      // JWT = header.payload.signature
      final parts = idToken.split('.');
      if (parts.length != 3) return '⚠️ Not a valid JWT (expected 3 parts)';

      // Pad base64 for decoding (JWT uses URL-safe base64 without padding)
      final normalized = parts[1]
          .replaceAll('-', '+')
          .replaceAll('_', '/')
          .padRight(((parts[1].length + 3) ~/ 4) * 4, '=');
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;

      final aud = json['aud']?.toString() ?? '⚠️ no "aud" claim';
      final email = json['email']?.toString() ?? '⚠️ no "email" claim';

      AppLogger.d('idToken aud=$aud, email=$email');
      return aud;
    } catch (e) {
      return '⚠️ decode error: $e';
    }
  }

  Future<void> signOut() => _googleSignIn.signOut();

  /// Attempts a Google Sign-In and returns the idToken on success, or `null`
  /// if the user cancels.
  ///
  /// Always calls [signOut] first so the native account picker appears
  /// (otherwise `google_sign_in` silently reuses the last account, making it
  /// impossible to switch Google accounts after logging out of the app).
  Future<String?> signIn() async {
    AppLogger.i('Google Sign-In: opening account picker...');

    // Force the account picker by clearing the previous session.
    await _googleSignIn.signOut();

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      AppLogger.i('Google Sign-In cancelled by user');
      return null;
    }

    AppLogger.i(
      'Google Sign-In: user selected — email=${googleUser.email}, '
      'name=${googleUser.displayName}',
    );

    final googleAuth = await googleUser.authentication;
    if (googleAuth.idToken == null) {
      AppLogger.w('Google Sign-In: no idToken received');
      return null;
    }

    AppLogger.i(
      'Google Sign-In: idToken received (length=${googleAuth.idToken!.length})',
    );

    _decodeIdTokenAudience(googleAuth.idToken!);

    return googleAuth.idToken;
  }
}
