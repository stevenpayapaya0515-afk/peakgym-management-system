import 'api_service.dart';

class PasswordRecoveryService {
  static Future<Map<String, dynamic>> requestCode(String email) {
    return ApiService.post(
      '/auth/password-recovery/request',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  static Future<Map<String, dynamic>> verifyCode({
    required String email,
    required String code,
  }) {
    return ApiService.post(
      '/auth/password-recovery/verify',
      body: {
        'email': email.trim().toLowerCase(),
        'otp_code': code.trim(),
      },
    );
  }

  static Future<Map<String, dynamic>> complete({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) {
    return ApiService.post(
      '/auth/password-recovery/complete',
      body: {
        'email': email.trim().toLowerCase(),
        'otp_code': code.trim(),
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      },
    );
  }
}
