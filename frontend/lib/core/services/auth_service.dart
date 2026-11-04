import 'api_service.dart';

class AuthService {
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    return await ApiService.post(
      '/auth/login',
      body: {
        'username': username,
        'password': password,
      },
    );
  }

  static Future<Map<String, dynamic>> getCurrentUser({
    required String token,
  }) async {
    return await ApiService.get(
      '/auth/me',
      token: token,
    );
  }
}