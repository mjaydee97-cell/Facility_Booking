import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Thin JSON-over-HTTPS client that attaches the JWT to every request.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  String? token;

  /// Called when the server rejects the token (expired / revoked).
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body: body);
  Future<dynamic> put(String path, Object? body) =>
      _send('PUT', path, body: body);
  Future<dynamic> delete(String path, [Object? body]) =>
      _send('DELETE', path, body: body);

  Future<dynamic> _send(String method, String path,
      {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
          await _http.send(request).timeout(const Duration(seconds: 20)));
    } on SocketException {
      throw ApiException(0, 'Cannot reach the server. Check your connection.');
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond.');
    }

    final decoded =
        response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && token != null) onUnauthorized?.call();
      var message = 'Request failed (${response.statusCode})';
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
        final details = decoded['details'];
        if (details is List && details.isNotEmpty) {
          message += ': ${details.map((d) => '${d['field']} ${d['message']}').join(', ')}';
        }
      }
      throw ApiException(response.statusCode, message);
    }
    return decoded;
  }
}
