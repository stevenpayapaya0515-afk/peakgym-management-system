import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  static Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
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