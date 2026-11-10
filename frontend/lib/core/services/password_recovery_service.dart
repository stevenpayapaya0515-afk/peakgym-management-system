import 'api_service.dart';

class PasswordRecoveryService {
  static Future<Map<String, dynamic>> getCaptcha() =>
      ApiService.get('/auth/captcha');

  static Future<Map<String, dynamic>> identify({
    required String username,
    required String captchaChallengeId,
    required String captchaAnswer,
  }) => ApiService.post(
    '/auth/password-recovery/identify',
    body: {
      'username': username.trim(),
      'captcha_challenge_id': captchaChallengeId,
      'captcha_answer': captchaAnswer.trim(),
    },
  );

  static Future<Map<String, dynamic>> answerQuestion({
    required String recoveryTicket,
    required int questionId,
    required String answer,
    required String confirmAnswer,
  }) => ApiService.post(
    '/auth/password-recovery/answer',
    body: {
      'recovery_ticket': recoveryTicket,
      'question_id': questionId,
      'answer': answer,
      'confirm_answer': confirmAnswer,
    },
  );

  static Future<Map<String, dynamic>> requestCode({
    required String username,
    required String recoveryProof,
  }) => ApiService.post(
    '/auth/password-recovery/request',
    body: {'username': username.trim(), 'recovery_proof': recoveryProof},
  );

  static Future<Map<String, dynamic>> verifyCode({
    required String username,
    required String recoveryProof,
    required String code,
  }) => ApiService.post(
    '/auth/password-recovery/verify',
    body: {
      'username': username.trim(),
      'recovery_proof': recoveryProof,
      'otp_code': code.trim(),
    },
  );

  static Future<Map<String, dynamic>> complete({
    required String username,
    required String recoveryProof,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) => ApiService.post(
    '/auth/password-recovery/complete',
    body: {
      'username': username.trim(),
      'recovery_proof': recoveryProof,
      'otp_code': code.trim(),
      'new_password': newPassword,
      'confirm_password': confirmPassword,
    },
  );
}
