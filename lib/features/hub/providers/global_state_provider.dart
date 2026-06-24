import 'package:flutter/material.dart';

class GlobalStateProvider extends ChangeNotifier {
  // Singleton pattern to access the provider instance outside the widget tree (e.g., in TawkNotificationService)
  static final GlobalStateProvider _instance = GlobalStateProvider._internal();
  factory GlobalStateProvider() => _instance;
  GlobalStateProvider._internal();

  int _unreadMessages = 0;
  int get unreadMessages => _unreadMessages;

  void incrementUnreadMessages() {
    _unreadMessages++;
    notifyListeners();
  }

  void resetUnreadMessages() {
    _unreadMessages = 0;
    notifyListeners();
  }
}
