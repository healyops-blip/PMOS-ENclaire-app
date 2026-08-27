import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/cycle/domain/menstrual_cycle.dart';

abstract interface class CycleRepository {
  Future<List<MenstrualCycle>> list();

  Future<MenstrualCycle> create(CycleDraft draft);

  Future<MenstrualCycle> update(String id, CycleDraft draft);

  Future<void> delete(String id);
}

class CycleRepositoryException implements Exception {
  const CycleRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FastApiCycleRepository implements CycleRepository {
  FastApiCycleRepository(this.client);

  final PomiApiClient client;

  String get _cyclesUrl {
    final base = client.dio.options.baseUrl.replaceFirst(RegExp(r'/$'), '');
    return '$base/cycles';
  }

  @override
  Future<List<MenstrualCycle>> list() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(_cyclesUrl);
      final rows = response.data?['data'] as List<dynamic>? ?? const [];
      return [
        for (final row in rows)
          MenstrualCycle.fromJson(row as Map<String, dynamic>),
      ];
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<MenstrualCycle> create(CycleDraft draft) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        _cyclesUrl,
        data: draft.toJson(),
      );
      return _cycle(response);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<MenstrualCycle> update(String id, CycleDraft draft) async {
    try {
      final response = await client.dio.put<Map<String, dynamic>>(
        '$_cyclesUrl/$id',
        data: draft.toJson(),
      );
      return _cycle(response);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await client.dio.delete<void>('$_cyclesUrl/$id');
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  MenstrualCycle _cycle(Response<Map<String, dynamic>> response) {
    return MenstrualCycle.fromJson(
      response.data?['data'] as Map<String, dynamic>,
    );
  }

  CycleRepositoryException _mapError(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final detail = body['error'];
      if (detail is Map<String, dynamic> && detail['message'] is String) {
        return CycleRepositoryException(detail['message'] as String);
      }
    }
    return const CycleRepositoryException('加载失败，请检查网络后重试');
  }
}

class DemoCycleRepository implements CycleRepository {
  DemoCycleRepository()
    : _cycles = [
        MenstrualCycle(
          id: 'demo-3',
          startDate: DateTime(2026, 8, 6),
          endDate: DateTime(2026, 8, 10),
          cycleLengthDays: 29,
          durationDays: 5,
          createdAt: DateTime(2026, 8, 6),
          updatedAt: DateTime(2026, 8, 10),
        ),
        MenstrualCycle(
          id: 'demo-2',
          startDate: DateTime(2026, 7, 8),
          endDate: DateTime(2026, 7, 12),
          cycleLengthDays: 30,
          durationDays: 5,
          createdAt: DateTime(2026, 7, 8),
          updatedAt: DateTime(2026, 7, 12),
        ),
        MenstrualCycle(
          id: 'demo-1',
          startDate: DateTime(2026, 6, 8),
          endDate: DateTime(2026, 6, 12),
          durationDays: 5,
          createdAt: DateTime(2026, 6, 8),
          updatedAt: DateTime(2026, 6, 12),
        ),
      ];

  final List<MenstrualCycle> _cycles;

  @override
  Future<List<MenstrualCycle>> list() async => List.unmodifiable(_cycles);

  @override
  Future<MenstrualCycle> create(CycleDraft draft) async {
    final value = MenstrualCycle(
      id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
      startDate: draft.startDate,
      endDate: draft.endDate,
      flowLevel: draft.flowLevel,
      note: draft.note,
      cycleLengthDays: _cycles.isEmpty
          ? null
          : draft.startDate.difference(_cycles.first.startDate).inDays,
      durationDays: draft.endDate == null
          ? null
          : draft.endDate!.difference(draft.startDate).inDays + 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _cycles.insert(0, value);
    return value;
  }

  @override
  Future<MenstrualCycle> update(String id, CycleDraft draft) async {
    final index = _cycles.indexWhere((cycle) => cycle.id == id);
    if (index < 0) throw const CycleRepositoryException('记录不存在');
    final existing = _cycles[index];
    final value = MenstrualCycle(
      id: existing.id,
      startDate: draft.startDate,
      endDate: draft.endDate,
      flowLevel: draft.flowLevel,
      note: draft.note,
      cycleLengthDays: existing.cycleLengthDays,
      durationDays: draft.endDate == null
          ? null
          : draft.endDate!.difference(draft.startDate).inDays + 1,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    _cycles[index] = value;
    return value;
  }

  @override
  Future<void> delete(String id) async {
    _cycles.removeWhere((cycle) => cycle.id == id);
  }
}
