import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/auth/data/session_store.dart';
import 'package:pmos_enclaire/features/reports/data/report_pdf_repository.dart';

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
        onSessionCleared: () async => cacheCleared = true,
      );

      await repository.logout();

      expect(cacheCleared, isTrue);
      expect(store.value, isNull);
    },
  );

  test('logout clears every account-scoped private PDF cache', () async {
    final root = await Directory.systemTemp.createTemp('pomi-auth-cache-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    Future<Directory> directoryProvider() async => root;
    final bytes = Uint8List.fromList('%PDF-1.7\nprivate'.codeUnits);
    final accountA = ReportPdfCache(
      accountScope: 'account-a',
      directoryProvider: directoryProvider,
    );
    final accountB = ReportPdfCache(
      accountScope: 'account-b',
      directoryProvider: directoryProvider,
    );
    final fileA = await accountA.store(reportId: 'report-a', bytes: bytes);
    final fileB = await accountB.store(reportId: 'report-b', bytes: bytes);

    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<void>(requestOptions: options, statusCode: 204),
        ),
      ),
    );
    final store = _MemorySessionStore()..value = 'opaque-session';
    final client = PomiApiClient(dio: dio)..useSession('opaque-session');
    var clearCalls = 0;
    final repository = FastApiAuthRepository(
      client,
      store,
      onSessionCleared: () async {
        clearCalls += 1;
        await ReportPdfCache.clearAllAccounts(
          directoryProvider: directoryProvider,
        );
      },
    );

    await repository.logout();

    expect(store.value, isNull);
    expect(client.dio.options.headers['Authorization'], isNull);
    expect(clearCalls, 1);
    expect(await fileA.exists(), isFalse);
    expect(await fileB.exists(), isFalse);
  });

  test('a restored 401 session clears local private data once', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response<void>(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
          ),
        ),
      ),
    );
    final store = _MemorySessionStore()..value = 'expired-session';
    final client = PomiApiClient(dio: dio);
    var clearCalls = 0;
    final repository = FastApiAuthRepository(
      client,
      store,
      onSessionCleared: () async => clearCalls += 1,
    );

    expect(await repository.restore(), isNull);
    expect(store.value, isNull);
    expect(client.dio.options.headers['Authorization'], isNull);
    expect(clearCalls, 1);
  });

  test(
    'a secure-store clear failure still drops the bearer and remains retryable',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<void>(requestOptions: options, statusCode: 204),
          ),
        ),
      );
      final store = _FailOnceSessionStore()..value = 'opaque-session';
      final client = PomiApiClient(dio: dio)..useSession('opaque-session');
      var privateClearCalls = 0;
      final repository = FastApiAuthRepository(
        client,
        store,
        onSessionCleared: () async => privateClearCalls += 1,
      );

      await expectLater(repository.logout(), throwsStateError);
      expect(client.dio.options.headers['Authorization'], isNull);
      expect(store.value, 'opaque-session');
      expect(privateClearCalls, 1);

      await repository.logout();
      expect(store.value, isNull);
      expect(store.clearCalls, 2);
      expect(privateClearCalls, 2);
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

class _FailOnceSessionStore extends _MemorySessionStore {
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    if (clearCalls == 1) throw StateError('simulated secure-store failure');
    await super.clear();
  }
}
