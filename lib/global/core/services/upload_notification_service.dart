import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class UploadNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'upload_progress';
  static const String _channelName = 'Upload Progress';
  static const String _channelDesc = 'Shows file upload progress';
  static const String _foregroundChannelId = 'upload_foreground';
  static const String _foregroundChannelName = 'Upload';
  static const String _foregroundChannelDesc = 'Required for upload service';
  static const int _queueNotifId = 999;

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

    const foregroundChannel = AndroidNotificationChannel(
      _foregroundChannelId,
      _foregroundChannelName,
      description: _foregroundChannelDesc,
      importance: Importance.min,
      playSound: false,
      enableVibration: false,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(foregroundChannel);

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
      // null means the feature is not available (Android < 13) — not needed
      if (granted == null) return true;
      return granted;
    }

    // iOS: request UNUserNotificationCenter authorization
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

    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      // iOS: check current authorization status
      return Future.value(false); // will prompt on next request
    }

    return true;
  }

  /// Open system notification settings for the app.
  static Future<void> openSystemSettings() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      return;
    }
    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
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

  static String _typeLabel(String? uploadType) {
    switch (uploadType) {
      case 'course':
        return 'Course';
      case 'module_lesson':
        return 'Lesson';
      case 'resource':
        return 'Resource';
      default:
        return 'Video';
    }
  }

  static Future<void> showQueueProgress({
    required int queueIndex,
    required int queueTotal,
    required int itemProgress,
    required int itemTotal,
    required String itemTitle,
    String? uploadType,
  }) async {
    final pct = itemTotal > 0 ? (itemProgress * 100 ~/ itemTotal) : 0;
    final label = _typeLabel(uploadType);
    final title = 'Uploading $queueIndex/$queueTotal • ${_truncate(itemTitle, 30)}';
    final body = label == 'Video'
        ? 'Uploading... $pct%'
        : '$label uploading... $pct%';

    await _notifications.show(
      id: _queueNotifId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: pct,
          indeterminate: false,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showProgress({
    required int notificationId,
    required int progress,
    required int total,
    required String title,
    String? fileName,
    int? queueIndex,
    int? queueTotal,
    String? uploadType,
  }) async {
    final pct = total > 0 ? (progress * 100 ~/ total) : 0;
    final body = 'Uploading... $pct%';

    await _notifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
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

    if (queueIndex != null && queueTotal != null) {
      await showQueueProgress(
        queueIndex: queueIndex,
        queueTotal: queueTotal,
        itemProgress: progress,
        itemTotal: total,
        itemTitle: title,
        uploadType: uploadType,
      );
    }
  }

  static Future<void> showQueueItemComplete({
    required int queueIndex,
    required int queueTotal,
    String? uploadType,
  }) async {
    final label = _typeLabel(uploadType);
    final title = 'Uploading $queueIndex/$queueTotal';
    final body = label == 'Video' ? 'Video uploaded' : '$label uploaded';

    await _notifications.show(
      id: _queueNotifId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          onlyAlertOnce: true,
          showProgress: false,
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
      id: notificationId,
      title: title,
      body: body ?? 'Upload completed successfully',
      notificationDetails: NotificationDetails(
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

  static Future<void> showQueueAllComplete() async {
    await _notifications.show(
      id: _queueNotifId,
      title: 'All Uploads Complete',
      body: 'All items in the queue have been processed.',
      notificationDetails: NotificationDetails(
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
      id: notificationId,
      title: title,
      body: body ?? 'Upload failed',
      notificationDetails: NotificationDetails(
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
      await _notifications.cancel(id: notificationId);
    } else {
      await _notifications.cancelAll();
    }
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 3)}...';
  }
}
