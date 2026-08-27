import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/presentation/lab_confirmation_page.dart';

void main() {
  testWidgets(
    'highlights draft errors, preserves edits after failure, retries and summarizes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _LabRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: LabConfirmationPage(repository: repository, task: _task),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lab-source-document')), findsOneWidget);
      expect(find.textContaining('需重点核对'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('confirm-all-lab-items')),
      );
      await tester.tap(find.byKey(const Key('confirm-all-lab-items')));
      await tester.pump();
      expect(find.text('请输入可解析的数值'), findsOneWidget);
      expect(find.text('单位不在允许范围内'), findsOneWidget);
      expect(repository.confirmCalls, 0);

      await tester.enterText(find.byKey(const Key('lab-value-0')), '5.2');
      await tester.enterText(find.byKey(const Key('lab-unit-0')), 'mmol/L');
      await tester.tap(find.text('日期与备注（可留空）'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lab-sample_date-0')),
        '2026-08-18',
      );
      await tester.ensureVisible(
        find.byKey(const Key('confirm-all-lab-items')),
      );
      await tester.tap(find.byKey(const Key('confirm-all-lab-items')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-lab-dialog-action')));
      await tester.pumpAndSettle();

      expect(repository.confirmCalls, 1);
      expect(find.text('请核对参考范围'), findsOneWidget);
      expect(
        (tester
                .widget<TextField>(find.byKey(const Key('lab-value-0')))
                .controller)
            ?.text,
        '5.2',
      );

      await tester.enterText(
        find.byKey(const Key('lab-reference_range-0')),
        '3.9-6.1',
      );
      await tester.ensureVisible(
        find.byKey(const Key('confirm-all-lab-items')),
      );
      await tester.tap(find.byKey(const Key('confirm-all-lab-items')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-lab-dialog-action')));
      await tester.pumpAndSettle();

      expect(repository.confirmCalls, 2);
      expect(find.byKey(const Key('lab-confirmation-success')), findsOneWidget);
      expect(find.text('已确认 1 项正式数据'), findsOneWidget);
      expect(find.text('5.200000 mmol/L'), findsOneWidget);
    },
  );
}

const _task = OcrTask(
  id: 'task-1',
  documentId: 'doc-1',
  documentRevisionId: 'rev-1',
  materialType: 'lab_report',
  status: OcrTaskStatus.pendingConfirmation,
  attemptNumber: 1,
  providerAttempts: 1,
);

class _LabRepository implements OcrRepository {
  int confirmCalls = 0;

  @override
  Future<OcrTaskResult> result(String taskId) async => const OcrTaskResult(
    resultId: 'result-1',
    taskId: 'task-1',
    draft: {
      'report_date': '2026-08-20',
      'items': [
        {
          'name': '血糖',
          'value': 'bad',
          'unit': 'banana',
          'reference_range': '',
          'sample_date': 'bad-date',
        },
      ],
    },
    fields: [
      OcrFieldDraft(
        path: 'items.0.value',
        value: 'bad',
        confidence: 0.45,
        sourceText: 'S.2',
        uncertaintyReason: '字符模糊',
      ),
    ],
    sourceDocument: OcrSourceDocument(
      documentId: 'doc-1',
      revisionId: 'rev-1',
      fileName: 'lab.png',
      mimeType: 'image/png',
      revisionNumber: 1,
    ),
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
  }) async {
    confirmCalls += 1;
    if (confirmCalls == 1) {
      throw const OcrException(
        'LAB_CONFIRMATION_INVALID',
        '字段无效',
        fieldErrors: [
          OcrFieldError(
            path: 'items.0.reference_range',
            code: 'LAB_REFERENCE_RANGE_INVALID',
            message: '请核对参考范围',
          ),
        ],
      );
    }
    expect(items.single.value, '5.2');
    expect(items.single.referenceRange, '3.9-6.1');
    return LabConfirmationResult(
      taskId: taskId,
      reused: false,
      confirmedAt: DateTime(2026, 8, 27),
      observations: const [
        LabObservationSummary(
          id: 'lab-1',
          name: '血糖',
          value: '5.200000',
          unit: 'mmol/L',
          abnormalStatus: 'normal',
          mappingStatus: 'mapped',
          metricId: 'glucose',
        ),
      ],
    );
  }

  @override
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  }) => throw UnimplementedError();

  @override
  Future<OcrTask> get(String taskId) => throw UnimplementedError();

  @override
  Future<OcrTask> retry(String taskId) => throw UnimplementedError();
}
