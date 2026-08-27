import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';

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

      expect(created.status, OcrTaskStatus.processing);
      expect(polled.providerAttempts, 1);
      expect(result.fields.single.sourceRegion?['page'], 1);
      expect(retried.status, OcrTaskStatus.queued);
      expect(requests.first.data, {
        'document_id': 'doc-1',
        'document_revision_id': 'rev-1',
      });
      expect(requests.map((item) => item.path), [
        '/ocr/tasks',
        '/ocr/tasks/task-1',
        '/ocr/tasks/task-1/result',
        '/ocr/tasks/task-1/retry',
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
                    'summary': {'findings': 'verbatim'},
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
        confirmedData: {'findings': 'verbatim'},
        fieldConfirmations: const [
          {
            'field_path': 'findings',
            'user_value': 'verbatim',
            'confirmation_status': 'confirmed',
          },
        ],
      );

      expect(result.recordId, 'imaging-1');
      expect(request!.path, '/ocr/tasks/task-1/confirm');
      expect(
        request!.headers['Idempotency-Key'],
        startsWith('flutter-confirm-'),
      );
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
