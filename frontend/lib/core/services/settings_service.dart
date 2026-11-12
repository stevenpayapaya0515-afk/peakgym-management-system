import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';
import 'api_service.dart';

class PasswordChangeException implements Exception {
  const PasswordChangeException(
    this.message, {
    this.retryAfter = 0,
  });

  final String message;
  final int retryAfter;

  @override
  String toString() => message;
}

class SettingsService {
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final token = await TokenStorage.getToken();

    if (token == null || token.isEmpty) {
      throw const PasswordChangeException(
        'Your session has expired. Please log in again.',
      );
    }

    final csrfToken = await ApiService.getCsrfToken();
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/settings/change-password'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-CSRF-Token': csrfToken,
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      }),
    );

    dynamic data;

    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw const PasswordChangeException(
        'The server returned an unexpected response.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final detail = data is Map ? data['detail'] : null;

    final message = detail is List
        ? detail.map((entry) {
            return entry is Map
                ? entry['msg']?.toString() ?? 'Invalid input.'
                : entry.toString();
          }).join('\n')
        : detail?.toString() ?? 'Unable to change your password.';

    throw PasswordChangeException(
      message,
      retryAfter: response.statusCode == 429
          ? int.tryParse(response.headers['retry-after'] ?? '') ?? 60
          : 0,
    );
  }
}