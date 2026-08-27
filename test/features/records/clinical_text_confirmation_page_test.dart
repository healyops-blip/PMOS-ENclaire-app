import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/presentation/clinical_text_confirmation_page.dart';

void main() {
  testWidgets(
    'imaging confirmation highlights missing text and retains edits for retry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _ClinicalRepository(failFirst: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ClinicalTextConfirmationPage(
            repository: repository,
            task: _task('imaging_text_report'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('clinical-field-findings')),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('clinical-confirmation-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('关键原文不能为空'), findsWidgets);
      await tester.enterText(
        find.byKey(const Key('clinical-field-findings')),
        '用户核对后的所见原文',
      );
      await tester.enterText(
        find.byKey(const Key('clinical-field-impression')),
        '用户核对后的结论原文',
      );
      final confirm = find.byKey(const Key('confirm-clinical-text'));
      await tester.scrollUntilVisible(
        confirm,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('clinical-confirmation-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('模拟网络失败'), findsOneWidget);
      expect(find.text('用户核对后的所见原文'), findsOneWidget);

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('clinical-confirmation-success')),
        findsOneWidget,
      );
      expect(repository.confirmCalls, 2);
    },
  );

  testWidgets(
    'outpatient page blocks invalid date and never offers medication import',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _ClinicalRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ClinicalTextConfirmationPage(
            repository: repository,
            task: _task('outpatient_record'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('不会自动新增、调整或停用当前用药'), findsOneWidget);
      expect(find.textContaining('导入用药'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('clinical-field-visit_date')),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('clinical-confirmation-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(
        find.byKey(const Key('clinical-field-visit_date')),
        '2099-01-01',
      );
      final confirm = find.byKey(const Key('confirm-clinical-text'));
      await tester.scrollUntilVisible(
        confirm,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('clinical-confirmation-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(confirm);
      await tester.pump();
      expect(find.text('日期格式或范围不合理'), findsOneWidget);
      expect(repository.confirmCalls, 0);
    },
  );
}

OcrTask _task(String materialType) => OcrTask(
  id: 'task-$materialType',
  documentId: 'document-1',
  documentRevisionId: 'revision-1',
  materialType: materialType,
  status: OcrTaskStatus.pendingConfirmation,
  attemptNumber: 1,
  providerAttempts: 1,
);

class _ClinicalRepository implements OcrRepository {
  _ClinicalRepository({this.failFirst = false});
  final bool failFirst;
  int confirmCalls = 0;

  @override
  Future<OcrTaskResult> result(String taskId) async {
    final imaging = taskId.contains('imaging');
    return OcrTaskResult(
      taskId: taskId,
      draft: imaging
          ? const {
              'facility': '模拟医院',
              'examination_name': '盆腔超声',
              'body_part': '盆腔',
              'modality': '超声',
              'examination_date': '2026-08-20',
              'report_date': '2026-08-21',
              'findings': '',
              'impression': '',
            }
          : const {
              'facility': '模拟医院',
              'department': '内分泌科',
              'doctor_name': null,
              'visit_date': '2026-08-20',
              'chief_complaint': '月经不规律',
              'diagnosis_summary': 'PCOS 随访原文',
              'treatment_plan': '病历药物文字原文',
              'medical_advice': '三个月后复诊',
            },
      fields: const [
        OcrFieldDraft(
          path: 'findings',
          value: null,
          confidence: 0.4,
          uncertaintyReason: '文字模糊',
        ),
      ],
    );
  }

  @override
  Future<ClinicalConfirmationResult> confirmClinical({
    required OcrTask task,
    required String resultId,
    required Map<String, dynamic> confirmedData,
    required List<Map<String, dynamic>> fieldConfirmations,
  }) async {
    confirmCalls += 1;
    if (failFirst && confirmCalls == 1) {
      throw const OcrException('NETWORK_ERROR', '模拟网络失败');
    }
    return ClinicalConfirmationResult(
      recordId: 'record-1',
      materialType: task.id.contains('imaging')
          ? 'imaging_text_report'
          : 'outpatient_record',
      documentRevisionId: 'revision-1',
      summary: confirmedData,
      reused: false,
    );
  }

  @override
  Future<List<int>> sourceFile(OcrTask task) async => const [];

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
