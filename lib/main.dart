import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmos_enclaire/app/pomi_app.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_repository.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({
    this.authRepository,
    this.profileRepository,
    this.patientNoteRepository,
    this.reportRepository,
    this.weightRepository,
    this.documentRepository,
    super.key,
  });

  final AuthRepository? authRepository;
  final PatientProfileRepository? profileRepository;
  final PatientNoteRepository? patientNoteRepository;
  final ReportRepository? reportRepository;
  final WeightRepository? weightRepository;
  final DocumentRepository? documentRepository;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: PomiApp(
        authRepository: authRepository,
        profileRepository: profileRepository,
        patientNoteRepository: patientNoteRepository,
        reportRepository: reportRepository,
        weightRepository: weightRepository,
        documentRepository: documentRepository,
      ),
    );
  }
}
