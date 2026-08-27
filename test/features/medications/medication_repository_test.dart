import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/application/medication_status_controller.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';

void main() {
  test('uses the server business date for reads and daily writes', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    final requests = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.path == '/medications') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'server_date': '2026-08-28',
                    'items': [_medication],
                    'groups': const {
                      'prescribed': [],
                      'supplement': [],
                      'other_long_term': [],
                    },
                    'next_cursor': null,
                    'has_more': false,
                  },
                  'request_id': 'req_test',
                  'error': null,
                },
              ),
            );
          } else if (options.path == '/medication-daily') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'items': const [],
                    'from': '2026-08-01',
                    'to': '2026-08-28',
                    'taken_count': 0,
                    'missed_count': 0,
                    'unrecorded_count': 28,
                  },
                  'request_id': 'req_test',
                  'error': null,
                },
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': const {
                    'id': 'daily-1',
                    'medication_id': 'medication-1',
                    'record_date': '2026-08-28',
                    'intake_status': 'taken',
                    'recorded_at': '2026-08-28T01:00:00Z',
                  },
                  'request_id': 'req_test',
                  'error': null,
                },
              ),
            );
          }
        },
      ),
    );
    final repository = FastApiMedicationRepository(PomiApiClient(dio: dio));
    final medications = await repository.listMedications();
    final controller = MedicationStatusController(
      gateway: repository,
      medications: medications,
    );

    await controller.setStatus(0, MedicationStatus.taken);

    final dailyRead = requests.singleWhere(
      (request) => request.path == '/medication-daily',
    );
    expect(dailyRead.queryParameters['from'], '2026-08-01');
    expect(dailyRead.queryParameters['to'], '2026-08-28');
    final dailyWrite = requests.singleWhere(
      (request) => request.path.endsWith('/daily-status'),
    );
    expect(dailyWrite.data['record_date'], '2026-08-28');
    expect(controller.medications.single.status, MedicationStatus.taken);
  });

  test(
    'history window is derived from the server date, not the device clock',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      RequestOptions? historyRequest;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/medications') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'success': true,
                    'data': {'server_date': '2026-01-02', 'items': const []},
                  },
                ),
              );
              return;
            }
            historyRequest = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'from': '2025-12-04',
                    'to': '2026-01-02',
                    'business_date': '2026-01-02',
                    'editable_from': '2025-12-27',
                    'taken_count': 0,
                    'missed_count': 0,
                    'unrecorded_count': 0,
                    'items': const [],
                  },
                },
              ),
            );
          },
        ),
      );
      final repository = FastApiMedicationRepository(PomiApiClient(dio: dio));

      final history = await repository.listDailyHistory('medication-1');

      expect(historyRequest!.queryParameters['from'], '2025-12-04');
      expect(historyRequest!.queryParameters['to'], '2026-01-02');
      expect(history.businessDate, DateTime(2026, 1, 2));
      expect(history.editableFrom, DateTime(2025, 12, 27));
    },
  );
}

const _medication = <String, dynamic>{
  'id': 'medication-1',
  'patient_id': 'patient-1',
  'drug_name': 'Metformin',
  'dosage_value': 500,
  'dosage_unit': 'mg',
  'frequency': 'once daily',
  'status': 'active',
  'source_category': 'prescribed',
  'start_date': '2026-08-01',
  'end_date': null,
  'replaces_medication_id': null,
  'created_at': '2026-08-01T00:00:00Z',
  'updated_at': '2026-08-01T00:00:00Z',
};
