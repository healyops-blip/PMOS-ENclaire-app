import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmos_enclaire/app/pomi_app.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({
    this.authRepository,
    this.profileRepository,
    this.weightRepository,
    super.key,
  });

  final AuthRepository? authRepository;
  final PatientProfileRepository? profileRepository;
  final WeightRepository? weightRepository;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: PomiApp(
        authRepository: authRepository,
        profileRepository: profileRepository,
        weightRepository: weightRepository,
      ),
    );
  }
}
