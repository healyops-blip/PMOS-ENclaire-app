import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmos_enclaire/app/pomi_app.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({this.authRepository, super.key});

  final AuthRepository? authRepository;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: PomiApp(authRepository: authRepository));
  }
}
