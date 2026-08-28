import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class AuthAccount {
  const AuthAccount({
    required this.uid,
    required this.accountName,
    required this.onboardingCompleted,
  });

  factory AuthAccount.fromJson(Map<String, dynamic> json) {
    final uid = json['uid'];
    final accountName = json['account_name'];
    final onboardingCompleted = json['onboarding_completed'];
    if (uid is! String ||
        accountName is! String ||
        onboardingCompleted is! bool) {
      throw ApiFailure('INVALID_RESPONSE', '服务响应格式异常，请稍后重试');
    }
    return AuthAccount(
      uid: uid,
      accountName: accountName,
      onboardingCompleted: onboardingCompleted,
    );
  }

  final String uid;
  final String accountName;
  final bool onboardingCompleted;
}

class AuthSession {
  const AuthSession({required this.account, this.expiresAt});

  final AuthAccount account;
  final DateTime? expiresAt;

  bool get onboardingRequired => !account.onboardingCompleted;
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final storage = ref.read(secureStorageProvider);
    final sessionId = await storage.read(key: sessionIdStorageKey);
    if (sessionId == null || sessionId.isEmpty) return null;

    final expiresAt =
        DateTime.tryParse(
          await storage.read(key: sessionExpiresAtStorageKey) ?? '',
        )?.toUtc();
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
      await _clearStoredSession();
      return null;
    }

    try {
      final data = await ref.read(apiClientProvider).get('/api/auth/me');
      return AuthSession(
        account: AuthAccount.fromJson(_jsonMap(data)),
        expiresAt: expiresAt,
      );
    } on ApiFailure catch (error) {
      if (error.code == 'AUTHENTICATION_REQUIRED') {
        await _clearStoredSession();
        return null;
      }
      rethrow;
    }
  }

  Future<void> login(String accountName, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _login(accountName.trim(), password));
  }

  Future<void> register(String accountName, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final normalizedAccountName = accountName.trim();
      await ref
          .read(apiClientProvider)
          .post(
            '/api/auth/register',
            data: {'account_name': normalizedAccountName, 'password': password},
          );
      return _login(normalizedAccountName, password);
    });
  }

  Future<AuthSession> _login(String accountName, String password) async {
    final data = _jsonMap(
      await ref
          .read(apiClientProvider)
          .post(
            '/api/auth/login',
            data: {
              'account_name': accountName,
              'password': password,
              'client_platform': _clientPlatform,
            },
          ),
    );
    final sessionId = data['session_id'];
    final expiresAt =
        DateTime.tryParse(data['expires_at']?.toString() ?? '')?.toUtc();
    final accountData = data['account'];
    if (sessionId is! String ||
        sessionId.isEmpty ||
        expiresAt == null ||
        accountData is! Map) {
      throw ApiFailure('INVALID_RESPONSE', '服务响应格式异常，请稍后重试');
    }

    final session = AuthSession(
      account: AuthAccount.fromJson(_jsonMap(accountData)),
      expiresAt: expiresAt,
    );
    final storage = ref.read(secureStorageProvider);
    await storage.write(
      key: sessionExpiresAtStorageKey,
      value: expiresAt.toIso8601String(),
    );
    await storage.write(key: sessionIdStorageKey, value: sessionId);
    return session;
  }

  Future<void> logout() async {
    try {
      await ref.read(apiClientProvider).post('/api/auth/logout');
    } finally {
      await _clearStoredSession();
      state = const AsyncData(null);
    }
  }

  Future<void> _clearStoredSession() async {
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      storage.delete(key: sessionIdStorageKey),
      storage.delete(key: sessionExpiresAtStorageKey),
    ]);
  }
}

Map<String, dynamic> _jsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw ApiFailure('INVALID_RESPONSE', '服务响应格式异常，请稍后重试');
}

String get _clientPlatform {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
