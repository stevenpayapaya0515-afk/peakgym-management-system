import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

class RegistrationException implements Exception {
  const RegistrationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RegistrationService {
  static Future<Map<String, dynamic>> _request(
    String method,
    String route, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final url = Uri.parse('${ApiService.baseUrl}$route');
      final headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (method != 'GET') {
        headers['X-CSRF-Token'] = await ApiService.getCsrfToken();
      }
      final http.Response response;
      if (method == 'GET') {
        response = await http
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 20));
      } else {
        response = await http
            .post(url, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 35));
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const RegistrationException(
          'Unexpected response from PeakGym server.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded['detail'];
        if (detail is String) throw RegistrationException(detail);
        if (detail is List) {
          final items = detail.map((x) {
            if (x is Map && x['msg'] is String) return x['msg'] as String;
            return x.toString();
          }).toList();
          throw RegistrationException(items.join('\n'));
        }
        throw RegistrationException(
          'Request failed (HTTP ${response.statusCode}).',
        );
      }
      return decoded;
    } on RegistrationException {
      rethrow;
    } catch (_) {
      throw const RegistrationException(
        'Unable to connect to PeakGym. Check that FastAPI is running.',
      );
    }
  }

  static Future<Map<String, dynamic>> validateInvitation(String token) =>
      _request('POST', '/invitations/validate', body: {'token': token});

  static Future<Map<String, dynamic>> start(Map<String, dynamic> data) =>
      _request('POST', '/registration/start', body: data);

  static Future<Map<String, dynamic>> verifyOtp(String token, String code) =>
      _request(
        'POST',
        '/registration/verify-otp',
        body: {'registration_token': token, 'otp_code': code},
      );

  static Future<Map<String, dynamic>> resendOtp(String token) => _request(
    'POST',
    '/registration/resend-otp',
    body: {'registration_token': token},
  );

  static Future<Map<String, dynamic>> activate(String token) => _request(
    'POST',
    '/registration/activate',
    body: {'registration_token': token},
  );
}
