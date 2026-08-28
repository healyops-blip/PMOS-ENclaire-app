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
    expect(find.text('材料存证'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('总睾酮'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('0.9'), findsOneWidget);
    expect(find.text('高于参考范围'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('维生素 D3'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('待确认'), findsOneWidget);
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
    expect(find.text('低于参考范围'), findsOneWidget);
  });
}
