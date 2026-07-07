import 'dart:io';

import 'package:http/http.dart' as http;

import '../setup_network_caller.dart';

class S3UploadResult {
  final bool isSuccess;
  final String? fileUrl;
  final String? errorMessage;

  S3UploadResult({required this.isSuccess, this.fileUrl, this.errorMessage});
}

class S3UploadService {
  static Future<S3UploadResult> uploadImage({
    required String uploadUrlEndpoint,
    required String confirmUrlEndpoint,
    required String filename,
    required List<int> bytes,
    required String contentType,
    Duration uploadTimeout = const Duration(seconds: 120),
    void Function(double progress)? onProgress,
  }) async {
    final fileSize = bytes.length;

    final urlResponse = await getNetworkCaller().postRequest(
      url: uploadUrlEndpoint,
      body: {
        'filename': filename,
        'contentType': contentType,
        'fileSize': fileSize,
      },
    );

    if (!urlResponse.isSuccess) {
      return S3UploadResult(
        isSuccess: false,
        errorMessage: urlResponse.errorMessage ?? 'Failed to get upload URL',
      );
    }

    final raw = urlResponse.responseData;
    final wrapper = raw is Map ? raw['data'] : null;
    if (wrapper is! Map) {
      return S3UploadResult(
        isSuccess: false,
        errorMessage: 'Invalid response from server',
      );
    }

    final isMultipart = wrapper['isMultipart'] as bool? ?? false;
    final fileUrl = wrapper['fileUrl'] as String?;

    if (fileUrl == null) {
      return S3UploadResult(
        isSuccess: false,
        errorMessage: 'Invalid response from server',
      );
    }

    String? resolvedFileUrl;

    if (isMultipart) {
      resolvedFileUrl = await _handleMultipartUpload(
        uploadUrlEndpoint: uploadUrlEndpoint,
        wrapper: wrapper,
        bytes: bytes,
        contentType: contentType,
        uploadTimeout: uploadTimeout,
        onProgress: onProgress,
      );
    } else {
      final uploadUrl = wrapper['uploadUrl'] as String?;
      if (uploadUrl == null) {
        return S3UploadResult(
          isSuccess: false,
          errorMessage: 'Invalid response from server',
        );
      }

      try {
        await _streamUpload(
          url: uploadUrl,
          bytes: bytes,
          contentType: contentType,
          timeout: uploadTimeout,
          onProgress: onProgress,
        );
      } catch (e) {
        return S3UploadResult(
          isSuccess: false,
          errorMessage: 'Failed to upload image to storage',
        );
      }
      resolvedFileUrl = fileUrl;
    }

    if (resolvedFileUrl == null) {
      return S3UploadResult(
        isSuccess: false,
        errorMessage: 'Failed to complete upload',
      );
    }

    final confirmResponse = await getNetworkCaller().putRequest(
      url: confirmUrlEndpoint,
      body: {'fileUrl': resolvedFileUrl},
    );

    if (confirmResponse.isSuccess) {
      return S3UploadResult(isSuccess: true, fileUrl: resolvedFileUrl);
    }

    return S3UploadResult(
      isSuccess: false,
      errorMessage: confirmResponse.errorMessage ?? 'Failed to confirm upload',
    );
  }

  static Future<String?> _handleMultipartUpload({
    required String uploadUrlEndpoint,
    required Map wrapper,
    required List<int> bytes,
    required String contentType,
    required Duration uploadTimeout,
    void Function(double progress)? onProgress,
  }) async {
    final uploadId = wrapper['uploadId'] as String? ?? '';
    final parts = wrapper['parts'] as List? ?? [];
    final totalBytes = bytes.length;

    if (parts.isEmpty || uploadId.isEmpty) return null;

    final etags = <Map<String, dynamic>>[];
    int uploadedBytes = 0;
    final totalParts = parts.length;

    for (int i = 0; i < totalParts; i++) {
      final part = parts[i] as Map;
      final partNumber = part['partNumber'] as int;
      final uploadUrl = part['uploadUrl'] as String;
      final partSize = part['size'] as int?;

      int start;
      int end;
      if (partSize != null) {
        start = uploadedBytes;
        end = (start + partSize).clamp(0, totalBytes);
      } else {
        start = i * (totalBytes ~/ totalParts);
        end = (i == totalParts - 1)
            ? totalBytes
            : (i + 1) * (totalBytes ~/ totalParts);
      }

      final partBytes = bytes.sublist(start, end);

      try {
        final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
        request.contentLength = partBytes.length;

        final responseFuture = request.send().timeout(uploadTimeout);
        request.sink.add(partBytes);
        await request.sink.close();

        final response = await responseFuture;
        if (response.statusCode != 200) {
          return null;
        }

        // Preserve S3's canonical quoted ETag verbatim — the backend's
        // complete endpoint expects the raw header value.
        final etag = response.headers['etag'] ?? '';
        etags.add({'partNumber': partNumber, 'eTag': etag});
      } catch (e) {
        return null;
      }

      uploadedBytes += partBytes.length;
      onProgress?.call(uploadedBytes / totalBytes * 0.9);
    }

    final completeResponse = await getNetworkCaller().postRequest(
      url: uploadUrlEndpoint,
      body: {'uploadId': uploadId, 'parts': etags},
    );

    if (!completeResponse.isSuccess) return null;

    final cr = completeResponse.responseData;
    final cw = cr is Map ? cr['data'] : null;
    final cd = cw is Map ? (cw['data'] ?? cw) : cw;
    final fileUrl = cd is Map ? cd['fileUrl'] as String? : null;

    if (fileUrl == null) return null;

    onProgress?.call(1.0);
    return fileUrl;
  }

  static Future<void> _streamUpload({
    required String url,
    required List<int> bytes,
    required String contentType,
    required Duration timeout,
    void Function(double progress)? onProgress,
  }) async {
    final totalBytes = bytes.length;
    const chunkSize = 65536;

    final request = http.StreamedRequest('PUT', Uri.parse(url));
    request.headers['Content-Type'] = contentType;
    request.contentLength = totalBytes;

    final responseFuture = request.send().timeout(timeout);

    int offset = 0;
    while (offset < totalBytes) {
      final end = (offset + chunkSize).clamp(0, totalBytes);
      request.sink.add(bytes.sublist(offset, end));
      offset = end;
      onProgress?.call(offset / totalBytes);
      await Future.delayed(const Duration(milliseconds: 8));
    }
    await request.sink.close();

    final streamedResponse = await responseFuture;
    if (streamedResponse.statusCode != 200) {
      throw HttpException(
        'S3 upload failed with status ${streamedResponse.statusCode}',
        uri: Uri.parse(url),
      );
    }
  }

  static String inferContentType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
