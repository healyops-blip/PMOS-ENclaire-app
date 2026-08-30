import 'dart:typed_data';

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
              'documents': [
                {
                  'id': 'document-1',
                  'document_type': 'lab_report',
                  'original_file_name': '真实化验单.pdf',
                  'latest_ocr_status': 'confirmed',
                  'hospital': '真实三甲医院',
                },
              ],
              // 化验项与文档同属一个 recordsProvider payload：确认入库后
              // 二者必须一起刷新，卡片才不会显示「0 项结果」。
              'labs': [
                {
                  'document_id': 'document-1',
                  'original_item_name': '空腹血糖',
                  'raw_value': '5.2',
                  'standard_unit': 'mmol/L',
                  'reference_range_raw': '3.9-6.1',
                  'abnormal_status': 'normal',
                  'report_date': '2026-08-20',
                },
              ],
              'reports': {'items': <Map<String, dynamic>>[]},
            },
          ),
        ],
        child: app(const RecordsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实化验单.pdf'), findsOneWidget);
    expect(find.text('1 项结果'), findsOneWidget);
    expect(find.text('模拟数据'), findsNothing);
    expect(find.textContaining('模拟医院'), findsNothing);
  });

  testWidgets('certified original overlays hospital watermark', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      app(
        OriginalFileScreen(
          bytes: Uint8List.fromList(const [
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
            0x00,
            0x00,
            0x00,
            0x0D,
            0x49,
            0x48,
            0x44,
            0x52,
            0x00,
            0x00,
            0x00,
            0x01,
            0x00,
            0x00,
            0x00,
            0x01,
            0x08,
            0x06,
            0x00,
            0x00,
            0x00,
            0x1F,
            0x15,
            0xC4,
            0x89,
            0x00,
            0x00,
            0x00,
            0x0D,
            0x49,
            0x44,
            0x41,
            0x54,
            0x78,
            0x9C,
            0x63,
            0xF8,
            0xCF,
            0xC0,
            0x00,
            0x00,
            0x03,
            0x01,
            0x01,
            0x00,
            0x18,
            0xDD,
            0x8D,
            0xB1,
            0x00,
            0x00,
            0x00,
            0x00,
            0x49,
            0x45,
            0x4E,
            0x44,
            0xAE,
            0x42,
            0x60,
            0x82,
          ]),
          mimeType: 'image/jpeg',
          fileName: '原件.jpg',
          certified: true,
          hospitalName: '示例医院',
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('hospital-certification-watermark')),
      findsOneWidget,
    );
    expect(find.text('医院认证'), findsOneWidget);
    expect(find.text('示例医院'), findsOneWidget);
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
          // 正式版和 Smoke 现在同一套 UI；本月状态由真实 medication-daily 聚合。
          monthlyMedicationStatusProvider.overrideWith(
            (ref) async => {
              'medication-active': (taken: 3, missed: 1, unrecorded: 0),
            },
          ),
        ],
        child: app(const MedicationManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('真实当前用药'), findsWidgets);
    expect(find.text('真实历史用药'), findsOneWidget);
    expect(find.text('用药提醒'), findsOneWidget);
    expect(find.text('本月状态'), findsOneWidget);
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

  testWidgets('tapping a day inside an existing cycle opens it for editing', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final today = DateUtils.dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: 3));
    final end = today.subtract(const Duration(days: 1));
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingProvider.overrideWith(
            (ref) async => {
              'cycles': [
                {
                  'id': 'cycle-1',
                  'start_date': iso(start),
                  'end_date': iso(end),
                  // 后端可能返回 'unknown'，分段按钮不能接受，不应崩溃。
                  'flow_level': 'unknown',
                  'updated_at': '2026-08-20T00:00:00Z',
                },
              ],
              'weights': <Map<String, dynamic>>[],
            },
          ),
        ],
        child: app(const TrackingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('${end.day}').first);
    await tester.pumpAndSettle();

    expect(find.text('更新经期记录'), findsOneWidget);
    expect(find.text('删除这条记录'), findsOneWidget);
    expect(find.text('${start.month}月${start.day}日'), findsOneWidget);
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
