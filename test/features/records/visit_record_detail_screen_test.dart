import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/core/theme.dart';
import 'package:pmos_enclaire/features/records/records_screen.dart';
import 'package:pmos_enclaire/features/records/visit_record_detail_screen.dart';

// 1x1 透明 PNG。
final _pngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB1, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _OriginalFileApiClient extends ApiClient {
  _OriginalFileApiClient() : super(const FlutterSecureStorage());

  @override
  Future<List<int>> download(String path) async => _pngBytes;
}

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
    await tester.pumpWidget(
      app(const VisitRecordsPage(visitsOverride: smokeVisitRecordDetails)),
    );

    for (final visit in smokeVisitRecordDetails) {
      expect(find.byKey(ValueKey('visit-record-${visit.id}')), findsOneWidget);
      expect(
        find.byKey(ValueKey('visit-hospital-${visit.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('visit-department-${visit.id}')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('visit-doctor-${visit.id}')), findsOneWidget);
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
    expect(stamp.width, 132);
    final stampPosition = tester.widget<Positioned>(
      find.byKey(const ValueKey('pomi-verified-stamp-position')),
    );
    expect(stampPosition.right, -4);
    expect(stampPosition.top, 0);
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
    expect(valueAxis.first, greaterThan(200));

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

  testWidgets(
    'a record with a document shows the original + blockchain watermark',
    (tester) async {
      usePhoneViewport(tester);
      const visit = VisitRecordDetailData(
        id: 'doc-1',
        documentId: 'doc-1',
        revisionId: 'rev-1',
        mimeType: 'image/png',
        date: '2026-08-27',
        hospital: '天津清和医院',
        department: '门诊',
        doctor: '孙医生',
        verificationState: VisitVerificationState.unverified,
        verificationLabel: '待核验',
        verificationTitle: '门诊病历 · 已上传',
        verificationDetail: 'MR00020.jpg',
        summaryItems: [
          VisitRecordSummaryItem(
            title: '门诊病历',
            category: VisitRecordCategory.outpatient,
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(_OriginalFileApiClient()),
          ],
          child: MaterialApp(
            theme: buildPomiTheme(),
            home: const VisitRecordDetailScreen(visit: visit),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('原件存证'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('blockchain-cert-watermark')),
        findsWidgets,
      );
      expect(find.text('区块链存证'), findsWidgets);
      expect(find.byType(Image), findsWidgets);
    },
  );

  testWidgets('a Smoke record (no document) hides the original card', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildPomiTheme(),
          home: VisitRecordDetailScreen(visit: smokeVisitRecordDetails.first),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('原件存证'), findsNothing);
  });

  testWidgets('every Smoke visit displays the green verification stamp', (
    tester,
  ) async {
    usePhoneViewport(tester);
    for (final visit in smokeVisitRecordDetails) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPomiTheme(),
          home: VisitRecordDetailScreen(visit: visit),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pomi-verified-stamp')),
        findsOneWidget,
        reason: '${visit.id} should show the green verification stamp',
      );
    }
  });
}
