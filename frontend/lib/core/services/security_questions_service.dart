import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';
import 'api_service.dart';

class SecurityQuestionsException implements Exception {
  const SecurityQuestionsException(this.message, {this.retryAfter = 0});

  final String message;
  final int retryAfter;

  @override
  String toString() => message;
}

class SecurityQuestionsService {
  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    final token = await TokenStorage.getToken();
    if (token == null || token.isEmpty) {
      throw const SecurityQuestionsException(
        'Your session has expired. Please log in again.',
      );
    }

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}$path'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 35));
    } catch (_) {
      throw const SecurityQuestionsException(
        'Could not reach FastAPI. Check your connection and try again.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const SecurityQuestionsException('Unexpected server response.');
    }

    final data = decoded is Map ? decoded : <String, dynamic>{};
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }

    final detail = data['detail'];
    final message = detail is List
        ? detail.map((item) => item is Map ? item['msg'] : item).join('\n')
        : detail?.toString() ?? 'Unable to update security questions.';

    throw SecurityQuestionsException(
      message,
      retryAfter: int.tryParse(response.headers['retry-after'] ?? '') ?? 0,
    );
  }

  static Future<Map<String, dynamic>> requestCode(String currentPassword) {
    return _post('/settings/security-questions/request-code', {
      'current_password': currentPassword,
    });
  }

  static Future<Map<String, dynamic>> updateAnswers({
    required String otpCode,
    required String q4,
    required String q7,
    required String q1,
  }) {
    return _post('/settings/security-questions/update', {
      'otp_code': otpCode,
      'security_answer_q4': q4,
      'security_answer_q7': q7,
      'security_answer_q1': q1,
    });
  }
}
