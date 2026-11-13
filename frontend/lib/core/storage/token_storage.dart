import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'access_token';

  static bool get usesCookieSession => kIsWeb;

  static Future<void> saveToken(String token) async {
    if (kIsWeb) return; // Never persist an access token in browser storage.
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    if (kIsWeb) return null;
    return _storage.read(key: _tokenKey);
  }

  static Future<void> deleteToken() async {
    // Remove any older readable token saved before browser cookie migration.
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      if (!kIsWeb) rethrow;
    }
  }
}
