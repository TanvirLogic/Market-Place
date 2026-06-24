import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:edtech/features/hub/providers/global_state_provider.dart';
import 'package:edtech/features/hub/services/tawk_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HelpCenterScreen extends StatefulWidget {
  final String directChatLink;
  const HelpCenterScreen({super.key, required this.directChatLink});
  static const String name = '/help-center';

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    final user = AuthController.userModel;
    if (user == null) return;

    TawkChatService().init(
      directChatLink: widget.directChatLink,
      userId: user.id,
      name: user.fullName,
      email: user.email,
      onLoad: () {
        if (!mounted) return;
        context.read<GlobalStateProvider>().resetUnreadMessages();
      },
      onAgentMessage: (_) {
        if (!mounted) return;
        context.read<GlobalStateProvider>().incrementUnreadMessages();
      },
    );

    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TawkChatService().chatWidget,
    );
  }
}
