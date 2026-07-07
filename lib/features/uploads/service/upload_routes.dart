import 'package:edtech/app/urls.dart';

import '../data/models/upload_job.dart';
import '../data/models/upload_enums.dart';

/// Everything that differs per asset type in one place: which endpoints to hit
/// and how to build each request body. Ported from the previous
/// UnifiedUploadQueueProvider so the backend contract is unchanged.
class UploadRoute {
  final String initEndpoint;
  final String completeEndpoint;
  final String abortEndpoint;
  final String callbackEndpoint;

  /// HTTP method for the step-4 callback (`POST` default; avatar/cover confirm
  /// is a `PUT`).
  final String callbackMethod;

  /// For course endpoints that return `data.thumbnail`/`data.video`, which
  /// section to parse ('thumbnail' | 'video'); null otherwise.
  final String? courseAssetKey;

  final Map<String, dynamic> initBody;
  final Map<String, dynamic> Function(UploadJob job) callbackBody;

  const UploadRoute({
    required this.initEndpoint,
    required this.completeEndpoint,
    required this.abortEndpoint,
    required this.callbackEndpoint,
    required this.initBody,
    required this.callbackBody,
    this.callbackMethod = 'POST',
    this.courseAssetKey,
  });
}

/// Builds the [UploadRoute] for a job based on its type + metadata.
class UploadRoutes {
  const UploadRoutes();

  UploadRoute forJob(UploadJob job) {
    final m = job.metadata;
    final fileName = _fileName(job.filePath);

    switch (job.type) {
      case UploadAssetType.moduleLesson:
        return UploadRoute(
          initEndpoint: Urls.courseModuleUploadUrl,
          completeEndpoint: Urls.uploadCompleteUrl,
          abortEndpoint: Urls.uploadAbortUrl,
          callbackEndpoint: Urls.courseModuleLessonUrl,
          initBody: {
            'videoFilename': fileName,
            'videoContentType': _videoType(fileName),
            'videoFileSize': job.fileSize,
            if (m['moduleId'] != null) 'moduleID': m['moduleId'],
          },
          callbackBody: (j) => {
            'title': j.metadata['lessonTitle'] ?? j.title,
            'moduleId': j.metadata['moduleId'],
            'videoUrl': j.fileUrl,
            'duration': j.metadata['videoDuration'] ?? 0,
            'fileSize': j.metadata['fileSize'] ?? j.fileSize,
          },
        );

      case UploadAssetType.resource:
        return UploadRoute(
          initEndpoint: Urls.courseModuleResourceUploadUrl,
          completeEndpoint: Urls.uploadCompleteUrl,
          abortEndpoint: Urls.uploadAbortUrl,
          callbackEndpoint: Urls.courseModuleResourceUrl,
          initBody: {
            'filename': fileName,
            'contentType': m['contentType'] ?? 'application/octet-stream',
          },
          callbackBody: (j) => {
            'title': j.metadata['lessonTitle'] ?? j.title,
            'fileUrl': j.fileUrl,
            'moduleId': j.metadata['moduleId'],
            'fileType': j.metadata['contentType'] ?? 'application/octet-stream',
            'fileSize': j.metadata['fileSize'] ?? j.fileSize,
          },
        );

      case UploadAssetType.course:
      case UploadAssetType.courseThumb:
        return UploadRoute(
          initEndpoint: Urls.courseAssetsUploadUrl,
          completeEndpoint: Urls.uploadCompleteUrl,
          abortEndpoint: Urls.uploadAbortUrl,
          callbackEndpoint: Urls.createCourseUrl,
          courseAssetKey: 'thumbnail',
          initBody: {
            'thumbnailFilename': fileName,
            'thumbnailContentType': _imageType(fileName),
            'thumbnailFileSize': job.fileSize,
          },
          callbackBody: (j) => {
            'title': j.metadata['courseTitle'] ?? j.title,
            'description': j.metadata['description'] ?? '',
            'shortDescription': j.metadata['shortDescription'] ?? '',
            'requirements': j.metadata['requirements'] ?? '',
            'thumbnailUrl': j.fileUrl,
            if (j.metadata['videoPath'] != null)
              'introVideoUrl': j.metadata['videoPath'],
            'language': j.metadata['language'] ?? '',
            'level': (j.metadata['level'] ?? '').toString().toUpperCase(),
            'type': (j.metadata['type'] ?? 'FREE').toString().toUpperCase(),
            'price': j.metadata['price'] ?? 0,
          },
        );

      case UploadAssetType.courseIntro:
        return UploadRoute(
          initEndpoint: Urls.courseAssetsUploadUrl,
          completeEndpoint: Urls.uploadCompleteUrl,
          abortEndpoint: Urls.uploadAbortUrl,
          callbackEndpoint: Urls.courseAssetsUploadUrl,
          courseAssetKey: 'video',
          initBody: {
            'thumbnailFilename': 'keep.jpg',
            'thumbnailContentType': 'image/jpeg',
            'thumbnailFileSize': 0,
            'videoFilename': fileName,
            'videoContentType': _videoType(fileName),
            'videoFileSize': job.fileSize,
          },
          callbackBody: (j) => {
            'title': j.title,
            'videoUrl': j.fileUrl,
          },
        );

      case UploadAssetType.avatar:
        return UploadRoute(
          initEndpoint: Urls.avatarUploadUrl,
          completeEndpoint: Urls.uploadCompleteUrl,
          abortEndpoint: Urls.uploadAbortUrl,
          callbackEndpoint: Urls.avatarConfirmUrl,
          callbackMethod: 'PUT',
          initBody: {
            'filename': fileName,
            'contentType': _imageType(fileName),
            'fileSize': job.fileSize,
          },
          callbackBody: (j) => {'fileUrl': j.fileUrl},
        );

      case UploadAssetType.cover:
        return UploadRoute(
          initEndpoint: Urls.coverUploadUrl,
          completeEndpoint: Urls.uploadCompleteUrl,
          abortEndpoint: Urls.uploadAbortUrl,
          callbackEndpoint: Urls.coverConfirmUrl,
          callbackMethod: 'PUT',
          initBody: {
            'filename': fileName,
            'contentType': _imageType(fileName),
            'fileSize': job.fileSize,
          },
          callbackBody: (j) => {'fileUrl': j.fileUrl},
        );

      case UploadAssetType.videoPost:
        return UploadRoute(
          initEndpoint: Urls.videoPostAssetsUploadUrl,
          completeEndpoint: Urls.uploadCompleteUrl,
          abortEndpoint: Urls.uploadAbortUrl,
          callbackEndpoint: Urls.videoPostUrl,
          initBody: {
            'videoFilename': fileName,
            'videoContentType': _videoType(fileName),
            'videoFileSize': job.fileSize,
          },
          callbackBody: (j) => {
            'title': j.title,
            'videoUrl': j.fileUrl,
            'duration': j.metadata['videoDuration'] ?? 0,
            'fileSize': j.metadata['fileSize'] ?? j.fileSize,
          },
        );
    }
  }

  String _fileName(String path) =>
      path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

  String _videoType(String filename) {
    switch (filename.split('.').last.toLowerCase()) {
      case 'mov':
      case 'quicktime':
        return 'video/quicktime';
      case 'mkv':
      case 'x-matroska':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  String _imageType(String filename) {
    switch (filename.split('.').last.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'avif':
        return 'image/avif';
      default:
        return 'image/jpeg';
    }
  }
}
