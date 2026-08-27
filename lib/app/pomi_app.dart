import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/auth/data/session_store.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/auth/presentation/login_page.dart';
import 'package:pmos_enclaire/features/cycle/data/cycle_repository.dart';
import 'package:pmos_enclaire/features/dashboard/presentation/dashboard_page.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_cache_store.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_repository.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';
import 'package:pmos_enclaire/features/onboarding/presentation/onboarding_page.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

abstract final class PomiRoutes {
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const dashboard = '/dashboard';
}

class PomiApp extends StatefulWidget {
  const PomiApp({
    this.authRepository,
    this.profileRepository,
    this.dashboardRepository,
    this.patientNoteRepository,
    this.documentRepository,
    this.ocrRepository,
    this.weightRepository,
    this.apiClient,
    this.now,
    this.cycleRepository,
    this.medicationRepository,
    super.key,
  });

  final AuthRepository? authRepository;
  final PatientProfileRepository? profileRepository;
  final DashboardRepository? dashboardRepository;
  final PatientNoteRepository? patientNoteRepository;
  final DocumentRepository? documentRepository;
  final OcrRepository? ocrRepository;
  final WeightRepository? weightRepository;
  final PomiApiClient? apiClient;
  final DateTime Function()? now;
  final CycleRepository? cycleRepository;
  final MedicationRepository? medicationRepository;

  @override
  State<PomiApp> createState() => _PomiAppState();
}

class _PomiAppState extends State<PomiApp> {
  late final PomiApiClient _apiClient = widget.apiClient ?? PomiApiClient();
  late final AuthRepository _authRepository =
      widget.authRepository ??
      FastApiAuthRepository(
        _apiClient,
        SecureSessionStore(),
        onLogout: _clearActiveDashboardCache,
      );
  late final PatientProfileRepository _profileRepository =
      widget.profileRepository ??
      (widget.authRepository is DemoAuthRepository
          ? DemoPatientProfileRepository()
          : FastApiPatientProfileRepository(_apiClient));
  late final DashboardRepository _dashboardRepository =
      widget.dashboardRepository ??
      (widget.authRepository is DemoAuthRepository
          ? const DemoDashboardRepository()
          : FastApiDashboardRepository(
              _apiClient,
              SecureDashboardCacheStore(),
            ));
  late final PatientNoteRepository _patientNoteRepository =
      widget.patientNoteRepository ??
      (widget.authRepository is DemoAuthRepository
          ? DemoPatientNoteRepository()
          : FastApiPatientNoteRepository(_apiClient));
  late final DocumentRepository _documentRepository =
      widget.documentRepository ??
      (widget.authRepository is DemoAuthRepository
          ? DemoDocumentRepository()
          : FastApiDocumentRepository(_apiClient));
  late final OcrRepository _ocrRepository =
      widget.ocrRepository ??
      (widget.authRepository is DemoAuthRepository
          ? DemoOcrRepository()
          : FastApiOcrRepository(_apiClient));
  late final WeightRepository _weightRepository =
      widget.weightRepository ??
      (widget.authRepository is DemoAuthRepository
          ? MemoryWeightRepository.seeded()
          : ApiWeightRepository(_apiClient));
  late final CycleRepository? _cycleRepository =
      widget.cycleRepository ??
      (widget.authRepository is DemoAuthRepository
          ? null
          : FastApiCycleRepository(_apiClient));
  late final MedicationRepository? _medicationRepository =
      widget.medicationRepository ??
      (widget.authRepository is DemoAuthRepository
          ? null
          : FastApiMedicationRepository(_apiClient));
  String? _activeUid;

  Future<void> _clearActiveDashboardCache() async {
    final uid = _activeUid;
    if (uid != null) await _dashboardRepository.clear(uid);
    _activeUid = null;
  }

  Future<void> _activateUid(String uid) async {
    final previous = _activeUid;
    if (previous != null && previous != uid) {
      await _dashboardRepository.clear(previous);
    }
    _activeUid = uid;
  }

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
            await _activateUid(account.uid);
            if (!context.mounted) return;
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
            onCompleted: (input) async {
              final profile = await _profileRepository.update(input);
              if (!context.mounted) return;
              context.go(
                PomiRoutes.dashboard,
                extra: account.copyWith(
                  displayName: profile.nickname ?? account.displayName,
                ),
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
          return DashboardPage(
            account: account,
            profileRepository: _profileRepository,
            dashboardRepository: _dashboardRepository,
            onLogout: () async {
              try {
                await _authRepository.logout();
              } finally {
                if (context.mounted) context.go(PomiRoutes.login);
              }
            },
            patientNoteRepository: _patientNoteRepository,
            documentRepository: _documentRepository,
            ocrRepository: _ocrRepository,
            weightRepository: _weightRepository,
            now: widget.now,
            cycleRepository: _cycleRepository,
            medicationRepository: _medicationRepository,
          );
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
      await _activateUid(presentation.uid);
      if (!mounted) return;
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
