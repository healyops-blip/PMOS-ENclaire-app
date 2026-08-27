import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/dashboard/application/dashboard_controller.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_cache_store.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_repository.dart';
import 'package:pmos_enclaire/features/dashboard/domain/dashboard_snapshot.dart';

void main() {
  test(
    'falls back to the encrypted UID cache and never crosses accounts',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      var offline = false;
      var unauthorized = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (unauthorized) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 401),
                ),
              );
            } else if (offline) {
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

      offline = false;
      await repository.load('uid-a');
      unauthorized = true;
      await expectLater(
        repository.load('uid-a'),
        throwsA(isA<DashboardAuthorizationFailure>()),
      );
      unauthorized = false;
      offline = true;
      await expectLater(repository.load('uid-a'), throwsA(isA<DioException>()));
    },
  );

  test(
    'revoked authorization clears in-memory medical data and logs out',
    () async {
      final repository = _RevokedRepository();
      var logoutCalls = 0;
      final controller = DashboardController(
        repository: repository,
        uid: 'uid-a',
        onUnauthorized: () async => logoutCalls++,
      );

      await controller.load();
      expect(controller.snapshot, isNotNull);
      repository.revoked = true;

      await controller.load();

      expect(controller.snapshot, isNull);
      expect(controller.offline, isFalse);
      expect(controller.updatedAt, isNull);
      expect(controller.error, isA<DashboardAuthorizationFailure>());
      expect(logoutCalls, 1);
    },
  );

  test('decodes only stable latest-report metadata', () {
    final json = Map<String, dynamic>.from(_dashboardJson)
      ..['latest_report'] = {
        'status': 'ok',
        'data': {
          'report_id': 'report-1',
          'status': 'succeeded',
          'generated_at': '2026-08-27T10:00:00+00:00',
          'snapshot_hash': List.filled(64, 'd').join(),
        },
        'error': null,
      };

    final report = DashboardSnapshot.fromJson(json).latestReport.data;

    expect(report?.reportId, 'report-1');
    expect(report?.status, 'succeeded');
    expect(report?.generatedAt, DateTime.utc(2026, 8, 27, 10));
    expect(report?.snapshotHash, List.filled(64, 'd').join());
  });

  test(
    'a slower earlier refresh cannot overwrite the newest dashboard',
    () async {
      final repository = _ConcurrentRepository();
      final controller = DashboardController(
        repository: repository,
        uid: 'uid-a',
      );

      final first = controller.load();
      final second = controller.load();
      repository.complete(1, '2026-08-28');
      await second;
      repository.complete(0, '2026-08-27');
      await first;

      expect(controller.snapshot?.businessDate, DateTime(2026, 8, 28));
      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
    },
  );
}

class _ConcurrentRepository implements DashboardRepository {
  final requests = <Completer<DashboardLoad>>[];

  @override
  Future<void> clear(String uid) async {}

  @override
  Future<DashboardLoad> load(String uid) {
    final completer = Completer<DashboardLoad>();
    requests.add(completer);
    return completer.future;
  }

  void complete(int index, String businessDate) {
    final json = Map<String, dynamic>.from(_dashboardJson)
      ..['business_date'] = businessDate;
    requests[index].complete(
      DashboardLoad(
        snapshot: DashboardSnapshot.fromJson(json),
        offline: false,
        updatedAt: DateTime.parse(businessDate),
      ),
    );
  }
}

class _RevokedRepository implements DashboardRepository {
  bool revoked = false;

  @override
  Future<void> clear(String uid) async {}

  @override
  Future<DashboardLoad> load(String uid) async {
    if (revoked) throw const DashboardAuthorizationFailure();
    return DashboardLoad(
      snapshot: DashboardSnapshot.fromJson(_dashboardJson),
      offline: false,
      updatedAt: DateTime.utc(2026, 8, 27, 12),
    );
  }
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
