import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionStore {
  Future<String?> read();

  Future<void> write(String sessionId);

  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'pomi.session_id';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _sessionKey);

  @override
  Future<void> write(String sessionId) {
    return _storage.write(key: _sessionKey, value: sessionId);
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}
