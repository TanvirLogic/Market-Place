import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class UploadNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static const String _channelId = 'upload_progress';
  static const String _channelName = 'Upload Progress';
  static const String _channelDesc = 'Shows file upload progress';
  static const String _foregroundChannelId = 'upload_foreground';
  static const String _foregroundChannelName = 'Upload';
  static const String _foregroundChannelDesc = 'Required for upload service';

  static bool _initialized = false;

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _notifications.initialize(const InitializationSettings(android: androidSettings, iOS: iosSettings));

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.defaultImportance,
    );
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const foregroundChannel = AndroidNotificationChannel(
      _foregroundChannelId,
      _foregroundChannelName,
      description: _foregroundChannelDesc,
      importance: Importance.min,
      playSound: false,
      enableVibration: false,
    );
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(foregroundChannel);

    _initialized = true;
  }

  static Future<bool> requestNotificationPermission() async {
    if (!_initialized) await init();
    final plugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return false;
    final granted = await plugin.requestNotificationsPermission();
    return granted ?? false;
  }

  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stopService');
    }
  }

  static Future<void> showProgress({
    required int notificationId,
    required int progress,
    required int total,
    required String title,
    String? fileName,
  }) async {
    final pct = total > 0 ? (progress * 100 ~/ total) : 0;
    final body = fileName != null ? '$fileName — $pct%' : 'Uploading... $pct%';

    await _notifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showSuccess({
    required int notificationId,
    required String title,
    String? body,
  }) async {
    await _notifications.show(
      notificationId,
      title,
      body ?? 'Upload completed successfully',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          showProgress: false,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showError({
    required int notificationId,
    required String title,
    String? body,
  }) async {
    await _notifications.show(
      notificationId,
      title,
      body ?? 'Upload failed',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          showProgress: false,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> cancel({int? notificationId}) async {
    if (notificationId != null) {
      await _notifications.cancel(notificationId);
    } else {
      await _notifications.cancelAll();
    }
  }
}
