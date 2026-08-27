import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/auth/data/session_store.dart';
import 'package:pmos_enclaire/features/auth/domain/account.dart';

abstract interface class AuthRepository {
  Future<AuthSession> login({
    required String accountName,
    required String password,
  });

  Future<AuthSession> register({
    required String accountName,
    required String password,
    String? phoneNumber,
  });

  Future<Account?> restore();

  Future<void> logout();
}

class FastApiAuthRepository implements AuthRepository {
  FastApiAuthRepository(this.client, this.sessionStore);

  final PomiApiClient client;
  final SessionStore sessionStore;

  @override
  Future<AuthSession> login({
    required String accountName,
    required String password,
  }) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'account_name': accountName,
          'password': password,
          'client_platform': 'flutter',
        },
      );
      final json = response.data!;
      final session = AuthSession(
        sessionId: json['session_id'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        account: Account.fromJson(
          Map<String, dynamic>.from(json['account'] as Map),
        ),
      );
      await sessionStore.write(session.sessionId);
      client.useSession(session.sessionId);
      return session;
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<AuthSession> register({
    required String accountName,
    required String password,
    String? phoneNumber,
  }) async {
    try {
      await client.dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'account_name': accountName,
          'password': password,
          if (phoneNumber != null && phoneNumber.isNotEmpty)
            'phone_number': phoneNumber,
        },
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
    return login(accountName: accountName, password: password);
  }

  @override
  Future<Account?> restore() async {
    final sessionId = await sessionStore.read();
    if (sessionId == null || sessionId.isEmpty) return null;
    client.useSession(sessionId);
    try {
      final response = await client.dio.get<Map<String, dynamic>>('/auth/me');
      return Account.fromJson(response.data!);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await sessionStore.clear();
        client.useSession(null);
        return null;
      }
      throw _failure(error);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await client.dio.post<void>('/auth/logout');
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) throw _failure(error);
    } finally {
      await sessionStore.clear();
      client.useSession(null);
    }
  }

  AuthFailure _failure(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      final value = body['error'] as Map;
      final code = value['code']?.toString() ?? 'REQUEST_FAILED';
      return AuthFailure(code, _message(code));
    }
    return const AuthFailure('NETWORK_ERROR', '无法连接服务，请检查网络后重试');
  }

  String _message(String code) {
    return switch (code) {
      'INVALID_CREDENTIALS' => '账号名或密码错误',
      'ACCOUNT_NAME_TAKEN' => '这个账号名已经被使用',
      'AUTH_RATE_LIMITED' => '尝试次数过多，请稍后再试',
      'VALIDATION_ERROR' => '请检查账号名、密码或手机号格式',
      _ => '请求失败，请稍后重试',
    };
  }
}

class DemoAuthRepository implements AuthRepository {
  const DemoAuthRepository();

  @override
  Future<AuthSession> login({
    required String accountName,
    required String password,
  }) async {
    final isNew = accountName == 'pomi_new';
    return AuthSession(
      sessionId: 'demo-session',
      expiresAt: DateTime(2099),
      account: Account(
        uid: isNew ? 'preset-new-user' : 'preset-existing-user',
        accountName: accountName,
        accountType: 'user',
        onboardingCompleted: !isNew,
        status: 'active',
        phoneVerified: false,
      ),
    );
  }

  @override
  Future<AuthSession> register({
    required String accountName,
    required String password,
    String? phoneNumber,
  }) async {
    return AuthSession(
      sessionId: 'demo-session',
      expiresAt: DateTime(2099),
      account: Account(
        uid: 'preset-new-user',
        accountName: accountName,
        accountType: 'user',
        onboardingCompleted: false,
        status: 'active',
        phoneNumber: phoneNumber,
        phoneVerified: false,
      ),
    );
  }

  @override
  Future<Account?> restore() async => null;

  @override
  Future<void> logout() async {}
}
