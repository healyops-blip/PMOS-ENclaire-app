import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/reports/data/report_pdf_repository.dart';
import 'package:pmos_enclaire/features/reports/presentation/report_pdf_panel.dart';

void main() {
  late Directory temporaryDirectory;
  late File cachedFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pomi-report-page-test-',
    );
    cachedFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}cached.pdf',
    )..writeAsBytesSync('%PDF-1.7\nfixture\n%%EOF'.codeUnits);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('polls queued and processing then shares the cached PDF', (
    tester,
  ) async {
    final repository = _ScriptedPdfRepository();
    final actions = _RecordingActions();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(
                child: SizedBox(
                  key: ValueKey('report-summary'),
                  child: Text('immutable report'),
                ),
              ),
              ReportPdfPanel(
                reportId: 'report-1',
                repository: repository,
                cache: _TestCache(cachedFile),
                systemActions: actions,
                pollingInterval: Duration.zero,
                maxPolls: 4,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('report-pdf-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享 PDF'));
    await _pumpUntil(tester, () => actions.shared.isNotEmpty);

    expect(repository.statusCalls, 2);
    expect(repository.downloadCalls, 1);
    expect(actions.shared, hasLength(1));
    expect(actions.shared.single.existsSync(), isTrue);
    expect(find.text('已打开 Android 系统分享面板'), findsWidgets);
    expect(find.byKey(const ValueKey('report-summary')), findsOneWidget);
    expect(find.byKey(const Key('retry-report-pdf')), findsNothing);
  });

  testWidgets(
    'shows a clear generation failure and retries without losing report',
    (tester) async {
      final repository = _ScriptedPdfRepository(failFirst: true);
      final actions = _RecordingActions();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(
                  child: SizedBox(
                    key: ValueKey('report-summary'),
                    child: Text('immutable report'),
                  ),
                ),
                ReportPdfPanel(
                  reportId: 'report-1',
                  repository: repository,
                  cache: _TestCache(cachedFile),
                  systemActions: actions,
                  pollingInterval: Duration.zero,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('report-pdf-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打印 PDF'));
      await tester.pumpAndSettle();

      final statusCard = find.byKey(const Key('report-pdf-status'));
      expect(
        find.descendant(
          of: statusCard,
          matching: find.textContaining('服务器渲染暂时失败'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: statusCard,
          matching: find.textContaining('App 内报告和服务器文件不受影响'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('report-summary')), findsOneWidget);

      await tester.tap(find.byKey(const Key('retry-report-pdf')));
      await _pumpUntil(tester, () => actions.printed.isNotEmpty);
      await tester.pumpAndSettle();

      expect(repository.createCalls, 2);
      expect(actions.printed, hasLength(1));
      expect(find.text('已打开 Android 系统打印预览'), findsWidgets);
      expect(find.byKey(const ValueKey('report-summary')), findsOneWidget);
    },
  );

  testWidgets(
    'retries a system share failure without replacing the App report',
    (tester) async {
      final repository = _ScriptedPdfRepository();
      final actions = _RecordingActions(failFirstShare: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(
                  child: SizedBox(
                    key: ValueKey('report-summary'),
                    child: Text('immutable report'),
                  ),
                ),
                ReportPdfPanel(
                  reportId: 'report-1',
                  repository: repository,
                  cache: _TestCache(cachedFile),
                  systemActions: actions,
                  pollingInterval: Duration.zero,
                  maxPolls: 4,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('report-pdf-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享 PDF'));
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('retry-report-pdf')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('系统分享面板暂时不可用'), findsWidgets);
      expect(find.byKey(const ValueKey('report-summary')), findsOneWidget);

      await tester.tap(find.byKey(const Key('retry-report-pdf')));
      await _pumpUntil(tester, () => actions.shared.isNotEmpty);

      expect(actions.shareAttempts, 2);
      expect(actions.shared, hasLength(1));
      expect(find.byKey(const ValueKey('report-summary')), findsOneWidget);
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (predicate()) {
      await tester.pump(const Duration(milliseconds: 220));
      return;
    }
  }
  fail('asynchronous PDF action did not finish');
}

class _TestCache extends ReportPdfCache {
  _TestCache(this.file) : super(directoryProvider: () async => file.parent);

  final File file;

  @override
  Future<void> cleanup({Directory? directory}) async {}

  @override
  Future<File> store({
    required String reportId,
    required Uint8List bytes,
    String? suggestedName,
  }) async => file;
}

class _ScriptedPdfRepository implements ReportPdfRepository {
  _ScriptedPdfRepository({this.failFirst = false});

  final bool failFirst;
  int createCalls = 0;
  int statusCalls = 0;
  int downloadCalls = 0;

  @override
  Future<ReportPdfJob> create(String reportId) async {
    createCalls += 1;
    if (failFirst && createCalls == 1) {
      return ReportPdfJob(
        reportId: reportId,
        status: ReportPdfGenerationStatus.failed,
        failureReason: '服务器渲染暂时失败',
      );
    }
    if (failFirst) return _succeeded(reportId);
    return ReportPdfJob(
      reportId: reportId,
      status: ReportPdfGenerationStatus.queued,
    );
  }

  @override
  Future<Uint8List> download(String reportId) async {
    downloadCalls += 1;
    return Uint8List.fromList('%PDF-1.7\nfixture\n%%EOF'.codeUnits);
  }

  @override
  Future<ReportPdfJob> getStatus(String reportId) async {
    statusCalls += 1;
    if (statusCalls == 1) {
      return ReportPdfJob(
        reportId: reportId,
        status: ReportPdfGenerationStatus.processing,
      );
    }
    return _succeeded(reportId);
  }

  ReportPdfJob _succeeded(String reportId) => ReportPdfJob(
    reportId: reportId,
    status: ReportPdfGenerationStatus.succeeded,
    fileId: 'file-1',
    fileName: 'pomi-report-report-1.pdf',
  );
}

class _RecordingActions implements ReportPdfSystemActions {
  _RecordingActions({this.failFirstShare = false});

  final bool failFirstShare;
  final List<File> saved = [];
  final List<File> shared = [];
  final List<File> printed = [];
  int shareAttempts = 0;

  @override
  Future<void> print(File file, String fileName) async => printed.add(file);

  @override
  Future<void> save(File file, String fileName) async => saved.add(file);

  @override
  Future<void> share(File file, String fileName) async {
    shareAttempts += 1;
    if (failFirstShare && shareAttempts == 1) {
      throw const ReportPdfFailure('系统分享面板暂时不可用');
    }
    shared.add(file);
  }
}
