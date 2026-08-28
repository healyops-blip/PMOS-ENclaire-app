import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_repository.dart';
import 'package:pmos_enclaire/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/dashboard/presentation/dashboard_page.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

void main() {
  testWidgets('shows offline timestamp, partial failure, and disables writes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: PomiTheme.light,
        home: DashboardPage(
          account: DemoAccount.existingUser,
          profileRepository: DemoPatientProfileRepository(),
          patientNoteRepository: DemoPatientNoteRepository(),
          documentRepository: DemoDocumentRepository(),
          weightRepository: MemoryWeightRepository(),
          dashboardRepository: _OfflineRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-offline-banner')), findsOneWidget);
    expect(find.textContaining('离线数据，更新于'), findsOneWidget);
    expect(find.text('复诊安排暂不可用'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('0'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(
      find.byKey(const Key('dashboard-section-error-复诊安排')),
      findsOneWidget,
    );
    expect(find.text('暂无复诊报告 · 准备复诊材料'), findsOneWidget);

    final status = find.byKey(const Key('medication-status-0'));
    await tester.ensureVisible(status);
    await tester.tap(status);
    await tester.pump();
    expect(find.text('离线状态仅支持查看，联网后才能修改用药'), findsOneWidget);
    final manage = find.text('用药管理 ›');
    await tester.ensureVisible(manage);
    final manageButton = tester.widget<TextButton>(
      find.ancestor(of: manage, matching: find.byType(TextButton)),
    );
    expect(manageButton.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pumpAndSettle();
    final addCycle = tester.widget<FilledButton>(
      find.byKey(const Key('add-cycle-button')),
    );
    expect(addCycle.onPressed, isNull);
    final record = tester.widget<FilledButton>(
      find.byKey(const Key('record-weight-button')),
    );
    expect(record.onPressed, isNull);
  });

  testWidgets(
    'failed refresh keeps prior data, marks it stale, and offers retry',
    (tester) async {
      final repository = _RefreshFailureRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: PomiTheme.light,
          home: DashboardPage(
            account: DemoAccount.existingUser,
            profileRepository: DemoPatientProfileRepository(),
            patientNoteRepository: DemoPatientNoteRepository(),
            documentRepository: DemoDocumentRepository(),
            weightRepository: MemoryWeightRepository(),
            dashboardRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('数据日期 2026-08-27'), findsOneWidget);

      repository.fail = true;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-stale-error')), findsOneWidget);
      expect(find.text('刷新失败，当前为上次数据'), findsOneWidget);
      expect(find.text('重试'), findsWidgets);
    },
  );

  testWidgets('shows latest successful report metadata without report body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: PomiTheme.light,
        home: DashboardPage(
          account: DemoAccount.existingUser,
          profileRepository: DemoPatientProfileRepository(),
          patientNoteRepository: DemoPatientNoteRepository(),
          documentRepository: DemoDocumentRepository(),
          weightRepository: MemoryWeightRepository(),
          dashboardRepository: _LatestReportRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-report-latest')), findsOneWidget);
    expect(find.textContaining('最新报告已生成'), findsOneWidget);
    expect(find.text('进入复诊报告'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);
    expect(find.textContaining('private report body'), findsNothing);
  });

  testWidgets('returning from medication history refreshes Dashboard totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dashboardRepository = _DashboardReloadRepository();
    final medicationRepository = DemoMedicationRepository(const [
      _medication,
    ], () => DateTime(2026, 8, 27));
    await tester.pumpWidget(
      MaterialApp(
        theme: PomiTheme.light,
        home: DashboardPage(
          account: DemoAccount.existingUser,
          profileRepository: DemoPatientProfileRepository(),
          patientNoteRepository: DemoPatientNoteRepository(),
          documentRepository: DemoDocumentRepository(),
          weightRepository: MemoryWeightRepository(),
          dashboardRepository: dashboardRepository,
          medicationRepository: medicationRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(dashboardRepository.calls, 1);

    final manage = find.text('用药管理 ›');
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication-page')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(dashboardRepository.calls, 2);
  });
}

class _DashboardReloadRepository implements DashboardRepository {
  int calls = 0;

  @override
  Future<void> clear(String uid) async {}

  @override
  Future<DashboardLoad> load(String uid) async {
    calls += 1;
    return DashboardLoad(
      snapshot: DashboardSnapshot(
        businessDate: DateTime(2026, 8, 27),
        followUp: const DashboardSection(status: DashboardSectionStatus.empty),
        todayMedications: const DashboardSection(
          status: DashboardSectionStatus.ok,
          data: [_medication],
        ),
        monthSummary: DashboardSection(
          status: DashboardSectionStatus.ok,
          data: MedicationMonthSummary(taken: calls, missed: 0, unrecorded: 1),
        ),
        latestReport: const DashboardSection(
          status: DashboardSectionStatus.empty,
        ),
      ),
      offline: false,
      updatedAt: DateTime(2026, 8, 27, 12),
    );
  }
}

class _LatestReportRepository implements DashboardRepository {
  @override
  Future<void> clear(String uid) async {}

  @override
  Future<DashboardLoad> load(String uid) async {
    final json = Map<String, dynamic>.from(_dashboardJson)
      ..['latest_report'] = {
        'status': 'ok',
        'data': {
          'report_id': 'report-1',
          'status': 'succeeded',
          'generated_at': '2026-08-27T10:00:00+00:00',
          'snapshot_hash': List.filled(64, 'd').join(),
        },
        'error': null,
      };
    return DashboardLoad(
      snapshot: DashboardSnapshot.fromJson(json),
      offline: false,
      updatedAt: DateTime(2026, 8, 27, 12),
    );
  }
}

class _RefreshFailureRepository implements DashboardRepository {
  bool fail = false;

  @override
  Future<void> clear(String uid) async {}

  @override
  Future<DashboardLoad> load(String uid) async {
    if (fail) throw StateError('network unavailable');
    return DashboardLoad(
      snapshot: DashboardSnapshot.fromJson(_dashboardJson),
      offline: false,
      updatedAt: DateTime(2026, 8, 27, 12),
    );
  }
}

class _OfflineRepository implements DashboardRepository {
  @override
  Future<void> clear(String uid) async {}

  @override
  Future<DashboardLoad> load(String uid) async {
    return DashboardLoad(
      snapshot: DashboardSnapshot(
        businessDate: DateTime(2026, 8, 27),
        followUp: const DashboardSection(
          status: DashboardSectionStatus.error,
          errorCode: 'FOLLOW_UP_UNAVAILABLE',
        ),
        todayMedications: const DashboardSection(
          status: DashboardSectionStatus.ok,
          data: [
            Medication(
              id: 'medication-1',
              name: '二甲双胍',
              dose: '500 mg · 每日',
              group: '多囊用药',
              status: MedicationStatus.unrecorded,
              takenDays: 0,
              missedDays: 0,
            ),
          ],
        ),
        monthSummary: const DashboardSection(
          status: DashboardSectionStatus.ok,
          data: MedicationMonthSummary(taken: 1, missed: 0, unrecorded: 2),
        ),
        latestReport: const DashboardSection(
          status: DashboardSectionStatus.empty,
        ),
      ),
      offline: true,
      updatedAt: DateTime(2026, 8, 27, 9, 30),
    );
  }
}

const _dashboardJson = <String, dynamic>{
  'business_date': '2026-08-27',
  'follow_up': {'status': 'empty', 'data': null, 'error': null},
  'today_medications': {'status': 'empty', 'data': <dynamic>[], 'error': null},
  'monthly_medication_summary': {
    'status': 'ok',
    'data': {'taken': 1, 'missed': 0, 'unrecorded': 2},
    'error': null,
  },
  'latest_report': {'status': 'empty', 'data': null, 'error': null},
};

const _medication = Medication(
  id: 'medication-1',
  name: 'Metformin',
  dose: '500 mg',
  group: '按医嘱用药',
  status: MedicationStatus.unrecorded,
  takenDays: 0,
  missedDays: 0,
);
