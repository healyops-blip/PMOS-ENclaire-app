import 'package:flutter/material.dart';
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

class PomiApp extends StatelessWidget {
  const PomiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pomi',
      debugShowCheckedModeBanner: false,
      theme: PomiTheme.light,
      initialRoute: PomiRoutes.login,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case PomiRoutes.login:
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => LoginPage(
                onLogin: (account) {
                  final route = account.onboardingRequired
                      ? PomiRoutes.onboarding
                      : PomiRoutes.dashboard;
                  Navigator.of(context)
                      .pushReplacementNamed(route, arguments: account);
                },
              ),
            );
          case PomiRoutes.onboarding:
            final account =
                settings.arguments as DemoAccount? ?? DemoAccount.newUser;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => OnboardingPage(
                account: account,
                onCompleted: (profileName) {
                  Navigator.of(context).pushReplacementNamed(
                    PomiRoutes.dashboard,
                    arguments: account.copyWith(displayName: profileName),
                  );
                },
              ),
            );
          case PomiRoutes.dashboard:
            final account =
                settings.arguments as DemoAccount? ?? DemoAccount.existingUser;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => DashboardPage(account: account),
            );
          default:
            return null;
        }
      },
    );
  }
}
