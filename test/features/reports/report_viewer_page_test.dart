import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_repository.dart';
import 'package:pmos_enclaire/features/reports/presentation/report_viewer_page.dart';

void main() {
  testWidgets(
    'small screen covers summary, 1/2/3+ points, folding and every-point trace',
    (tester) async {
      _smallPhone(tester);
      final reports = DemoReportRepository();
      final report = await reports.create(null, confirmIncomplete: false);
      await tester.pumpWidget(
        _app(
          report,
          reports,
          _ImageDocumentRepository(),
          MemoryCertificationRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('report-page')), findsOneWidget);
      expect(find.text('患者自述原文'), findsOneWidget);
      expect(find.text('当前用药'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final glucose = find.byKey(const Key('report-summary-metric-glucose'));
      await tester.dragUntilVisible(
        glucose,
        find.byKey(const Key('report-summary-scroll')),
        const Offset(0, -180),
      );
      expect(find.text('最新检查指标'), findsOneWidget);
      await tester.tap(glucose);
      await tester.pumpAndSettle();
      expect(find.text('趋势线'), findsOneWidget);
      expect(find.byKey(const Key('expand-archived-points')), findsOneWidget);
      expect(find.byKey(const Key('report-point-source-1')), findsNothing);

      await tester.tap(find.byKey(const Key('expand-archived-points')));
      await tester.pumpAndSettle();
      final archived = find.byKey(const Key('report-point-source-1'));
      await tester.dragUntilVisible(
        archived,
        find.byKey(const Key('report-trend-scroll')),
        const Offset(0, -180),
      );
      expect(archived, findsOneWidget);

      final doubleMetric = find.byKey(const Key('report-metric-double'));
      await tester.dragUntilVisible(
        doubleMetric,
        find.byKey(const Key('report-trend-scroll')),
        const Offset(0, 180),
      );
      await tester.tap(doubleMetric);
      await tester.pumpAndSettle();
      expect(find.text('两次对比'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-metric-single')));
      await tester.pumpAndSettle();
      expect(find.text('单次结果'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('report-metric-selector')),
        const Offset(240, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-metric-glucose')));
      await tester.pumpAndSettle();
      final incomparable = find.byKey(const Key('report-point-source-4'));
      await tester.dragUntilVisible(
        incomparable,
        find.byKey(const Key('report-trend-scroll')),
        const Offset(0, -180),
      );
      await tester.drag(
        find.byKey(const Key('report-trend-scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(incomparable);
      await tester.pumpAndSettle();
      expect(find.text('来源 #4'), findsOneWidget);
      expect(find.text('不可比 · 独立散点'), findsOneWidget);
      expect(find.byKey(const Key('source-file-fallback')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('open-original-report')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source and original viewer preserve metric/version and show only local success watermark',
    (tester) async {
      _smallPhone(tester);
      final reports = _CountingReportRepository();
      final report = await reports.create(null, confirmIncomplete: false);
      final certification = MemoryCertificationRepository();
      await certification.write(
        CertificationRecord(
          documentId: 'demo-document-3',
          revisionId: 'demo-revision-3',
          status: CertificationStatus.succeeded,
          updatedAt: DateTime(2026, 8, 27),
        ),
      );
      await tester.pumpWidget(
        _app(report, reports, _ImageDocumentRepository(), certification),
      );
      await tester.pumpAndSettle();
      final glucose = find.byKey(const Key('report-summary-metric-glucose'));
      await tester.dragUntilVisible(
        glucose,
        find.byKey(const Key('report-summary-scroll')),
        const Offset(0, -180),
      );
      await tester.tap(glucose);
      await tester.pumpAndSettle();
      final point = find.byKey(const Key('report-point-source-3'));
      await tester.dragUntilVisible(
        point,
        find.byKey(const Key('report-trend-scroll')),
        const Offset(0, -180),
      );
      await tester.drag(
        find.byKey(const Key('report-trend-scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(point);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('local-certification-watermark')),
        findsOneWidget,
      );
      final openOriginal = find.byKey(const Key('open-original-report'));
      await tester.dragUntilVisible(
        openOriginal,
        find.byKey(const Key('report-source-scroll')),
        const Offset(0, -180),
      );
      await tester.drag(
        find.byKey(const Key('report-source-scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(openOriginal);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('original-file-viewer')), findsOneWidget);
      expect(
        find.byKey(const Key('fullscreen-local-watermark')),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-page')), findsOneWidget);
      expect(
        find.byKey(const Key('local-certification-watermark')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('report-layer-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-point-source-3')), findsOneWidget);
      expect(reports.requestedIds, [report.reportId]);
    },
  );

  testWidgets('manual points are never presented as hospital material', (
    tester,
  ) async {
    _smallPhone(tester);
    final reports = DemoReportRepository();
    final report = await reports.create(null, confirmIncomplete: false);
    await tester.pumpWidget(
      _app(
        report,
        reports,
        _ImageDocumentRepository(),
        MemoryCertificationRepository(),
      ),
    );
    await tester.pumpAndSettle();
    final glucose = find.byKey(const Key('report-summary-metric-glucose'));
    await tester.dragUntilVisible(
      glucose,
      find.byKey(const Key('report-summary-scroll')),
      const Offset(0, -180),
    );
    await tester.tap(glucose);
    await tester.pumpAndSettle();
    final weightSection = find.byKey(const Key('weight-trend-row'));
    await tester.dragUntilVisible(
      weightSection,
      find.byKey(const Key('report-trend-scroll')),
      const Offset(0, -180),
    );
    await tester.drag(
      find.byKey(const Key('report-trend-scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trace-weight-source-1')));
    await tester.pumpAndSettle();
    expect(find.text('患者手工记录'), findsWidgets);
    expect(find.text('患者手工记录没有医院原始文件。'), findsOneWidget);
    expect(
      find.byKey(const Key('local-certification-watermark')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed original file keeps frozen structured source visible', (
    tester,
  ) async {
    _smallPhone(tester);
    final reports = DemoReportRepository();
    final report = await reports.create(null, confirmIncomplete: false);
    await tester.pumpWidget(
      _app(
        report,
        reports,
        _FailingDocumentRepository(),
        MemoryCertificationRepository(),
      ),
    );
    await tester.pumpAndSettle();
    final glucose = find.byKey(const Key('report-summary-metric-glucose'));
    await tester.dragUntilVisible(
      glucose,
      find.byKey(const Key('report-summary-scroll')),
      const Offset(0, -180),
    );
    await tester.tap(glucose);
    await tester.pumpAndSettle();
    final point = find.byKey(const Key('report-point-source-3'));
    await tester.dragUntilVisible(
      point,
      find.byKey(const Key('report-trend-scroll')),
      const Offset(0, -180),
    );
    await tester.drag(
      find.byKey(const Key('report-trend-scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(point);
    await tester.pumpAndSettle();
    expect(find.text('6.3 mmol/L'), findsWidgets);
    expect(
      find.byKey(const Key('local-certification-watermark')),
      findsNothing,
    );
    final openOriginal = find.byKey(const Key('open-original-report'));
    await tester.dragUntilVisible(
      openOriginal,
      find.byKey(const Key('report-source-scroll')),
      const Offset(0, -180),
    );
    await tester.drag(
      find.byKey(const Key('report-source-scroll')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(openOriginal);
    await tester.pumpAndSettle();
    expect(find.text('原始文件打开失败'), findsOneWidget);
    expect(find.textContaining('来源 #3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  ReportSnapshotItem report,
  ReportRepository reports,
  DocumentRepository documents,
  CertificationRepository certification,
) => MaterialApp(
  restorationScopeId: 'report-test',
  home: ReportViewerPage(
    report: report,
    repository: reports,
    documentRepository: documents,
    certificationRepository: certification,
  ),
);

void _smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _ImageDocumentRepository extends DemoDocumentRepository {
  @override
  Future<Uint8List> download(String documentId, String revisionId) async =>
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
}

class _FailingDocumentRepository extends DemoDocumentRepository {
  @override
  Future<Uint8List> download(String documentId, String revisionId) {
    throw const DocumentFailure('SOURCE_FILE_UNAVAILABLE', '文件服务暂时不可用');
  }
}

class _CountingReportRepository extends DemoReportRepository {
  final List<String> requestedIds = [];

  @override
  Future<ReportDetail> get(String reportId) {
    requestedIds.add(reportId);
    return super.get(reportId);
  }
}
