import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/records/records_screen.dart';

void main() {
  testWidgets('glucose chart accepts a one-sided reference range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReportViewer(
            report: {
              'generated_at': '2026-08-29T08:30:00Z',
              'snapshot': {
                'summary': {
                  'profile': {
                    'nickname': '测试用户',
                    'birth_date': '1996-06-01',
                    'diagnosis_year': 2024,
                    'height_cm': 162,
                  },
                  'weight_summary': {'latest_weight_kg': 67.5},
                  'current_medications': <Map<String, dynamic>>[
                    {
                      'drug_name': '二甲双胍',
                      'source_type': 'medical_order',
                      'route': '口服',
                      'frequency': '每日 2 次',
                      'start_date': '2026-08-01',
                      'completion_percent': 75,
                      'taken_units': 45,
                      'planned_total_units': 60,
                    },
                    {
                      'drug_name': '叶酸',
                      'source_type': 'manual',
                      'route': '口服',
                      'frequency': '每日 1 次',
                      'start_date': '2026-08-20',
                    },
                  ],
                  'disclaimers': <String>[],
                },
                'trends': {
                  'weights': <Map<String, dynamic>>[],
                  'cycles': <Map<String, dynamic>>[],
                  'labs': [
                    {
                      'metric_id': 'glucose',
                      'metric_name': '空腹血糖',
                      'unit': 'mmol/L',
                      'points': [
                        {
                          'date': '2026-08-25',
                          'raw_value': '5.6',
                          'normalized_value': 5.6,
                          'normalized_unit': 'mmol/L',
                          'normalized_reference_lower': 3.9,
                          'normalized_reference_upper': null,
                          'abnormal_status': 'normal',
                          'comparability': 'comparable',
                          'source_number': 1,
                        },
                      ],
                    },
                  ],
                },
                'sources': <Map<String, dynamic>>[],
              },
            },
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('测试用户 · 30 岁 · 162 cm · 67.5 kg'), findsOneWidget);
    expect(find.text('本次关注'), findsOneWidget);
    expect(find.textContaining('当前无备孕计划'), findsOneWidget);
    expect(find.text('近期基础信息'), findsOneWidget);
    expect(find.text('近期关键指标'), findsOneWidget);
    expect(find.text('摘要'), findsOneWidget);
    expect(find.text('趋势'), findsOneWidget);
    expect(find.text('原始数据'), findsOneWidget);
    expect(find.text('医嘱用药'), findsOneWidget);
    expect(find.text('完成率 75%'), findsOneWidget);
    expect(find.text('患者自用'), findsOneWidget);
    expect(find.textContaining('已服用 10 天'), findsOneWidget);
    expect(find.text('空腹血糖（FPG）趋势'), findsNothing);

    await tester.tap(find.text('空腹血糖'));
    await tester.pumpAndSettle();

    expect(find.text('空腹血糖（FPG）趋势'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
