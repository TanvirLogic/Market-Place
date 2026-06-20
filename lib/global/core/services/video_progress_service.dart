import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class VideoProgressService {
  VideoProgressService._();

  static const _storage = FlutterSecureStorage();
  static const _prefix = 'vid_prog_';

  static Future<void> savePosition(int lessonId, Duration position) async {
    await _storage.write(
      key: '$_prefix$lessonId',
      value: position.inMilliseconds.toString(),
    );
  }

  static Future<Duration> getPosition(int lessonId) async {
    final val = await _storage.read(key: '$_prefix$lessonId');
    if (val == null) return Duration.zero;
    return Duration(milliseconds: int.tryParse(val) ?? 0);
  }

  static Future<void> clearPosition(int lessonId) async {
    await _storage.delete(key: '$_prefix$lessonId');
  }
}
