import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'auth_session';
  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  Future<void> saveSession(String value) {
    return _storage.write(key: _sessionKey, value: value);
  }

  Future<String?> readSession() {
    return _storage.read(key: _sessionKey);
  }

  Future<void> deleteSession() {
    return _storage.delete(key: _sessionKey);
  }

  Future<void> saveRefreshToken(String token) {
    return _storage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> deleteRefreshToken() {
    return _storage.delete(key: _refreshTokenKey);
  }
}
