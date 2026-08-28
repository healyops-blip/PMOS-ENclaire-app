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
import 'package:pmos_enclaire/features/reports/data/report_pdf_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_repository.dart';
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
    this.reportRepository,
    this.reportPdfRepository,
    this.reportPdfCache,
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
  final ReportRepository? reportRepository;
  final ReportPdfRepository? reportPdfRepository;
  final ReportPdfCache? reportPdfCache;
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
        onSessionCleared: _clearPrivateSessionData,
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
  late final ReportRepository _reportRepository =
      widget.reportRepository ??
      (widget.authRepository is DemoAuthRepository
          ? DemoReportRepository()
          : FastApiReportRepository(_apiClient));
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

  Future<void> _clearPrivateSessionData() async {
    final uid = _activeUid;
    _activeUid = null;
    if (mounted) _router.go(PomiRoutes.login);
    try {
      if (uid != null) await _dashboardRepository.clear(uid);
    } on Object {
      // One private cache failing must not prevent the others being purged.
    }
    try {
      await widget.reportPdfCache?.clearAll();
    } on Object {
      // Continue with the global cache purge and signed-out routing.
    }
    try {
      await ReportPdfCache.clearAllAccounts();
    } on Object {
      // Session removal and signed-out routing remain mandatory.
    }
  }

  Future<void> _activateUid(String uid) async {
    final previous = _activeUid;
    if (previous != null && previous != uid) {
      try {
        await _dashboardRepository.clear(previous);
      } on Object {
        // Continue clearing other account-scoped private data.
      }
      try {
        final injectedCache = widget.reportPdfCache;
        if (injectedCache == null) {
          await ReportPdfCache(accountScope: previous).clearAll();
        } else {
          await injectedCache.clearAll();
        }
      } on Object {
        // A stale temporary file must not strand a successful new login.
      }
    }
    _activeUid = uid;
  }

  late final ReportPdfRepository _reportPdfRepository =
      widget.reportPdfRepository ??
      (widget.authRepository is DemoAuthRepository
          ? DemoReportPdfRepository()
          : FastApiReportPdfRepository(_apiClient));

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
                await _clearPrivateSessionData();
                if (context.mounted) context.go(PomiRoutes.login);
              }
            },
            patientNoteRepository: _patientNoteRepository,
            reportRepository: _reportRepository,
            reportPdfRepository: _reportPdfRepository,
            reportPdfCache:
                widget.reportPdfCache ??
                ReportPdfCache(accountScope: account.uid),
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
      if (!mounted) return;
      if (account == null) {
        await _clearPrivateSessionData();
        return;
      }
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
      restorationScopeId: 'pomi-app',
      debugShowCheckedModeBanner: false,
      theme: PomiTheme.light,
      routerConfig: _router,
    );
  }
}
