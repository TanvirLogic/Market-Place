import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tawk_to_plus/flutter_tawk_to_plus.dart';

class TawkChatService {
  static final TawkChatService _instance = TawkChatService._internal();
  factory TawkChatService() => _instance;
  TawkChatService._internal();

  final _storage = const FlutterSecureStorage();
  static const _userIdKey = 'tawk_user_id';

  bool _initialized = false;

  Future<void> init({
    required String directChatLink,
    required String userId,
    required String name,
    required String email,
    Function? onLoad,
    Function(String)? onAgentMessage,
  }) async {
    if (!_initialized) {
      await TawkService().initialize(
        directChatLink: directChatLink,
        visitor: TawkVisitor(
          name: name,
          email: email,
          otherAttributes: {'user_id': userId},
        ),
        onLoad: onLoad,
        onAgentMessage: onAgentMessage,
      );
      _initialized = true;
    }

    await _storage.write(key: _userIdKey, value: userId);
  }

  Future<void> restore({
    required String directChatLink,
    Function? onLoad,
    Function(String)? onAgentMessage,
  }) async {
    if (_initialized) return;
    final id = await _storage.read(key: _userIdKey);
    if (id == null) return;

    await TawkService().initialize(
      directChatLink: directChatLink,
      visitor: TawkVisitor(
        name: 'User',
        email: 'user@example.com',
        otherAttributes: {'user_id': id},
      ),
      onLoad: onLoad,
      onAgentMessage: onAgentMessage,
    );
    _initialized = true;
  }

  Widget get chatWidget =>
      TawkService().getWebViewWidget(
        placeholder: const Center(child: CircularProgressIndicator()),
      );

  Future<void> logout() async {
    TawkService().dispose();
    await _storage.delete(key: _userIdKey);
    _initialized = false;
  }
}
