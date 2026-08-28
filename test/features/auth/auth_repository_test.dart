import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/auth/data/session_store.dart';

void main() {
  test(
    'registers, logs in, stores Bearer session, and restores account',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      final calls = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls.add(options.path);
            if (options.path == '/auth/register') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: _account,
                ),
              );
            } else if (options.path == '/auth/login') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'session_id': 'opaque-session',
                    'token_type': 'Bearer',
                    'expires_at': '2026-09-03T04:00:00+00:00',
                    'account': _account,
                  },
                ),
              );
            } else {
              expect(options.headers['Authorization'], 'Bearer opaque-session');
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _account,
                ),
              );
            }
          },
        ),
      );
      final store = _MemorySessionStore();
      final repository = FastApiAuthRepository(PomiApiClient(dio: dio), store);

      final session = await repository.register(
        accountName: 'new-user',
        password: 'StrongPass123',
        phoneNumber: '+8613812345678',
      );
      expect(session.sessionId, 'opaque-session');
      expect(store.value, 'opaque-session');

      final restored = await repository.restore();
      expect(restored?.accountName, 'new-user');
      expect(calls, ['/auth/register', '/auth/login', '/auth/me']);
    },
  );

  test(
    'logout clears the active account cache even when API is unauthorized',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 401),
            ),
          ),
        ),
      );
      var cacheCleared = false;
      final store = _MemorySessionStore()..value = 'session';
      final repository = FastApiAuthRepository(
        PomiApiClient(dio: dio),
        store,
        onLogout: () async => cacheCleared = true,
      );

      await repository.logout();

      expect(cacheCleared, isTrue);
      expect(store.value, isNull);
    },
  );
}

const _account = <String, dynamic>{
  'uid': 'ee7abf29-b21f-4f52-865a-ecf4b50ab45c',
  'account_name': 'new-user',
  'account_type': 'user',
  'onboarding_completed': false,
  'status': 'active',
  'phone_number': '+8613812345678',
  'phone_verified': false,
};

class _MemorySessionStore implements SessionStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String sessionId) async => value = sessionId;
}
