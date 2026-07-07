import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles notification-permission checks for uploads.
///
/// The actual "Uploading… X%" progress notifications are shown by the
/// `background_downloader` package (configured in [BackgroundUploadEngine]).
/// This service only owns channel setup and runtime permission, which the OS
/// requires before background uploads can post notifications.
class UploadNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'upload_progress';
  static const String _channelName = 'Upload Progress';
  static const String _channelDesc = 'Shows file upload progress';

  static bool _initialized = false;

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.defaultImportance,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _initialized = true;
  }

  /// Returns true if permission is granted or not required on this platform.
  static Future<bool> requestNotificationPermission() async {
    if (!_initialized) await init();

    // Android 13+ requires runtime POST_NOTIFICATIONS permission.
    // On Android 12 and below, no runtime permission needed — return true.
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted == null) return true; // Android < 13 — not needed
      return granted;
    }

    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  /// Check if notification permission is already granted (without prompting).
  static Future<bool> hasNotificationPermission() async {
    if (!_initialized) await init();

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final granted = await androidPlugin.areNotificationsEnabled();
      return granted ?? false;
    }

    // iOS: will prompt on next request.
    return false;
  }
}
