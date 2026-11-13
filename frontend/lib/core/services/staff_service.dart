import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';
import 'api_service.dart';

class StaffService {
  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final token = await TokenStorage.getToken();

    if (!TokenStorage.usesCookieSession && (token == null || token.isEmpty)) {
      throw Exception('Your session has expired. Please log in again.');
    }

    // Invitations already carry their own one-time CSRF token.
    final existingCsrf = extraHeaders?['X-CSRF-Token'];
    final csrfToken = method == 'GET' || existingCsrf != null
        ? null
        : await ApiService.getCsrfToken();

    final request = http.Request(
      method,
      Uri.parse('${ApiService.baseUrl}$path'),
    );

    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...ApiService.authHeaders(token),
    });

    if (csrfToken != null) {
      request.headers['X-CSRF-Token'] = csrfToken;
    }

    if (extraHeaders != null) {
      request.headers.addAll(extraHeaders);
    }

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamed = await ApiService.client.send(request);
    final response = await http.Response.fromStream(streamed);

    dynamic data;

    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        throw Exception(
          'The server returned an unexpected response '
          '(${response.statusCode}).',
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    if (response.statusCode == 401) {
      throw Exception('Your session has expired. Please log in again.');
    }

    final detail = data is Map ? data['detail'] : null;

    if (detail is List) {
      final messages = detail
          .map((item) {
            if (item is Map) {
              return item['msg']?.toString() ?? 'Invalid input.';
            }
            return item.toString();
          })
          .join('\n');

      throw Exception(messages);
    }

    throw Exception(
      detail?.toString() ?? 'Request failed (${response.statusCode}).',
    );
  }

  static Future<List<Map<String, dynamic>>> getStaff() async {
    final data = await _request('GET', '/users/');

    if (data is! List) {
      throw Exception('Invalid staff list returned by the server.');
    }

    return data
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((user) => user['role'] == 'staff')
        .toList();
  }

  /// Admin-only: get a one-time CSRF token, then email a staff invitation.
  /// No password is created here; staff provide their own during registration.
  static Future<void> inviteStaff({required String email}) async {
    final csrfData = await _request('GET', '/invitations/csrf');
    if (csrfData is! Map ||
        csrfData['csrf_token'] is! String ||
        (csrfData['csrf_token'] as String).isEmpty) {
      throw Exception('Unable to obtain the invitation security token.');
    }

    await _request(
      'POST',
      '/invitations/',
      extraHeaders: {'X-CSRF-Token': csrfData['csrf_token'] as String},
      body: {'email': email.trim().toLowerCase()},
    );
  }

  static Future<void> changeStatus(int id, bool active) async {
    // FastAPI expects is_active as a query parameter.
    await _request('PATCH', '/users/$id/status?is_active=$active');
  }

  static Future<void> deleteStaff(int id) async {
    await _request('DELETE', '/users/$id');
  }
}
