import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/certification/application/certification_flow_controller.dart';
import 'package:pmos_enclaire/features/certification/application/certification_providers.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';
import 'package:pmos_enclaire/features/certification/presentation/certification_page.dart';

void main() {
  testWidgets('all four confirmed material types expose the local entry', (
    tester,
  ) async {
    final repository = MemoryCertificationRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const Column(
          children: [
            CertificationEntryCard(
              documentId: 'lab-document',
              revisionId: 'lab-revision',
              materialLabel: '化验报告',
              ocrConfirmed: true,
            ),
            CertificationEntryCard(
              documentId: 'order-document',
              revisionId: 'order-revision',
              materialLabel: '医嘱／处方',
              ocrConfirmed: true,
            ),
            CertificationEntryCard(
              documentId: 'imaging-document',
              revisionId: 'imaging-revision',
              materialLabel: '影像文字报告',
              ocrConfirmed: true,
            ),
            CertificationEntryCard(
              documentId: 'outpatient-document',
              revisionId: 'outpatient-revision',
              materialLabel: '门诊病历／就诊记录',
              ocrConfirmed: true,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('certification-entry-card')), findsNWidgets(4));
  });

  testWidgets('entry is available only for a confirmed current revision', (
    tester,
  ) async {
    final repository = MemoryCertificationRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const Column(
          children: [
            CertificationEntryCard(
              documentId: 'document-1',
              revisionId: 'revision-1',
              materialLabel: '化验报告',
              ocrConfirmed: false,
            ),
            CertificationEntryCard(
              documentId: 'document-2',
              revisionId: '',
              materialLabel: '医嘱／处方',
              ocrConfirmed: true,
            ),
            CertificationEntryCard(
              documentId: 'document-3',
              revisionId: 'revision-3',
              materialLabel: '门诊病历',
              ocrConfirmed: true,
              currentRevisionAvailable: false,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('certification-entry-card')), findsNothing);
  });

  testWidgets('golden path shows watermark only after local success', (
    tester,
  ) async {
    final repository = MemoryCertificationRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const CertificationPage(
          documentId: 'document-1',
          revisionId: 'revision-1',
          materialLabel: '影像文字报告',
          transitionDuration: Duration(milliseconds: 20),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('不代表真实认证'), findsOneWidget);
    expect(find.textContaining('真实区块链'), findsWidgets);
    expect(
      find.byKey(const Key('simulate-certification-failure')),
      findsNothing,
    );
    expect(find.textContaining('交易哈希'), findsNothing);
    expect(find.textContaining('医生签名'), findsNothing);
    expect(find.textContaining('医院公章'), findsNothing);
    expect(find.byKey(const Key('certification-watermark')), findsNothing);

    await tester.tap(find.byKey(const Key('advance-certification-button')));
    await tester.pump();
    expect(find.text('认证演示处理中…'), findsOneWidget);
    expect(find.byKey(const Key('certification-watermark')), findsNothing);

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    expect(find.text('本地演示成功'), findsOneWidget);
    expect(find.byKey(const Key('certification-watermark')), findsOneWidget);
    expect(
      (await repository.read('document-1', 'revision-1')).status,
      CertificationStatus.succeeded,
    );
  });

  testWidgets('returning to material detail refreshes the revision watermark', (
    tester,
  ) async {
    final repository = MemoryCertificationRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const CertificationEntryCard(
          documentId: 'document-1',
          revisionId: 'revision-1',
          materialLabel: '化验报告',
          ocrConfirmed: true,
          transitionDuration: Duration(milliseconds: 20),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('certification-entry-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('advance-certification-button')));
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('finish-certification-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-certification-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('certification-page')), findsNothing);
    expect(find.byKey(const Key('certification-watermark')), findsOneWidget);
    expect(find.text('本地认证演示已完成'), findsOneWidget);
  });

  testWidgets('controlled failure has no watermark and retry succeeds', (
    tester,
  ) async {
    final repository = MemoryCertificationRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const CertificationPage(
          documentId: 'document-1',
          revisionId: 'revision-1',
          materialLabel: '门诊病历',
          transitionDuration: Duration(milliseconds: 20),
          demoPlan: CertificationDemoPlan(failFirstAttempt: true),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('advance-certification-button')));
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    expect(find.text('本地演示失败'), findsOneWidget);
    expect(find.byKey(const Key('certification-watermark')), findsNothing);

    await tester.tap(find.byKey(const Key('advance-certification-button')));
    await tester.pump();
    expect(find.text('认证演示处理中…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    expect(find.text('本地演示成功'), findsOneWidget);
    expect(find.byKey(const Key('certification-watermark')), findsOneWidget);
  });

  testWidgets('new revision does not inherit an old revision watermark', (
    tester,
  ) async {
    final repository = MemoryCertificationRepository();
    await repository.write(
      CertificationRecord(
        documentId: 'document-1',
        revisionId: 'revision-old',
        status: CertificationStatus.succeeded,
      ),
    );
    await tester.pumpWidget(
      _app(
        repository,
        const CertificationEntryCard(
          documentId: 'document-1',
          revisionId: 'revision-new',
          materialLabel: '化验报告',
          ocrConfirmed: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('医院认证 · 本地演示'), findsOneWidget);
    expect(find.byKey(const Key('certification-watermark')), findsNothing);
  });
}

Widget _app(CertificationRepository repository, Widget child) => ProviderScope(
  overrides: [certificationRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: PomiTheme.light,
    home: child is CertificationPage
        ? child
        : Scaffold(body: SingleChildScrollView(child: child)),
  ),
);
