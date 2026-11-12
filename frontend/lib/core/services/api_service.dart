import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  /// Each mutation receives its own short-lived, one-time server token.
  static Future<String> getCsrfToken() async {
    final response = await http
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
    final response = await http
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': csrfToken,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body ?? {}),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body);

    if (data is Map<String, dynamic>) {
      return {
        ...data,
        'status_code': response.statusCode,
      };
    }

    throw Exception('Invalid server response.');
  }

  static Future<Map<String, dynamic>> get(
    String endpoint, {
    String? token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    final data = jsonDecode(response.body);

    if (data is Map<String, dynamic>) {
      return {
        ...data,
        'status_code': response.statusCode,
      };
    }

    throw Exception('Invalid server response.');
  }
}