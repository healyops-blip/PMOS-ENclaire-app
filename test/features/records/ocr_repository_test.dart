import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/data/order_reconciliation_repository.dart';

void main() {
  test(
    'creates, polls, reads protected result and retries through API',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            final payload = options.path.endsWith('/result')
                ? _result
                : options.path.endsWith('/confirm')
                ? _confirmation
                : {
                    ..._task,
                    'status': options.path.endsWith('/retry')
                        ? 'queued'
                        : 'processing',
                  };
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: options.method == 'POST' ? 201 : 200,
                data: {'success': true, 'data': payload, 'error': null},
              ),
            );
          },
        ),
      );
      final repository = FastApiOcrRepository(PomiApiClient(dio: dio));

      final created = await repository.create(
        documentId: 'doc-1',
        revisionId: 'rev-1',
      );
      final polled = await repository.get(created.id);
      final result = await repository.result(created.id);
      final retried = await repository.retry(created.id);
      final confirmed = await repository.confirmLab(
        taskId: created.id,
        resultId: 'result-1',
        expectedRevisionId: 'rev-1',
        items: const [
          LabConfirmationItem(
            sourceIndex: 0,
            name: '血糖',
            value: '5.2',
            unit: 'mmol/L',
          ),
        ],
      );

      expect(created.status, OcrTaskStatus.processing);
      expect(polled.providerAttempts, 1);
      expect(result.fields.single.sourceRegion?['page'], 1);
      expect(retried.status, OcrTaskStatus.queued);
      expect(confirmed.observations.single.name, '血糖');
      expect(requests.first.data, {
        'document_id': 'doc-1',
        'document_revision_id': 'rev-1',
      });
      expect(requests.map((item) => item.path), [
        '/ocr/tasks',
        '/ocr/tasks/task-1',
        '/ocr/tasks/task-1/result',
        '/ocr/tasks/task-1/retry',
        '/ocr/tasks/task-1/confirm',
      ]);
      expect((requests.last.data as Map)['items'], [
        {
          'source_index': 0,
          'name': '血糖',
          'value': '5.2',
          'unit': 'mmol/L',
          'reference_range': null,
          'sample_date': null,
          'exam_date': null,
          'report_date': null,
          'visit_date': null,
          'note': null,
        },
      ]);
    },
  );

  test('maps each worker error category to a distinct safe message', () {
    const categories = [
      'file',
      'network',
      'timeout',
      'provider_unavailable',
      'response_format',
      'unknown',
    ];
    final messages = categories
        .map(
          (category) => OcrTaskFailure(
            category: category,
            code: 'SAFE_CODE',
            message: 'internal-safe-message',
          ).userMessage,
        )
        .toSet();
    expect(messages, hasLength(categories.length));
  });

  test(
    'confirms each order item then creates and executes reconciliation',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            final payload = options.path.contains('medication-reconciliations')
                ? {
                    ..._reconciliation,
                    'status': options.method == 'PUT' ? 'executed' : 'draft',
                  }
                : {'items': <Object>[], 'reused': false};
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: options.method == 'POST' ? 201 : 200,
                data: {'success': true, 'data': payload, 'error': null},
              ),
            );
          },
        ),
      );
      final repository = FastApiOcrRepository(PomiApiClient(dio: dio));
      final item = MedicalOrderDraft(
        index: 0,
        drugName: 'Metformin',
        specification: '500 mg',
        dosageValue: '500',
        dosageUnit: 'mg',
        frequency: 'twice daily',
        course: '30 days',
        route: 'oral',
        instructions: 'after meals',
        rawOrderText: 'Metformin 500 mg twice daily',
        orderDate: '2026-08-27',
        confirmed: true,
      );

      await repository.confirmMedicalOrder(
        'task-order',
        'result-order',
        'rev-order',
        [item],
      );
      final reconciliation = await repository.createReconciliation(
        'task-order',
      );
      reconciliation.items.single.decision = 'keep_current';
      final executed = await repository.executeReconciliation(reconciliation);

      expect(executed.status, 'executed');
      expect(requests.map((request) => request.path), [
        '/ocr/tasks/task-order/confirm',
        '/medication-reconciliations',
        '/medication-reconciliations/rec-1',
      ]);
      expect((requests.first.data as Map)['result_id'], 'result-order');
      expect((requests.first.data as Map)['expected_revision_id'], 'rev-order');
      expect((requests.first.data as Map)['items'][0]['confirmed'], isTrue);
      expect(
        (requests.last.data as Map)['decisions'][0]['decision'],
        'keep_current',
      );
    },
  );

  test(
    'clinical confirmation pins result and revision with idempotency',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      RequestOptions? request;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'record_id': 'imaging-1',
                    'material_type': 'imaging_text_report',
                    'document_revision_id': 'rev-1',
                    'summary': {'findings_text': 'verbatim'},
                    'reused': false,
                  },
                },
              ),
            );
          },
        ),
      );
      final repository = FastApiOcrRepository(PomiApiClient(dio: dio));
      final task = OcrTask.fromJson({
        ..._task,
        'material_type': 'imaging_text_report',
      });

      final result = await repository.confirmClinical(
        task: task,
        resultId: 'result-1',
        confirmedData: {'findings_text': 'verbatim'},
        fieldConfirmations: const [
          {
            'field_path': 'findings_text',
            'user_value': 'verbatim',
            'confirmation_status': 'confirmed',
          },
        ],
      );

      expect(result.recordId, 'imaging-1');
      expect(request!.path, '/ocr/tasks/task-1/confirm');
      expect(request!.headers['Idempotency-Key'], isNull);
      expect(request!.data['result_id'], 'result-1');
      expect(request!.data['expected_revision_id'], 'rev-1');
      expect(request!.data['document_type'], 'imaging_text_report');
    },
  );
}

final _task = <String, dynamic>{
  'id': 'task-1',
  'document_id': 'doc-1',
  'document_revision_id': 'rev-1',
  'material_type': 'lab_report',
  'status': 'queued',
  'attempt_number': 1,
  'provider_attempts': 1,
  'parent_task_id': null,
  'error': null,
};

final _result = <String, dynamic>{
  'id': 'result-1',
  'task_id': 'task-1',
  'validated_draft': {'items': []},
  'fields': [
    {
      'path': 'facility',
      'parsed_value': 'Pomi Hospital',
      'confidence': 0.9,
      'source_text': 'Pomi Hospital',
      'uncertainty_reason': null,
      'source_region': {'page': 1},
    },
  ],
};

final _reconciliation = <String, dynamic>{
  'id': 'rec-1',
  'ocr_task_id': 'task-order',
  'rule_version': 'pomi-med-reconcile-v1',
  'items': [
    {
      'id': 'item-1',
      'position': 0,
      'old_medication': {'drug_name': 'Metformin'},
      'new_medical_order': {'drug_name': 'Metformin'},
      'match_basis': {'standard_drug_id': 'rxnorm:metformin'},
      'suggestion': 'unchanged',
      'user_decision': null,
    },
  ],
};

final _confirmation = <String, dynamic>{
  'task_id': 'task-1',
  'result_id': 'result-1',
  'status': 'confirmed',
  'reused': false,
  'confirmed_at': '2026-08-27T12:00:00Z',
  'created_resource_ids': ['lab-1'],
  'observations': [
    {
      'id': 'lab-1',
      'original_item_name': '血糖',
      'numeric_value': '5.200000',
      'standard_unit': 'mmol/L',
      'abnormal_status': 'normal',
      'mapping_status': 'mapped',
      'standard_metric_id': 'glucose',
      'trend_date': null,
    },
  ],
};
