import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/reports/data/report_pdf_repository.dart';

void main() {
  test(
    'queues, polls and downloads through authenticated report endpoints',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      final client = PomiApiClient(dio: dio)..useSession('opaque-session');
      final requests = <RequestOptions>[];
      var statusCalls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.path.endsWith('/file')) {
              handler.resolve(
                Response<List<int>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: '%PDF-1.7\nfixture\n%%EOF'.codeUnits,
                ),
              );
              return;
            }
            final status = options.method == 'POST'
                ? 'queued'
                : statusCalls++ == 0
                ? 'processing'
                : 'succeeded';
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: options.method == 'POST' ? 202 : 200,
                data: {
                  'success': true,
                  'data': {
                    'report_id': 'report-1',
                    'generation_status': status,
                    'template_version': 'report-pdf-v1',
                    'attempt_count': 1,
                    'file_id': status == 'succeeded' ? 'file-1' : null,
                    'file_name': status == 'succeeded'
                        ? 'pomi-report-report-1.pdf'
                        : null,
                  },
                },
              ),
            );
          },
        ),
      );
      final repository = FastApiReportPdfRepository(client);

      expect(
        (await repository.create('report-1')).status,
        ReportPdfGenerationStatus.queued,
      );
      expect(
        (await repository.getStatus('report-1')).status,
        ReportPdfGenerationStatus.processing,
      );
      final succeeded = await repository.getStatus('report-1');
      expect(succeeded.status, ReportPdfGenerationStatus.succeeded);
      expect(succeeded.templateVersion, 'report-pdf-v1');
      expect(succeeded.attemptCount, 1);
      final bytes = await repository.download('report-1');

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(requests.map((request) => request.path), [
        '/reports/report-1/pdf',
        '/reports/report-1/pdf',
        '/reports/report-1/pdf',
        '/reports/report-1/pdf/file',
      ]);
      expect(requests.first.headers['Idempotency-Key'], contains('report-1'));
      expect(
        requests.every(
          (request) =>
              request.headers['Authorization'] == 'Bearer opaque-session',
        ),
        isTrue,
      );
      expect(
        requests.last.headers['Accept'],
        'application/pdf',
        reason: 'the file endpoint remains an authenticated API request',
      );
    },
  );

  test('accepts the legacy pending status as queued', () {
    final job = ReportPdfJob.fromJson({
      'report_id': 'report-1',
      'generation_status': 'pending',
    });

    expect(job.status, ReportPdfGenerationStatus.queued);
  });

  test(
    'rejects a non-PDF response from the authenticated file endpoint',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              statusCode: 200,
              data: '<html>not a PDF</html>'.codeUnits,
            ),
          ),
        ),
      );
      final repository = FastApiReportPdfRepository(PomiApiClient(dio: dio));

      await expectLater(
        repository.download('report-1'),
        throwsA(
          isA<ReportPdfFailure>().having(
            (error) => error.message,
            'message',
            contains('不是有效的 PDF'),
          ),
        ),
      );
    },
  );

  test(
    'stores only safe private cache names and cleans old/excess files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pomi-pdf-cache-test-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final cache = ReportPdfCache(
        directoryProvider: () async => root,
        maxAge: const Duration(hours: 1),
        maxFiles: 2,
      );
      final bytes = Uint8List.fromList('%PDF-1.7\nfixture'.codeUnits);

      final first = await cache.store(
        reportId: 'report-1',
        bytes: bytes,
        suggestedName: '../../private clinical report.pdf',
      );
      expect(first.parent.parent.path, root.path);
      expect(first.path, isNot(contains('..')));
      await first.setLastModified(
        DateTime.now().subtract(const Duration(hours: 2)),
      );
      await cache.store(reportId: 'report-2', bytes: bytes);
      await cache.store(reportId: 'report-3', bytes: bytes);
      await cache.store(reportId: 'report-4', bytes: bytes);

      final files = await first.parent
          .list()
          .where((entity) => entity is File)
          .toList();
      expect(
        await first.exists(),
        isFalse,
        reason: 'files expire after the configured maxAge',
      );
      expect(files, hasLength(2));
      expect(files.any((file) => file.path.endsWith('.part')), isFalse);

      await cache.clear();
      expect(await first.parent.exists(), isFalse);
    },
  );
}
