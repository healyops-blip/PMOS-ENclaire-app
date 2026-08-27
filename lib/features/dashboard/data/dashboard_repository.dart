import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_cache_store.dart';
import 'package:pmos_enclaire/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';

class DashboardLoad {
  const DashboardLoad({
    required this.snapshot,
    required this.offline,
    required this.updatedAt,
  });

  final DashboardSnapshot snapshot;
  final bool offline;
  final DateTime updatedAt;
}

class DashboardAuthorizationFailure implements Exception {
  const DashboardAuthorizationFailure();
}

abstract interface class DashboardRepository {
  Future<DashboardLoad> load(String uid);
  Future<void> clear(String uid);
}

class FastApiDashboardRepository implements DashboardRepository {
  FastApiDashboardRepository(
    this.client,
    this.cache, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PomiApiClient client;
  final DashboardCacheStore cache;
  final DateTime Function() _clock;

  @override
  Future<DashboardLoad> load(String uid) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>('/dashboard');
      final json = Map<String, dynamic>.from(response.data!['data'] as Map);
      final now = _clock();
      await cache.write(uid, json, now);
      return DashboardLoad(
        snapshot: DashboardSnapshot.fromJson(json),
        offline: false,
        updatedAt: now,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await cache.clear(uid);
        throw const DashboardAuthorizationFailure();
      }
      final cached = await cache.read(uid);
      if (cached == null) rethrow;
      return DashboardLoad(
        snapshot: DashboardSnapshot.fromJson(cached.json),
        offline: true,
        updatedAt: cached.savedAt,
      );
    }
  }

  @override
  Future<void> clear(String uid) => cache.clear(uid);
}

class DemoDashboardRepository implements DashboardRepository {
  const DemoDashboardRepository();

  @override
  Future<DashboardLoad> load(String uid) async {
    final now = DateTime.now();
    return DashboardLoad(
      snapshot: DashboardSnapshot(
        businessDate: now,
        followUp: DashboardSection(
          status: DashboardSectionStatus.ok,
          data: FollowUpSummary(
            nextVisitDate: now.add(const Duration(days: 15)),
            state: 'upcoming',
            daysRemaining: 15,
          ),
        ),
        todayMedications: const DashboardSection(
          status: DashboardSectionStatus.ok,
          data: [
            Medication(
              id: 'demo-metformin',
              name: '二甲双胍',
              dose: '500 mg · 晚餐随餐',
              group: '多囊用药',
              status: MedicationStatus.taken,
              takenDays: 22,
              missedDays: 2,
            ),
            Medication(
              id: 'demo-yasmin',
              name: '优思明',
              dose: '1 片 · 每晚',
              group: '多囊用药',
              status: MedicationStatus.unrecorded,
              takenDays: 20,
              missedDays: 1,
            ),
          ],
        ),
        monthSummary: const DashboardSection(
          status: DashboardSectionStatus.ok,
          data: MedicationMonthSummary(taken: 23, missed: 2, unrecorded: 4),
        ),
        latestReport: const DashboardSection(
          status: DashboardSectionStatus.empty,
        ),
      ),
      offline: false,
      updatedAt: now,
    );
  }

  @override
  Future<void> clear(String uid) async {}
}
