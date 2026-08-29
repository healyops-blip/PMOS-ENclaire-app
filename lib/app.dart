import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

class PomiApp extends ConsumerWidget {
  const PomiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Pomi',
      debugShowCheckedModeBanner: false,
      theme: buildPomiTheme(),
      routerConfig: ref.watch(routerProvider),
      builder:
          (context, child) =>
              PomiAppBackground(child: child ?? const SizedBox.shrink()),
    );
  }
}
