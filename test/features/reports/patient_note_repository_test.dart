import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';

void main() {
  test(
    'keeps statement text verbatim across save, confirm, skip and copy calls',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            final status = options.path.endsWith('/confirm')
                ? 'confirmed'
                : options.path.endsWith('/skip')
                ? 'skipped'
                : 'draft';
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: options.method == 'POST' ? 201 : 200,
                data: {
                  'success': true,
                  'data': {
                    ..._note,
                    'status': status,
                    'original_text':
                        (options.data as Map?)?['original_text'] ?? '原始表达',
                    'confirmed_text': status == 'confirmed' ? '原始表达' : null,
                  },
                },
              ),
            );
          },
        ),
      );
      final repository = FastApiPatientNoteRepository(PomiApiClient(dio: dio));

      final draft = await repository.create('原始表达');
      final confirmed = await repository.confirm(draft.id);
      await repository.copy(confirmed.id, visitContext: '下次复诊');

      expect(draft.originalText, '原始表达');
      expect(confirmed.status, PatientNoteStatus.confirmed);
      expect(requests.map((request) => request.path), [
        '/patient-notes',
        '/patient-notes/note-1/confirm',
        '/patient-notes/note-1/copy',
      ]);
      expect((requests.last.data as Map)['visit_context'], '下次复诊');
    },
  );

  test(
    'demo copy creates an independent draft that requires confirmation',
    () async {
      final repository = DemoPatientNoteRepository();
      final original = await repository.latest();
      final copy = await repository.copy(original!.id);

      expect(copy.id, isNot(original.id));
      expect(copy.sourceNoteId, original.id);
      expect(copy.status, PatientNoteStatus.draft);
      expect(copy.originalText, original.confirmedText);
    },
  );
}

const _note = <String, dynamic>{
  'id': 'note-1',
  'patient_id': 'patient-1',
  'visit_context': null,
  'original_text': '原始表达',
  'confirmed_text': null,
  'status': 'draft',
  'source_note_id': null,
  'confirmed_at': null,
  'created_at': '2026-08-27T10:00:00+00:00',
  'updated_at': '2026-08-27T10:00:00+00:00',
};
