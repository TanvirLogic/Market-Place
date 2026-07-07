import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;

import '../../../features/auth/data/models/auth_controller.dart';
import '../models/network_response.dart';
import 'logger_service.dart';

class NetworkCaller {
  final VoidCallback onUnauthorize;
  final Map<String, String>? headers;
  final String? decodedErrorMSGKey;
  final Future<bool> Function()? onRefreshToken;

  NetworkCaller({
    required this.onUnauthorize,
    this.headers,
    this.decodedErrorMSGKey,
    this.onRefreshToken,
  });

  Future<NetworkResponse> getRequest({
    required String url,
    bool skipUnauthorize = false,
  }) async {
    try {
      Uri uri = Uri.parse(url);
      AppLogger.i('→ [GET] $url');
      http.Response response = await http.get(uri, headers: headers);
      return _processResponse(
        response,
        uri: uri,
        method: 'GET',
        skipUnauthorize: skipUnauthorize,
      );
    } on Exception catch (e) {
      return NetworkResponse(
        isSuccess: false,
        responseCode: -1,
        errorMessage: e.toString(),
      );
    }
  }

  Future<NetworkResponse> postRequest({
    required String url,
    Map<String, dynamic>? body,
    bool skipUnauthorize = false,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      Uri uri = Uri.parse(url);
      AppLogger.i('→ [POST] $url');
      if (body != null) AppLogger.i('Body: ${jsonEncode(body)}');
      http.Response response = await http.post(
        uri,
        headers: {...(headers ?? {'content-type': 'application/json'}), ...?extraHeaders},
        body: jsonEncode(body),
      );
      return _processResponse(
        response,
        uri: uri,
        method: 'POST',
        body: body,
        skipUnauthorize: skipUnauthorize,
        extraHeaders: extraHeaders,
      );
    } on Exception catch (e) {
      return NetworkResponse(
        isSuccess: false,
        responseCode: -1,
        errorMessage: e.toString(),
      );
    }
  }

  Future<NetworkResponse> putRequest({
    required String url,
    Map<String, dynamic>? body,
    bool skipUnauthorize = false,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      Uri uri = Uri.parse(url);
      AppLogger.i('→ [PUT] $url');
      if (body != null) AppLogger.i('Body: ${jsonEncode(body)}');
      http.Response response = await http.put(
        uri,
        headers: {...(headers ?? {'content-type': 'application/json'}), ...?extraHeaders},
        body: jsonEncode(body),
      );
      return _processResponse(
        response,
        uri: uri,
        method: 'PUT',
        body: body,
        skipUnauthorize: skipUnauthorize,
        extraHeaders: extraHeaders,
      );
    } on Exception catch (e) {
      return NetworkResponse(
        isSuccess: false,
        responseCode: -1,
        errorMessage: e.toString(),
      );
    }
  }

  Future<NetworkResponse> deleteRequest({
    required String url,
    Map<String, dynamic>? body,
    bool skipUnauthorize = false,
  }) async {
    try {
      Uri uri = Uri.parse(url);
      AppLogger.i('→ [DELETE] $url');
      if (body != null) AppLogger.i('Body: ${jsonEncode(body)}');
      http.Response response = await http.delete(
        uri,
        headers: headers ?? {'content-type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(
        response,
        uri: uri,
        method: 'DELETE',
        skipUnauthorize: skipUnauthorize,
      );
    } on Exception catch (e) {
      return NetworkResponse(
        isSuccess: false,
        responseCode: -1,
        errorMessage: e.toString(),
      );
    }
  }

  Future<NetworkResponse> _processResponse(
    http.Response response, {
    required Uri uri,
    required String method,
    Map<String, dynamic>? body,
    bool skipUnauthorize = false,
    Map<String, String>? extraHeaders,
  }) async {
    final int statusCode = response.statusCode;
    final dynamic decodedBody = _tryDecode(response.body);

    AppLogger.i('[$method] ${uri.path} → $statusCode');
    if (body != null) AppLogger.i('Request body: ${jsonEncode(body)}');
    AppLogger.i('Response: ${_truncate(decodedBody)}');

    if (statusCode == 200 || statusCode == 201) {
      return NetworkResponse(
        isSuccess: true,
        responseCode: statusCode,
        responseData: decodedBody,
      );
    }

    if (statusCode == 401 && !skipUnauthorize) {
      if (onRefreshToken != null) {
        final refreshed = await onRefreshToken!();
        if (refreshed) {
          return _retryWithFreshToken(response, uri, method, body, extraHeaders);
        }
      }
      onUnauthorize();
      return NetworkResponse(
        isSuccess: false,
        responseCode: statusCode,
        errorMessage: _extractError(decodedBody),
      );
    }

    return NetworkResponse(
      isSuccess: false,
      responseCode: statusCode,
      responseData: decodedBody,
      errorMessage: decodedBody is Map
          ? decodedBody[decodedErrorMSGKey ?? 'msg']
          : 'Request failed',
    );
  }

  Future<NetworkResponse> _retryWithFreshToken(
    http.Response originalResponse,
    Uri uri,
    String method,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  ) async {
    final updatedHeaders = <String, String>{
      ...?headers,
      ...?extraHeaders,
      'Authorization': 'Bearer ${AuthController.accessToken ?? ''}',
    };

    http.Response retryResponse;

    switch (method) {
      case 'GET':
        retryResponse = await http.get(uri, headers: updatedHeaders);
        break;
      case 'POST':
        retryResponse = await http.post(
          uri,
          headers: updatedHeaders,
          body: jsonEncode(body),
        );
        break;
      case 'PUT':
        retryResponse = await http.put(
          uri,
          headers: updatedHeaders,
          body: jsonEncode(body),
        );
        break;
      case 'DELETE':
        retryResponse = await http.delete(
          uri,
          headers: updatedHeaders,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      default:
        return NetworkResponse(
          isSuccess: false,
          responseCode: originalResponse.statusCode,
          errorMessage: _extractError(originalResponse.body),
        );
    }

    final retryDecoded = _tryDecode(retryResponse.body);
    AppLogger.i('Retry [$method] ${uri.path} → ${retryResponse.statusCode}');
    if (body != null) AppLogger.i('Retry body: ${jsonEncode(body)}');
    AppLogger.i('Retry response: ${_truncate(retryDecoded)}');

    if (retryResponse.statusCode == 200 || retryResponse.statusCode == 201) {
      return NetworkResponse(
        isSuccess: true,
        responseCode: retryResponse.statusCode,
        responseData: retryDecoded,
      );
    }

    onUnauthorize();
    return NetworkResponse(
      isSuccess: false,
      responseCode: originalResponse.statusCode,
      errorMessage: _extractError(originalResponse.body),
    );
  }

  String _extractError(dynamic decodedBody) {
    if (decodedBody is Map) {
      return decodedBody[decodedErrorMSGKey ?? 'msg'] ?? 'Unauthorized';
    }
    return 'Unauthorized';
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  String _truncate(dynamic data, [int maxLen = 500]) {
    final s = data.toString();
    return s.length > maxLen ? '${s.substring(0, maxLen)}...' : s;
  }
}
