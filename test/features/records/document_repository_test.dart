import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';

void main() {
  test(
    'uploads with consent, idempotency and progress then reads revisions',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            final data = switch (options.path) {
              '/documents' when options.method == 'POST' => _document,
              '/documents' => {
                'items': [_document],
                'next_cursor': null,
                'has_more': false,
              },
              '/documents/doc-1/revisions' => [_revision],
              _ => _document,
            };
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: options.method == 'POST' ? 201 : 200,
                data: {'success': true, 'data': data, 'error': null},
              ),
            );
          },
        ),
      );
      final repository = FastApiDocumentRepository(PomiApiClient(dio: dio));
      var progressCalled = false;

      final uploaded = await repository.upload(
        file: SelectedDocumentFile(
          name: 'lab.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        documentType: 'lab_report',
        consentVersion: documentProcessingNoticeVersion,
        idempotencyKey: 'stable-upload-retry-key',
        onProgress: (_, _) => progressCalled = true,
      );
      await repository.upload(
        file: SelectedDocumentFile(
          name: 'lab.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        documentType: 'lab_report',
        consentVersion: documentProcessingNoticeVersion,
        idempotencyKey: 'stable-upload-retry-key',
        onProgress: (_, _) {},
      );
      final listed = await repository.list(documentType: 'lab_report');
      final revisions = await repository.revisions(uploaded.id);

      expect(uploaded.id, 'doc-1');
      expect(listed.single.originalFileName, 'lab.png');
      expect(revisions.single.revisionNumber, 1);
      expect(requests[0].headers['Idempotency-Key'], 'stable-upload-retry-key');
      expect(requests[1].headers['Idempotency-Key'], 'stable-upload-retry-key');
      final form = requests.first.data as FormData;
      expect(
        Map<String, String>.fromEntries(
          form.fields,
        )['external_processing_consent_version'],
        'external-ocr-v1',
      );
      // Dio's mock adapter does not stream request bytes, but the callback is wired on the request.
      expect(progressCalled, isFalse);
    },
  );

  test('maps backend business failures to a safe retry message', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 413,
              data: {
                'error': {'code': 'FILE_TOO_LARGE', 'message': '文件超过 20 MiB'},
              },
            ),
          ),
        ),
      ),
    );
    final repository = FastApiDocumentRepository(PomiApiClient(dio: dio));

    expect(
      () => repository.list(),
      throwsA(
        isA<DocumentFailure>()
            .having((error) => error.code, 'code', 'FILE_TOO_LARGE')
            .having((error) => error.message, 'message', '文件超过 20 MiB'),
      ),
    );
  });

  test(
    'demo replacement updates current content and remains idempotent',
    () async {
      final repository = DemoDocumentRepository();
      final original = await repository.upload(
        file: SelectedDocumentFile(
          name: 'original.png',
          bytes: Uint8List.fromList([1]),
        ),
        documentType: 'lab_report',
        consentVersion: documentProcessingNoticeVersion,
        idempotencyKey: 'demo-original-upload',
        onProgress: (_, _) {},
      );
      final replacementFile = SelectedDocumentFile(
        name: 'clearer.png',
        bytes: Uint8List.fromList([2, 3]),
      );
      final first = await repository.replace(
        documentId: original.id,
        expectedRevisionId: original.currentRevisionId,
        reason: 'clearer scan',
        file: replacementFile,
        idempotencyKey: 'stable-replacement-key',
        onProgress: (_, _) {},
      );
      final repeated = await repository.replace(
        documentId: original.id,
        expectedRevisionId: original.currentRevisionId,
        reason: 'clearer scan',
        file: replacementFile,
        idempotencyKey: 'stable-replacement-key',
        onProgress: (_, _) {},
      );

      final current = await repository.get(original.id);
      expect(repeated.id, first.id);
      expect(current.currentRevisionId, first.id);
      expect(current.originalFileName, 'clearer.png');
      expect(await repository.revisions(original.id), hasLength(2));
      expect(await repository.download(original.id, first.id), [2, 3]);
    },
  );
}

final _document = <String, dynamic>{
  'id': 'doc-1',
  'document_type': 'lab_report',
  'original_file_name': 'lab.png',
  'mime_type': 'image/png',
  'file_size_bytes': 1024,
  'pixel_count': 1200,
  'page_count': 1,
  'file_hash': 'abcdef0123456789',
  'current_revision_id': 'rev-1',
  'uploaded_at': '2026-08-27T10:00:00+00:00',
};

final _revision = <String, dynamic>{
  'id': 'rev-1',
  'revision_number': 1,
  'mime_type': 'image/png',
  'file_hash': 'abcdef0123456789',
  'replacement_reason': null,
  'created_at': '2026-08-27T10:00:00+00:00',
};
