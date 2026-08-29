import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/features/auth/auth_controller.dart';

import 'support/fake_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'login stores the session and cold start restores the account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      final loginApi = FakeApiClient(
        handler: (call) {
          expect(call.path, '/api/auth/login');
          expect(call.data, {
            'account_name': 'alice',
            'password': 'Secret123',
            'client_platform': isA<String>(),
          });
          return {
            'session_id': 'stored-session',
            'expires_at': '2099-09-01T00:00:00Z',
            'account': {
              'uid': 'uid-alice',
              'account_name': 'alice',
              'onboarding_completed': false,
            },
          };
        },
      );
      final loginContainer = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(loginApi),
        ],
      );
      addTearDown(loginContainer.dispose);
      await loginContainer.read(authControllerProvider.future);

      await loginContainer
          .read(authControllerProvider.notifier)
          .login(' alice ', 'Secret123');

      final loggedIn = loginContainer.read(authControllerProvider).requireValue;
      expect(loggedIn?.account.uid, 'uid-alice');
      expect(loggedIn?.onboardingRequired, isTrue);
      expect(await storage.read(key: sessionIdStorageKey), 'stored-session');

      final restoreApi = FakeApiClient(
        handler: (call) {
          expect(call.path, '/api/auth/me');
          return {
            'uid': 'uid-alice',
            'account_name': 'alice',
            'onboarding_completed': true,
          };
        },
      );
      final restoreContainer = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(restoreApi),
        ],
      );
      addTearDown(restoreContainer.dispose);

      final restored = await restoreContainer.read(
        authControllerProvider.future,
      );

      expect(restored?.account.accountName, 'alice');
      expect(restored?.account.onboardingCompleted, isTrue);
      expect(restoreApi.calls.single.method, 'GET');
    },
  );

  test('expired local session is cleared without a network request', () async {
    FlutterSecureStorage.setMockInitialValues({
      sessionIdStorageKey: 'expired-session',
      sessionExpiresAtStorageKey: '2020-01-01T00:00:00Z',
    });
    const storage = FlutterSecureStorage();
    final api = FakeApiClient(
      handler: (_) => fail('network should not be called'),
    );
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(authControllerProvider.future), isNull);
    expect(await storage.read(key: sessionIdStorageKey), isNull);
    expect(api.calls, isEmpty);
  });
}
