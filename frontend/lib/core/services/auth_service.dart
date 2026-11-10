import 'api_service.dart';

class AuthService {
  // CAPTCHA challenge and matching image. The challenge ID stays in Flutter state.
  static Future<Map<String, dynamic>> getLoginCaptcha() =>
      ApiService.get('/auth/captcha');

  // Step 1: Password + CAPTCHA. This endpoint must NOT return a JWT.
  static Future<Map<String, dynamic>> startLogin({
    required String username,
    required String password,
    required String captchaChallengeId,
    required String captchaAnswer,
  }) => ApiService.post(
    '/auth/login/start',
    body: {
      'username': username,
      'password': password,
      'captcha_challenge_id': captchaChallengeId,
      'captcha_answer': captchaAnswer,
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
    },
  );

  static Future<Map<String, dynamic>> getCurrentUser({
    required String token,
  }) => ApiService.get('/auth/me', token: token);
}
