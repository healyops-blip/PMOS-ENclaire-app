import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/core/theme.dart';
import 'package:pmos_enclaire/features/dashboard/dashboard_screen.dart';
import 'package:pmos_enclaire/features/profile/profile_screen.dart';
import 'package:pmos_enclaire/features/records/records_screen.dart';
import 'package:pmos_enclaire/features/tracking/tracking_screen.dart';
import 'package:pmos_enclaire/features/upload/upload_screen.dart';

import 'support/fake_api_client.dart';

void main() {
  Widget app(Widget child) => MaterialApp(theme: buildPomiTheme(), home: child);

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('normal records mode renders API documents instead of demos', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordsProvider.overrideWith(
            (ref) async => {
              'documents': {
                'items': [
                  {
                    'id': 'document-1',
                    'document_type': 'lab_report',
                    'original_file_name': '真实化验单.pdf',
                    'latest_ocr_status': 'confirmed',
                  },
                ],
              },
              'reports': {'items': <Map<String, dynamic>>[]},
            },
          ),
        ],
        child: app(const RecordsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实化验单.pdf'), findsOneWidget);
    expect(find.text('模拟数据'), findsNothing);
    expect(find.textContaining('模拟医院'), findsNothing);
  });

  testWidgets('normal dashboard hides the fixed Smoke visit preview', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardProvider.overrideWith(
            (ref) async => {
              'profile': <String, dynamic>{},
              'medications': <Map<String, dynamic>>[],
              'documents': <String, dynamic>{},
            },
          ),
        ],
        child: app(
          DashboardScreen(
            onOpenTab: (_) {},
            onOpenRecords: ({bool reports = false}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('激素六项化验单'), findsNothing);
    expect(find.textContaining('仁和医院'), findsNothing);
  });

  testWidgets('normal medication management uses API items and empty states', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          medicationsProvider.overrideWith(
            (ref) async => [
              {
                'id': 'medication-active',
                'drug_name': '真实当前用药',
                'current_status': 'active',
              },
              {
                'id': 'medication-stopped',
                'drug_name': '真实历史用药',
                'current_status': 'stopped',
                'start_date': '2026-01-01',
                'end_date': '2026-02-01',
              },
            ],
          ),
        ],
        child: app(const MedicationManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实当前用药'), findsOneWidget);
    expect(find.text('真实历史用药'), findsOneWidget);
    expect(find.text('当前用药'), findsOneWidget);
    expect(find.text('每日提醒'), findsNothing);
    expect(find.text('本月状态'), findsNothing);
    expect(find.textContaining('优思明'), findsNothing);
  });

  testWidgets('normal tracking shows an empty state without fake weights', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingProvider.overrideWith(
            (ref) async => {
              'cycles': <Map<String, dynamic>>[],
              'weights': <Map<String, dynamic>>[],
            },
          ),
        ],
        child: app(const TrackingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无体重记录'), findsOneWidget);
    expect(find.text('69.8'), findsNothing);
  });

  testWidgets('tapping a past calendar day opens cycle entry for that day', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final yesterday = DateUtils.dateOnly(
      DateTime.now(),
    ).subtract(const Duration(days: 1));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingProvider.overrideWith(
            (ref) async => {
              'cycles': <Map<String, dynamic>>[],
              'weights': <Map<String, dynamic>>[],
            },
          ),
        ],
        child: app(const TrackingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('${yesterday.day}').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('收起经期记录'), findsOneWidget);
    expect(find.text('开始日期'), findsOneWidget);
    expect(find.text('${yesterday.month}月${yesterday.day}日'), findsOneWidget);
  });

  testWidgets('today weight can be saved without a future-date warning', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final api = FakeApiClient(handler: (_) => <String, dynamic>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          trackingProvider.overrideWith(
            (ref) async => {
              'cycles': <Map<String, dynamic>>[],
              'weights': <Map<String, dynamic>>[],
            },
          ),
        ],
        child: app(const TrackingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看体重历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录体重'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '66.5');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('只能记录今天及之前的体重'), findsNothing);
    final call = api.calls.singleWhere((item) => item.path == '/api/weights');
    expect(call.method, 'POST');
    expect(
      (call.data as Map)['record_date'],
      DateUtils.dateOnly(DateTime.now()).toIso8601String().substring(0, 10),
    );
    expect((call.data as Map)['weight_kg'], 66.5);
  });

  testWidgets('normal profile does not label a real account as simulated', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            (ref) async => {
              'nickname': '真实用户',
              'birth_year': null,
              'diagnosis_year': null,
            },
          ),
        ],
        child: app(const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实用户'), findsOneWidget);
    expect(find.text('模拟患者'), findsNothing);
  });

  testWidgets('upload flow keeps the OCR recognition action', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(app(const UploadScreen()));

    expect(find.widgetWithText(FilledButton, '开始识别'), findsOneWidget);
  });
}
