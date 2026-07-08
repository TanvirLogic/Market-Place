import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles notification-permission checks and shows custom notifications for
/// video uploads with the user-facing video title (not the raw filename).
class UploadNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'upload_progress';
  static const String _channelName = 'Upload Progress';
  static const String _channelDesc = 'Shows video upload progress';

  static bool _initialized = false;

  /// We replace the progress notification with the completion one on the same
  /// id so the OS groups them correctly.
  static int notificationId(String jobId) => jobId.hashCode & 0x7FFFFFFF;

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

  /// Show or update a progress notification — shows only the percentage (no
  /// descriptive text) to minimize visual noise in the notification tray.
  static Future<void> showUploadProgress({
    required String jobId,
    required String title,
    required double progress,
  }) async {
    final percent = (progress * 100).clamp(0, 100).toInt();
    await _notifications.show(
      id: notificationId(jobId),
      title: '$percent%',
      body: null,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          autoCancel: false,
          silent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  /// Show a completion notification — minimal text, no sound.
  static Future<void> showUploadComplete({
    required String jobId,
    required String title,
  }) async {
    await _notifications.show(
      id: notificationId(jobId),
      title: '100%',
      body: '$title uploaded',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          silent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  /// Dismiss any active notification for a given job.
  static Future<void> dismissUploadNotification(String jobId) async {
    await _notifications.cancel(id: notificationId(jobId));
  }

  /// Returns true if permission is granted or not required on this platform.
  static Future<bool> requestNotificationPermission() async {
    if (!_initialized) await init();

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted == null) return true;
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

    return false;
  }
}
