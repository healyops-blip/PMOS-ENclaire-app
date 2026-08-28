import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/order_reconciliation_repository.dart';
import 'package:pmos_enclaire/features/records/presentation/ocr_task_page.dart';

void main() {
  testWidgets(
    'requires per-drug confirmation then requires every reconciliation decision',
    (tester) async {
      final gateway = _Gateway(twoOrders: true);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: OcrPendingConfirmationPage(
              repository: gateway,
              task: _task,
              document: _document,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('medical-order-review-page')),
        findsOneWidget,
      );

      var submit = tester.widget<FilledButton>(
        find.byKey(const Key('confirm-all-medical-orders')),
      );
      expect(submit.onPressed, isNull);
      final confirm = find.byKey(const Key('confirm-medical-order-0'));
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pump();
      submit = tester.widget(
        find.byKey(const Key('confirm-all-medical-orders')),
      );
      expect(submit.onPressed, isNull);
      final secondConfirm = find.byKey(const Key('confirm-medical-order-1'));
      await tester.ensureVisible(secondConfirm);
      tester.widget<CheckboxListTile>(secondConfirm).onChanged!(true);
      await tester.pump();
      submit = tester.widget(
        find.byKey(const Key('confirm-all-medical-orders')),
      );
      expect(submit.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('confirm-all-medical-orders')));
      await tester.pumpAndSettle();

      expect(gateway.confirmCalls, 1);
      expect(
        find.byKey(const Key('medication-reconciliation-page')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('certification-entry-card')), findsOneWidget);
      var execute = tester.widget<FilledButton>(
        find.byKey(const Key('execute-reconciliation')),
      );
      expect(execute.onPressed, isNull);

      for (final item in gateway.reconciliation.items) {
        final dropdown = find.byKey(Key('reconciliation-decision-${item.id}'));
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('保持当前用药不变').last);
        await tester.pumpAndSettle();
      }
      execute = tester.widget(find.byKey(const Key('execute-reconciliation')));
      expect(execute.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('execute-reconciliation')));
      await tester.pumpAndSettle();
      expect(gateway.executeCalls, 1);
      expect(find.text('对账已完整执行'), findsOneWidget);
    },
  );

  testWidgets('keeps edited medical-order fields when submission fails', (
    tester,
  ) async {
    final gateway = _Gateway(failConfirm: true, fieldError: true);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OcrPendingConfirmationPage(repository: gateway, task: _task),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final drugField = find.widgetWithText(TextFormField, '药名 *');
    await tester.enterText(drugField, '盐酸二甲双胍');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-medical-order-0'));
    tester.widget<CheckboxListTile>(confirm).onChanged!(true);
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-all-medical-orders')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('medical-order-review-page')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medical-order-submit-error')), findsOneWidget);
    expect(find.text('开具日期不能晚于服务器业务日期'), findsOneWidget);
    expect(find.text('盐酸二甲双胍'), findsOneWidget);
  });
}

const _task = OcrTask(
  id: 'task-order',
  documentId: 'doc-order',
  documentRevisionId: 'rev-order',
  materialType: 'medical_order',
  status: OcrTaskStatus.pendingConfirmation,
  attemptNumber: 1,
  providerAttempts: 1,
);

final _document = MedicalDocument(
  id: 'doc-order',
  documentType: 'medical_order',
  originalFileName: 'order.png',
  mimeType: 'image/png',
  fileSizeBytes: 100,
  currentRevisionId: 'rev-order',
  uploadedAt: DateTime(2026),
);

class _Gateway implements OcrRepository, MedicalOrderGateway {
  _Gateway({
    this.failConfirm = false,
    this.fieldError = false,
    this.twoOrders = false,
  });
  final bool failConfirm;
  final bool fieldError;
  final bool twoOrders;
  int confirmCalls = 0;
  int executeCalls = 0;

  final reconciliation = MedicationReconciliationDraft(
    id: 'rec-1',
    status: 'draft',
    ruleVersion: 'pomi-med-reconcile-v1',
    items: [
      ReconciliationItem(
        id: 'item-adjusted',
        suggestion: 'adjusted',
        oldMedication: const {'drug_name': 'Metformin 500 mg'},
        newOrder: const {'drug_name': 'Metformin 850 mg'},
        matchBasis: const {'standard_drug_id': 'rxnorm:metformin'},
      ),
      ReconciliationItem(
        id: 'item-uncertain',
        suggestion: 'uncertain',
        oldMedication: const {'drug_name': 'Vitamin D3'},
        newOrder: null,
        matchBasis: const {'automatic_stop': false},
      ),
    ],
  );

  @override
  Future<void> confirmMedicalOrder(
    String taskId,
    String resultId,
    String expectedRevisionId,
    List<MedicalOrderDraft> items,
  ) async {
    confirmCalls += 1;
    if (failConfirm) {
      throw OrderReviewException(
        'server unavailable',
        fieldErrors: fieldError
            ? const {'items.0.prescribed_at': '开具日期不能晚于服务器业务日期'}
            : const {},
      );
    }
  }

  @override
  Future<MedicationReconciliationDraft> createReconciliation(
    String taskId,
  ) async => reconciliation;

  @override
  Future<MedicationReconciliationDraft> executeReconciliation(
    MedicationReconciliationDraft value,
  ) async {
    executeCalls += 1;
    return MedicationReconciliationDraft(
      id: value.id,
      status: 'executed',
      ruleVersion: value.ruleVersion,
      items: value.items,
    );
  }

  @override
  Future<OcrTaskResult> result(String taskId) async => OcrTaskResult(
    resultId: 'result-order',
    taskId: taskId,
    draft: {
      'prescribed_at': '2026-08-27',
      'orders': [
        {
          'source_text': 'Metformin 500 mg twice daily',
          'drug_name': 'Metformin',
          'specification': '500 mg',
          'dosage_value': 500,
          'dosage_unit': 'mg',
          'frequency': 'twice daily',
          'duration': '30 days',
          'route': 'oral',
          'instruction': 'after meals',
        },
        if (twoOrders)
          {
            'source_text': '优思明 1 tablet once daily',
            'drug_name': '优思明',
            'specification': '1 tablet',
            'dosage_value': 1,
            'dosage_unit': 'tablet',
            'frequency': 'once daily',
            'duration': '21 days',
            'route': 'oral',
            'instruction': '',
          },
      ],
    },
    fields: const [],
  );

  @override
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  }) async => _task;
  @override
  Future<OcrTask> get(String taskId) async => _task;
  @override
  Future<OcrTask> retry(String taskId) async => _task;

  @override
  Future<List<int>> sourceFile(OcrTask task) async => const [];

  @override
  Future<ClinicalConfirmationResult> confirmClinical({
    required OcrTask task,
    required String resultId,
    required Map<String, dynamic> confirmedData,
    required List<Map<String, dynamic>> fieldConfirmations,
  }) => throw UnimplementedError();

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
