import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
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
  const PomiApp({super.key});

  @override
  State<PomiApp> createState() => _PomiAppState();
}

class _PomiAppState extends State<PomiApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: PomiRoutes.login,
    routes: [
      GoRoute(
        path: PomiRoutes.login,
        builder: (context, state) => LoginPage(
          onLogin: (account) {
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
