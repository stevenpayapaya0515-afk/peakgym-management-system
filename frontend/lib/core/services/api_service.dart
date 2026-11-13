import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client_native.dart'
    if (dart.library.js_interop) 'api_client_web.dart' as api_client;

class ApiService {
  // The development API must use the SAME HOST as the Flutter Web page:
  // localhost:3000 -> localhost:8000, 127.0.0.1:3000 -> 127.0.0.1:8000.
  // Mixed hosts make SameSite=Lax cookies fail on browser API requests.
  // Configure an HTTPS endpoint with --dart-define=API_BASE_URL=... when deployed.
  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) return '${Uri.base.scheme}://${Uri.base.host}:8000';
    return 'http://127.0.0.1:8000';
  }

  static final http.Client client = api_client.createApiClient();

  static Map<String, String> authHeaders(String? token) => {
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// Each state-changing request receives a short-lived, one-time CSRF token.
  static Future<String> getCsrfToken() async {
    final response = await client
        .get(
          Uri.parse('$baseUrl/security/csrf'),
          headers: {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Unable to request a CSRF security token.');
    }
    final data = jsonDecode(response.body);
    final csrfToken = data is Map ? data['csrf_token'] : null;
    if (csrfToken is! String || csrfToken.isEmpty) {
      throw Exception('Invalid CSRF security token returned by the server.');
    }
    return csrfToken;
  }

  static Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final csrfToken = await getCsrfToken();
    final response = await client
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': csrfToken,
            ...authHeaders(token),
          },
          body: jsonEncode(body ?? {}),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      return {...data, 'status_code': response.statusCode};
    }
    throw Exception('Invalid server response.');
  }

  static Future<Map<String, dynamic>> get(
    String endpoint, {
    String? token,
  }) async {
    final response = await client.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Accept': 'application/json',
        ...authHeaders(token),
      },
    );
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      return {...data, 'status_code': response.statusCode};
    }
    throw Exception('Invalid server response.');
  }
}
