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
              'snapshot': {
                'summary': {
                  'profile': {'nickname': '测试用户'},
                  'weight_summary': {'latest_weight_kg': 67.5},
                  'current_medications': <Map<String, dynamic>>[],
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
    expect(find.text('体重 67.5 kg'), findsOneWidget);
    expect(find.text('近期基础信息'), findsOneWidget);
    expect(find.text('近期关键指标'), findsOneWidget);
    expect(find.text('1  摘要'), findsOneWidget);
    expect(find.text('2  趋势'), findsOneWidget);
    expect(find.text('3  原始数据'), findsOneWidget);
    expect(find.text('空腹血糖（FPG）趋势'), findsNothing);

    await tester.tap(find.text('空腹血糖'));
    await tester.pumpAndSettle();

    expect(find.text('空腹血糖（FPG）趋势'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
