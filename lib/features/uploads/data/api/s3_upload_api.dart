import 'package:edtech/app/urls.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/global/core/models/network_response.dart';

import '../models/course_init_result.dart';
import '../models/s3_init_response.dart';
class CompleteResult {
  final bool isSuccess;
  final String? fileUrl;
  final String? errorMessage;
  const CompleteResult({required this.isSuccess, this.fileUrl, this.errorMessage});
}
class S3UploadApi {
  const S3UploadApi();
  Future<S3InitResponse?> init({
    required String endpoint,
    required Map<String, dynamic> body,
    String? courseAssetKey,
  }) async {
    final res = await getNetworkCaller().postRequest(url: endpoint, body: body);
    if (!res.isSuccess) return null;
    final data = res.responseData;
    if (data is! Map) return null;
    return S3InitResponse.fromEnvelope(
      Map<String, dynamic>.from(data),
      courseAssetKey: courseAssetKey,
    );
  }

  Future<CourseInitResult?> initCourseAssets({
    required Map<String, dynamic> body,
  }) async {
    final res = await getNetworkCaller().postRequest(
      url: Urls.courseAssetsUploadUrl,
      body: body,
    );
    if (!res.isSuccess) {
      print('initCourseAssets failed: ${res.responseCode} ${res.errorMessage}');
      return null;
    }
    final data = res.responseData;
    if (data is! Map) return null;
    return CourseInitResult.fromEnvelope(Map<String, dynamic>.from(data));
  }

  Future<CompleteResult> complete({
    required String endpoint,
    required String key,
    required String s3UploadId,
    required List<Map<String, dynamic>> parts,
    Map<String, dynamic> extraFields = const {},
  }) async {
    final res = await getNetworkCaller().postRequest(
      url: endpoint,
      body: {
        'key': key,
        'uploadId': s3UploadId,
        'parts': parts,
        ...extraFields,
      },
    );
    if (!res.isSuccess) {
      return CompleteResult(
        isSuccess: false,
        errorMessage: res.errorMessage ?? 'Complete failed',
      );
    }
    final fileUrl = _extractFileUrl(res.responseData);
    if (fileUrl == null || fileUrl.isEmpty) {
      return const CompleteResult(
        isSuccess: false,
        errorMessage: 'Complete response missing fileUrl',
      );
    }
    return CompleteResult(isSuccess: true, fileUrl: fileUrl);
  }

  /// Step 3b — abort a multipart upload on failure. Sends `{key, uploadId}`.
  Future<bool> abort({
    required String endpoint,
    required String key,
    required String s3UploadId,
  }) async {
    final res = await getNetworkCaller().postRequest(
      url: endpoint,
      body: {'key': key, 'uploadId': s3UploadId},
    );
    return res.isSuccess;
  }

  Future<bool> callback({
    required String endpoint,
    required Map<String, dynamic> body,
    String method = 'POST',
    String? idempotencyKey,
  }) async {
    final caller = getNetworkCaller();
    final extraHeaders = idempotencyKey != null
        ? {'Idempotency-Key': idempotencyKey}
        : <String, String>{};
    final res = method.toUpperCase() == 'PUT'
        ? await caller.putRequest(
            url: endpoint, body: body, extraHeaders: extraHeaders)
        : await caller.postRequest(
            url: endpoint, body: body, extraHeaders: extraHeaders);
    if (res.isSuccess) return true;
    return res.responseCode == 409;
  }

  String? _extractFileUrl(dynamic responseData) {
    if (responseData is! Map) return null;
    final d = responseData['data'];
    if (d is Map && d['fileUrl'] is String) return d['fileUrl'] as String;
    if (responseData['fileUrl'] is String) {
      return responseData['fileUrl'] as String;
    }
    // Some course endpoints nest one level deeper.
    if (d is Map && d['data'] is Map && (d['data'] as Map)['fileUrl'] is String) {
      return (d['data'] as Map)['fileUrl'] as String;
    }
    return null;
  }
}

// Re-export for callers that only import the api.
typedef S3NetworkResponse = NetworkResponse;
