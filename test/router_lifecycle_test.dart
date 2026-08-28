import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pmos_enclaire/app.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/core/router.dart';
import 'package:pmos_enclaire/features/auth/auth_controller.dart';
import 'package:pmos_enclaire/features/auth/login_screen.dart';
import 'package:pmos_enclaire/features/home/app_shell.dart';

import 'support/fake_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  test(
    'keeps one router instance while the stored session is restored',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        sessionIdStorageKey: 'stored-session',
        sessionExpiresAtStorageKey: '2099-09-01T00:00:00Z',
      });
      const storage = FlutterSecureStorage();
      final response = Completer<Map<String, dynamic>>();
      final api = FakeApiClient(
        handler: (call) {
          expect(call.path, '/api/auth/me');
          return response.future;
        },
      );
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      final routerBeforeRestore = container.read(routerProvider);
      final restoredSession = container.read(authControllerProvider.future);

      response.complete({
        'uid': 'uid-alice',
        'account_name': 'alice',
        'onboarding_completed': true,
      });
      await restoredSession;

      expect(
        identical(container.read(routerProvider), routerBeforeRestore),
        isTrue,
        reason: 'Authentication changes must refresh, not replace, the router.',
      );
    },
  );

  testWidgets('restored authentication redirects without replacing the tree', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      sessionIdStorageKey: 'stored-session',
      sessionExpiresAtStorageKey: '2099-09-01T00:00:00Z',
    });
    const storage = FlutterSecureStorage();
    final api = _DeferredSessionSmokeApiClient(storage);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(api),
        ],
        child: const PomiApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);

    api.restoreSession();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppShell), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _DeferredSessionSmokeApiClient extends SmokeApiClient {
  _DeferredSessionSmokeApiClient(super.storage);

  final _session = Completer<Map<String, dynamic>>();

  void restoreSession() {
    _session.complete({
      'uid': 'smoke-user',
      'account_name': 'smoke',
      'onboarding_completed': true,
    });
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) {
    if (path == '/api/auth/me') return _session.future;
    return super.get(path, queryParameters: queryParameters);
  }
}
