import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_cache_store.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_repository.dart';

void main() {
  test(
    'falls back to the encrypted UID cache and never crosses accounts',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      var offline = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (offline) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'success': true, 'data': _dashboardJson},
                ),
              );
            }
          },
        ),
      );
      final cache = _MemoryDashboardCache();
      final repository = FastApiDashboardRepository(
        PomiApiClient(dio: dio),
        cache,
        clock: () => DateTime.utc(2026, 8, 27, 12),
      );

      final online = await repository.load('uid-a');
      expect(online.offline, isFalse);
      offline = true;
      final cached = await repository.load('uid-a');
      expect(cached.offline, isTrue);
      expect(cached.updatedAt, DateTime.utc(2026, 8, 27, 12));
      await expectLater(repository.load('uid-b'), throwsA(isA<DioException>()));

      await repository.clear('uid-a');
      await expectLater(repository.load('uid-a'), throwsA(isA<DioException>()));
    },
  );
}

class _MemoryDashboardCache implements DashboardCacheStore {
  final entries = <String, DashboardCacheEntry>{};

  @override
  Future<void> clear(String uid) async => entries.remove(uid);

  @override
  Future<DashboardCacheEntry?> read(String uid) async => entries[uid];

  @override
  Future<void> write(
    String uid,
    Map<String, dynamic> json,
    DateTime savedAt,
  ) async {
    entries[uid] = DashboardCacheEntry(json: json, savedAt: savedAt);
  }
}

const _dashboardJson = <String, dynamic>{
  'business_date': '2026-08-27',
  'follow_up': {'status': 'empty', 'data': null, 'error': null},
  'today_medications': {'status': 'empty', 'data': <dynamic>[], 'error': null},
  'monthly_medication_summary': {
    'status': 'ok',
    'data': {'taken': 1, 'missed': 2, 'unrecorded': 3},
    'error': null,
  },
  'latest_report': {'status': 'empty', 'data': null, 'error': null},
};
