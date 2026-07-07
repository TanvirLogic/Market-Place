import 'package:edtech/features/courses/data/repositories/upload_queue_repository.dart';
import 'package:edtech/global/core/services/upload_notification_service.dart';
import 'package:media_kit/media_kit.dart';

Future<void> initPlatformServices() async {
  MediaKit.ensureInitialized();
  await UploadNotificationService.init();
  await _requestNotificationPermissionEarly();

  // Storage cleanup: delete old rows, orphaned cache files, trim WAL
  await UploadQueueRepository.runStartupCleanup();
}

Future<void> _requestNotificationPermissionEarly() async {
  try {
    if (!await UploadNotificationService.hasNotificationPermission()) {
      await UploadNotificationService.requestNotificationPermission();
    }
  } catch (_) {}
}
