import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_repository.dart';
import 'package:pmos_enclaire/features/reports/presentation/report_page.dart';

void main() {
  test('uses preflight and idempotent report snapshot contracts', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    final requests = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final dynamic data;
          if (options.path == '/reports/preflight') {
            data = {
              'missing_sections': ['labs'],
              'can_generate': false,
              'confirmed_source_count': 4,
            };
          } else if (options.method == 'GET' && options.path == '/reports') {
            data = {
              'items': [_report],
              'next_cursor': null,
              'has_more': false,
            };
          } else if (options.method == 'GET') {
            data = _reportDetail;
          } else {
            data = _report;
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {'success': true, 'data': data},
            ),
          );
        },
      ),
    );
    final repository = FastApiReportRepository(PomiApiClient(dio: dio));

    final preflight = await repository.preflight('note-1');
    final created = await repository.create('note-1', confirmIncomplete: true);
    final listed = await repository.list();
    final detail = await repository.get('report-1');

    expect(preflight.missingSections, ['labs']);
    expect(created.reportId, 'report-1');
    expect(listed.single.snapshotHash, 'a' * 64);
    expect(detail.item.reportId, 'report-1');
    expect(requests.map((request) => request.path), [
      '/reports/preflight',
      '/reports',
      '/reports',
      '/reports/report-1',
    ]);
    expect((requests[1].data as Map)['confirm_incomplete'], isTrue);
    expect(requests[1].headers['Idempotency-Key'], contains('note-1'));
  });

  testWidgets('confirms missing sections before opening an immutable report', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ReportGeneratorPage(
          repository: DemoPatientNoteRepository(),
          reportRepository: DemoReportRepository(
            missingSections: const ['labs', 'imaging'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final generate = find.byKey(const Key('generate-report-button'));
    await tester.drag(
      find.byKey(const Key('report-generator-scroll')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('资料尚不完整'), findsOneWidget);
    expect(find.textContaining('labs、imaging'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-incomplete-report')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('report-page')), findsOneWidget);
  });

  testWidgets(
    'retains the confirmed statement and retries a failed generation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reports = _FlakyReportRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ReportGeneratorPage(
            repository: DemoPatientNoteRepository(),
            reportRepository: reports,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = (tester.widget<TextField>(
        find.byKey(const Key('patient-note-field')),
      )).controller!.text;
      final generate = find.byKey(const Key('generate-report-button'));
      await tester.drag(
        find.byKey(const Key('report-generator-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      await tester.tap(generate);
      await tester.pumpAndSettle();
      expect(find.text('temporary generation failure'), findsOneWidget);
      expect(
        (tester.widget<TextField>(find.byKey(const Key('patient-note-field'))))
            .controller!
            .text,
        original,
      );

      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('report-page')), findsOneWidget);
      expect(reports.attempts, 2);
    },
  );
}

class _FlakyReportRepository implements ReportRepository {
  int attempts = 0;

  @override
  Future<ReportSnapshotItem> create(
    String? patientNoteId, {
    required bool confirmIncomplete,
  }) async {
    attempts += 1;
    if (attempts == 1) {
      throw const ReportFailure('temporary generation failure');
    }
    return ReportSnapshotItem.fromJson(_report);
  }

  @override
  Future<List<ReportSnapshotItem>> list() async => const [];

  @override
  Future<ReportDetail> get(String reportId) async =>
      ReportDetail.fromJson(_reportDetail);

  @override
  Future<ReportPreflight> preflight(String? patientNoteId) async =>
      const ReportPreflight(
        missingSections: [],
        canGenerate: true,
        confirmedSourceCount: 1,
      );
}

const _report = <String, dynamic>{
  'report_id': 'report-1',
  'status': 'succeeded',
  'generated_at': '2026-08-27T12:00:00Z',
  'snapshot_hash':
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'source_digest':
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'previous_report_id': null,
  'has_updates': false,
  'reused': false,
  'missing_sections': ['labs'],
  'snapshot': {
    'summary': {
      'patient_note_text': 'Confirmed statement returned verbatim.',
      'patient_note_empty_state': null,
      'current_medications': <dynamic>[],
      'latest_observations': <dynamic>[],
      'missing_sections': ['labs'],
      'disclaimers': ['Deterministic confirmed data only.'],
    },
    'trends': {
      'weights': <dynamic>[],
      'cycles': <dynamic>[],
      'medication_daily': <dynamic>[],
      'labs': <dynamic>[],
    },
    'sources': <dynamic>[],
  },
  'date_sources': <String, dynamic>{},
  'data_freshness': <String, dynamic>{},
};

final _reportDetail = <String, dynamic>{..._report, ..._demoDetailForTest};

const _demoDetailForTest = <String, dynamic>{
  'metadata': <String, dynamic>{},
  'summary': <String, dynamic>{
    'profile': <String, dynamic>{},
    'current_medications': <dynamic>[],
    'latest_observations': <dynamic>[],
    'missing_sections': <String>[],
    'disclaimers': <String>[],
  },
  'trends': <String, dynamic>{
    'labs': <dynamic>[],
    'weights': <dynamic>[],
    'cycles': <dynamic>[],
    'medication_daily': <dynamic>[],
  },
  'records': <String, dynamic>{},
  'sources': <dynamic>[],
  'data_freshness': <String, dynamic>{},
};
