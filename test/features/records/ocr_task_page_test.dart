import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/presentation/ocr_task_page.dart';

void main() {
  testWidgets(
    'polling pauses in background, resumes, then opens confirmation',
    (tester) async {
      final repository = _SequenceRepository([
        _task(OcrTaskStatus.processing),
        _task(OcrTaskStatus.pendingConfirmation),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: OcrTaskPage(
            repository: repository,
            document: _document,
            pollInterval: const Duration(milliseconds: 100),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('ocr-polling-indicator')), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.getCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repository.getCalls, 1);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byKey(const Key('ocr-confirmation-entry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ocr-confirmation-entry')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('ocr-confirmation-lab_report')),
        findsOneWidget,
      );
    },
  );

  testWidgets('failed task exposes an idempotent manual retry action', (
    tester,
  ) async {
    final repository = _SequenceRepository(const []);
    repository.createValue = _task(
      OcrTaskStatus.failed,
      category: 'provider_unavailable',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OcrTaskPage(repository: repository, document: _document),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('ocr-retry-button')), findsOneWidget);
    expect(find.textContaining('暂时不可用'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-retry-button')));
    await tester.pump();
    expect(repository.retryCalls, 1);
  });

  testWidgets(
    'exact demo fallback requires an explicit choice and stays marked',
    (tester) async {
      final repository = _SequenceRepository(const [])
        ..createValue = _task(
          OcrTaskStatus.failed,
          category: 'provider_unavailable',
        )
        ..fallbackValue = const OcrFallbackEligibility(
          eligible: true,
          reason: 'exact_match',
          dataVersion: 'pomi-demo-fallback-v1',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: OcrTaskPage(repository: repository, document: _document),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ocr-fallback-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ocr-fallback-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-ocr-fallback')));
      await tester.pumpAndSettle();
      expect(repository.fallbackChoices, [false]);
      expect(find.byKey(const Key('ocr-retry-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ocr-fallback-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept-ocr-fallback')));
      await tester.pumpAndSettle();
      expect(repository.fallbackChoices, [false, true]);
      expect(find.byKey(const Key('ocr-fallback-badge')), findsOneWidget);
      expect(find.byKey(const Key('ocr-confirmation-entry')), findsOneWidget);
    },
  );
}

OcrTask _task(
  OcrTaskStatus status, {
  String? category,
  bool fallback = false,
}) => OcrTask(
  id: 'task-1',
  documentId: 'doc-1',
  documentRevisionId: 'rev-1',
  materialType: 'lab_report',
  status: status,
  attemptNumber: 1,
  providerAttempts: 1,
  resultSource: fallback ? 'fallback' : null,
  fallback: fallback
      ? const OcrFallbackAudit(
          dataVersion: 'pomi-demo-fallback-v1',
          triggerCategory: 'provider_unavailable',
          triggerCode: 'OCR_UNAVAILABLE',
        )
      : null,
  error: category == null
      ? null
      : OcrTaskFailure(
          category: category,
          code: 'OCR_UNAVAILABLE',
          message: 'safe',
        ),
);

final _document = MedicalDocument(
  id: 'doc-1',
  documentType: 'lab_report',
  originalFileName: 'lab.png',
  mimeType: 'image/png',
  fileSizeBytes: 100,
  currentRevisionId: 'rev-1',
  uploadedAt: DateTime(2026),
);

class _SequenceRepository implements OcrRepository {
  _SequenceRepository(this.values);
  final List<OcrTask> values;
  OcrTask? createValue;
  int getCalls = 0;
  int retryCalls = 0;
  OcrFallbackEligibility fallbackValue = const OcrFallbackEligibility(
    eligible: false,
    reason: 'file_not_registered',
  );
  final List<bool> fallbackChoices = [];

  @override
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  }) async => createValue ?? _task(OcrTaskStatus.queued);

  @override
  Future<OcrTask> get(String taskId) async => values[getCalls++];

  @override
  Future<OcrTaskResult> result(String taskId) async => OcrTaskResult(
    resultId: 'result-1',
    taskId: taskId,
    draft: const {'items': []},
    fields: const [
      OcrFieldDraft(path: 'facility', value: 'Pomi', confidence: 0.9),
    ],
  );

  @override
  Future<OcrTask> retry(String taskId) async {
    retryCalls += 1;
    return _task(OcrTaskStatus.queued);
  }

  @override
  Future<OcrFallbackEligibility> fallbackEligibility(String taskId) async =>
      fallbackValue;

  @override
  Future<OcrTask> useFallback(
    String taskId, {
    required bool accept,
    required String dataVersion,
  }) async {
    fallbackChoices.add(accept);
    return accept
        ? _task(OcrTaskStatus.pendingConfirmation, fallback: true)
        : _task(OcrTaskStatus.failed, category: 'provider_unavailable');
  }

  @override
  Future<LabConfirmationResult> confirmLab({
    required String taskId,
    required String resultId,
    required String expectedRevisionId,
    required List<LabConfirmationItem> items,
    String? sampleDate,
    String? examDate,
    String? reportDate,
    String? visitDate,
  }) => throw UnimplementedError();

  @override
  Future<List<int>> sourceFile(OcrTask task) async => const [];

  @override
  Future<ClinicalConfirmationResult> confirmClinical({
    required OcrTask task,
    required String resultId,
    required Map<String, dynamic> confirmedData,
    required List<Map<String, dynamic>> fieldConfirmations,
  }) async => ClinicalConfirmationResult(
    recordId: 'record-1',
    materialType: task.materialType,
    documentRevisionId: task.documentRevisionId,
    summary: confirmedData,
    reused: false,
  );
}
