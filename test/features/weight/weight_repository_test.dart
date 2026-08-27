import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

void main() {
  test('API repository uses weight endpoints and keeps trend sorted', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final body = switch ((options.method, options.path)) {
            ('GET', '/weights') => [
              _record('later', '2026-08-27', 63.2),
              _record('earlier', '2026-08-05', 64.0),
            ],
            ('POST', '/weights') => _record('created', '2026-08-27', 63.2),
            ('PUT', '/weights/created') => _record(
              'created',
              '2026-08-27',
              63.1,
            ),
            _ => throw StateError(
              'Unexpected request: ${options.method} ${options.path}',
            ),
          };
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: body,
              statusCode: 200,
            ),
          );
        },
      ),
    );
    final repository = ApiWeightRepository(PomiApiClient(dio: dio));

    final trend = await repository.listWeights();
    final created = await repository.createWeight(
      recordDate: DateTime(2026, 8, 27),
      weightKg: 63.2,
    );
    final updated = await repository.updateWeight(
      id: created.id,
      recordDate: DateTime(2026, 8, 27),
      weightKg: 63.1,
    );

    expect(trend.map((item) => item.id), ['earlier', 'later']);
    expect(updated.weightKg, 63.1);
    expect(requests.map((request) => request.method), ['GET', 'POST', 'PUT']);
    expect(requests[1].data, {'record_date': '2026-08-27', 'weight_kg': 63.2});
  });
}

Map<String, dynamic> _record(String id, String date, double weight) => {
  'id': id,
  'record_date': date,
  'weight_kg': weight,
  'created_at': '2026-08-27T10:00:00Z',
  'updated_at': '2026-08-27T10:00:00Z',
};
