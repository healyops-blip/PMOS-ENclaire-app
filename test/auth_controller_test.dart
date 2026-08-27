import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/features/auth/auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'registration creates an account, logs in, and stores the session',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      final api = _FakeApiClient(storage);
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(authControllerProvider.future), isNull);
      await container
          .read(authControllerProvider.notifier)
          .register(' New.User ', 'StrongPass123');

      final session = container.read(authControllerProvider).value;
      expect(session, isNotNull);
      expect(session!.account.accountName, 'new.user');
      expect(session.onboardingRequired, isTrue);
      expect(api.postPaths, ['/api/auth/register', '/api/auth/login']);
      expect(api.postBodies.last['client_platform'], isNotNull);
      expect(await storage.read(key: sessionIdStorageKey), 'created-session');
      expect(
        await storage.read(key: sessionExpiresAtStorageKey),
        '2099-01-01T00:00:00.000Z',
      );
    },
  );

  test('cold start validates a stored session with auth me', () async {
    FlutterSecureStorage.setMockInitialValues({
      sessionIdStorageKey: 'stored-session',
      sessionExpiresAtStorageKey: '2099-01-01T00:00:00Z',
    });
    const storage = FlutterSecureStorage();
    final api = _FakeApiClient(storage)..meOnboardingCompleted = true;
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final session = await container.read(authControllerProvider.future);
    expect(api.getPaths, ['/api/auth/me']);
    expect(session!.onboardingRequired, isFalse);
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(super.storage);

  final List<String> postPaths = [];
  final List<Map<String, dynamic>> postBodies = [];
  final List<String> getPaths = [];
  bool meOnboardingCompleted = false;

  @override
  Future<dynamic> get(String path) async {
    getPaths.add(path);
    return _account(onboardingCompleted: meOnboardingCompleted);
  }

  @override
  Future<dynamic> post(String path, {Object? data}) async {
    postPaths.add(path);
    postBodies.add(Map<String, dynamic>.from(data! as Map));
    if (path == '/api/auth/register') {
      return _account(onboardingCompleted: false);
    }
    if (path == '/api/auth/login') {
      return {
        'session_id': 'created-session',
        'token_type': 'Bearer',
        'expires_at': '2099-01-01T00:00:00Z',
        'account': _account(onboardingCompleted: false),
      };
    }
    return null;
  }

  Map<String, dynamic> _account({required bool onboardingCompleted}) => {
    'uid': '00000000-0000-0000-0000-000000000001',
    'account_name': 'new.user',
    'account_type': 'user',
    'onboarding_completed': onboardingCompleted,
    'status': 'active',
    'phone_number': null,
    'phone_verified': false,
  };
}
