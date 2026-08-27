import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_repository.dart';
import 'package:pmos_enclaire/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/dashboard/presentation/dashboard_page.dart';

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
          dashboardRepository: _OfflineRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-offline-banner')), findsOneWidget);
    expect(find.textContaining('离线数据，更新于'), findsOneWidget);
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

    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pumpAndSettle();
    final record = tester.widget<FilledButton>(
      find.byKey(const Key('record-weight-button')),
    );
    expect(record.onPressed, isNull);
  });
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
