import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmos_enclaire/app/pomi_app.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/cycle/data/cycle_repository.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({
    this.authRepository,
    this.profileRepository,
    this.patientNoteRepository,
    this.documentRepository,
    this.weightRepository,
    this.apiClient,
    this.now,
    this.cycleRepository,
    this.medicationRepository,
    super.key,
  });

  final AuthRepository? authRepository;
  final PatientProfileRepository? profileRepository;
  final PatientNoteRepository? patientNoteRepository;
  final DocumentRepository? documentRepository;
  final WeightRepository? weightRepository;
  final PomiApiClient? apiClient;
  final DateTime Function()? now;
  final CycleRepository? cycleRepository;
  final MedicationRepository? medicationRepository;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: PomiApp(
        authRepository: authRepository,
        profileRepository: profileRepository,
        patientNoteRepository: patientNoteRepository,
        documentRepository: documentRepository,
        weightRepository: weightRepository,
        apiClient: apiClient,
        now: now,
        cycleRepository: cycleRepository,
        medicationRepository: medicationRepository,
      ),
    );
  }
}
