import 'api_service.dart';
import '../storage/token_storage.dart';

class AuthService {
  // Step 1: Password + CAPTCHA. This endpoint must NOT return a JWT.
  static Future<Map<String, dynamic>> startLogin({
    required String username,
    required String password,
    required String recaptchaToken,
  }) => ApiService.post(
    '/auth/login/start',
    body: {
      'username': username,
      'password': password,
      'recaptcha_token': recaptchaToken,
    },
  );

  // Step 2: Only a verified email OTP can produce an access token.
  static Future<Map<String, dynamic>> verifyLoginOtp({
    required String username,
    required String otpCode,
  }) => ApiService.post(
    '/auth/login/verify-otp',
    body: {
      'username': username,
      'otp_code': otpCode,
      'token_transport': TokenStorage.usesCookieSession ? 'cookie' : 'bearer',
    },
  );

  static Future<Map<String, dynamic>> getCurrentUser({
    required String token,
  }) => ApiService.get('/auth/me', token: token);
}
