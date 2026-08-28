import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/theme.dart';
import 'package:pmos_enclaire/features/records/records_screen.dart';
import 'package:pmos_enclaire/features/records/visit_record_detail_screen.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: buildPomiTheme(),
    home: PomiAppBackground(child: Scaffold(body: child)),
  );

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('each Smoke visit has an independent detail payload', () {
    expect(smokeVisitRecordDetails, hasLength(5));
    expect(
      smokeVisitRecordDetails.map((visit) => visit.id).toSet(),
      hasLength(5),
    );
    expect(
      smokeVisitRecordDetails.every((visit) => visit.summaryItems.isNotEmpty),
      isTrue,
    );
  });

  testWidgets('opens the latest visit and presents clinical detail states', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(app(const VisitRecordsPage()));

    for (final visit in smokeVisitRecordDetails) {
      expect(find.byKey(ValueKey('visit-record-${visit.id}')), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('visit-record-visit-20260826')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/pomi_verified_stamp.png'),
        tester.element(find.byType(VisitRecordDetailScreen)),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('visit-record-detail-screen')),
      findsOneWidget,
    );
    expect(find.text('模拟医院 B'), findsOneWidget);
    expect(find.text('就诊记录快照 · 上传后版本'), findsOneWidget);
    expect(find.byKey(const ValueKey('pomi-verified-stamp')), findsOneWidget);
    final stamp = tester.widget<Image>(
      find.byKey(const ValueKey('pomi-verified-stamp')),
    );
    expect(stamp.width, 112);
    expect(
      find.byKey(const ValueKey('pomi-verified-stamp-rotation')),
      findsOneWidget,
    );
    expect(find.text('材料存证'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('总睾酮'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('0.9'), findsOneWidget);
    final highReference = tester.widget<Text>(
      find.byKey(const ValueKey('lab-reference-总睾酮')),
    );
    expect(highReference.data, '参考 0.1–0.75 ng/mL');
    expect(highReference.style?.color, const Color(0xFFD24A54));
    expect(find.text('高于参考范围'), findsNothing);
    final valueAxis = ['空腹血糖', 'HbA1c', '总睾酮', '甘油三酯'].map(
      (name) => tester.getTopLeft(find.byKey(ValueKey('lab-value-$name'))).dx,
    );
    expect(valueAxis.toSet(), hasLength(1));

    await tester.scrollUntilVisible(
      find.text('医嘱与处方'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byIcon(Icons.medication_outlined), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('维生素 D3'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('待确认'), findsOneWidget);
    expect(find.byIcon(Icons.medication_rounded), findsNothing);
  });

  testWidgets('historical visit keeps the age warning and low result label', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPomiTheme(),
        home: VisitRecordDetailScreen(visit: smokeVisitRecordDetails.last),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('此数据超过 6 个月'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('维生素 D'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('18.6'), findsOneWidget);
    final lowReference = tester.widget<Text>(
      find.byKey(const ValueKey('lab-reference-维生素 D')),
    );
    expect(lowReference.data, '参考 ≥ 20 ng/mL');
    expect(lowReference.style?.color, const Color(0xFFC77A16));
    expect(find.text('低于参考范围'), findsNothing);
  });
}
