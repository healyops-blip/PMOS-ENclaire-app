import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/certification/application/certification_providers.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';
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

  testWidgets('manual retry schedules polling only after request completes', (
    tester,
  ) async {
    final repository = _SequenceRepository([
      _task(OcrTaskStatus.pendingConfirmation),
    ]);
    repository.createValue = _task(
      OcrTaskStatus.failed,
      category: 'provider_unavailable',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OcrTaskPage(
          repository: repository,
          document: _document,
          pollInterval: Duration.zero,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('ocr-retry-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(repository.retryCalls, 1);
    expect(repository.getCalls, 1);
    expect(find.byKey(const Key('ocr-confirmation-entry')), findsOneWidget);
  });

  testWidgets('poll error preserves task and automatically retries', (
    tester,
  ) async {
    final repository = _SequenceRepository([
      const OcrException('NETWORK_ERROR', 'temporary poll failure'),
      _task(OcrTaskStatus.pendingConfirmation),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: OcrTaskPage(
          repository: repository,
          document: _document,
          pollInterval: const Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(find.text('temporary poll failure'), findsOneWidget);
    expect(find.byKey(const Key('ocr-polling-indicator')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(repository.getCalls, 2);
    expect(find.byKey(const Key('ocr-confirmation-entry')), findsOneWidget);
  });

  testWidgets(
    'confirmed task exposes certification only for the current revision',
    (tester) async {
      final repository = _SequenceRepository(const [])
        ..createValue = _task(OcrTaskStatus.confirmed);
      final local = MemoryCertificationRepository();

      Widget app(MedicalDocument document) => ProviderScope(
        overrides: [certificationRepositoryProvider.overrideWithValue(local)],
        child: MaterialApp(
          home: OcrTaskPage(
            repository: repository,
            document: document,
            documentRepository: _StaticDocumentRepository(document),
          ),
        ),
      );

      await tester.pumpWidget(app(_document));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('certification-entry-card')), findsOneWidget);

      await tester.pumpWidget(
        app(
          MedicalDocument(
            id: 'doc-1',
            documentType: 'lab_report',
            originalFileName: 'lab.png',
            mimeType: 'image/png',
            fileSizeBytes: 100,
            currentRevisionId: 'rev-2',
            uploadedAt: DateTime(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('certification-entry-card')), findsNothing);
    },
  );
}

OcrTask _task(OcrTaskStatus status, {String? category}) => OcrTask(
  id: 'task-1',
  documentId: 'doc-1',
  documentRevisionId: 'rev-1',
  materialType: 'lab_report',
  status: status,
  attemptNumber: 1,
  providerAttempts: 1,
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
  final List<Object> values;
  OcrTask? createValue;
  int getCalls = 0;
  int retryCalls = 0;

  @override
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  }) async => createValue ?? _task(OcrTaskStatus.queued);

  @override
  Future<OcrTask> get(String taskId) async {
    final value = values[getCalls++];
    if (value is OcrTask) return value;
    throw value;
  }

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
}

class _StaticDocumentRepository implements DocumentRepository {
  _StaticDocumentRepository(this.document);

  final MedicalDocument document;

  @override
  Future<MedicalDocument> get(String id) async => document;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
