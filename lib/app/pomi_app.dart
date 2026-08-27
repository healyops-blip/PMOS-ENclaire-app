import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/auth/data/session_store.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/auth/presentation/login_page.dart';
import 'package:pmos_enclaire/features/dashboard/presentation/dashboard_page.dart';
import 'package:pmos_enclaire/features/onboarding/presentation/onboarding_page.dart';

abstract final class PomiRoutes {
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const dashboard = '/dashboard';
}

class PomiApp extends StatefulWidget {
  const PomiApp({this.authRepository, super.key});

  final AuthRepository? authRepository;

  @override
  State<PomiApp> createState() => _PomiAppState();
}

class _PomiAppState extends State<PomiApp> {
  late final AuthRepository _authRepository =
      widget.authRepository ??
      FastApiAuthRepository(PomiApiClient(), SecureSessionStore());

  late final GoRouter _router = GoRouter(
    initialLocation: PomiRoutes.login,
    routes: [
      GoRoute(
        path: PomiRoutes.login,
        builder: (context, state) => LoginPage(
          onSubmit: (submission) async {
            final session = submission.registering
                ? await _authRepository.register(
                    accountName: submission.accountName,
                    password: submission.password,
                    phoneNumber: submission.phoneNumber,
                  )
                : await _authRepository.login(
                    accountName: submission.accountName,
                    password: submission.password,
                  );
            if (!context.mounted) return;
            final account = session.account.toPresentationAccount();
            final route = account.onboardingRequired
                ? PomiRoutes.onboarding
                : PomiRoutes.dashboard;
            context.go(route, extra: account);
          },
        ),
      ),
      GoRoute(
        path: PomiRoutes.onboarding,
        builder: (context, state) {
          final account = state.extra as DemoAccount? ?? DemoAccount.newUser;
          return OnboardingPage(
            account: account,
            onCompleted: (profileName) {
              context.go(
                PomiRoutes.dashboard,
                extra: account.copyWith(displayName: profileName),
              );
            },
          );
        },
      ),
      GoRoute(
        path: PomiRoutes.dashboard,
        builder: (context, state) {
          final account =
              state.extra as DemoAccount? ?? DemoAccount.existingUser;
          return DashboardPage(account: account);
        },
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final account = await _authRepository.restore();
      if (!mounted || account == null) return;
      final presentation = account.toPresentationAccount();
      _router.go(
        presentation.onboardingRequired
            ? PomiRoutes.onboarding
            : PomiRoutes.dashboard,
        extra: presentation,
      );
    } catch (_) {
      // Keep the login page visible when a transient restore request fails.
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Pomi',
      debugShowCheckedModeBanner: false,
      theme: PomiTheme.light,
      routerConfig: _router,
    );
  }
}
