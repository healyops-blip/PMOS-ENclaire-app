import '../../core/api_client.dart';
import '../../core/json_value.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final trackingRepositoryProvider = Provider<TrackingRepository>(
  (ref) => TrackingRepository(ref.watch(apiClientProvider)),
);

enum CycleFlowLevel {
  light('light'),
  medium('medium'),
  heavy('heavy'),
  unknown('unknown');

  const CycleFlowLevel(this.wireValue);
  final String wireValue;

  static CycleFlowLevel parse(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw ApiFailure('INVALID_RESPONSE', '服务返回了未知的经量状态'),
  );
}

class CycleRecord {
  const CycleRecord({
    required this.id,
    required this.startDate,
    required this.createdAt,
    required this.updatedAt,
    this.endDate,
    this.flowLevel,
    this.note,
    this.cycleLengthDays,
    this.durationDays,
  });

  factory CycleRecord.fromJson(dynamic value) {
    final json = jsonObject(value, 'cycle');
    final flow = jsonStringOrNull(json, 'flow_level');
    return CycleRecord(
      id: jsonString(json, 'id'),
      startDate: jsonString(json, 'start_date'),
      endDate: jsonStringOrNull(json, 'end_date'),
      flowLevel: flow == null ? null : CycleFlowLevel.parse(flow),
      note: jsonStringOrNull(json, 'note'),
      cycleLengthDays: jsonIntOrNull(json, 'cycle_length_days'),
      durationDays: jsonIntOrNull(json, 'duration_days'),
      createdAt: jsonDateTime(json, 'created_at'),
      updatedAt: jsonDateTime(json, 'updated_at'),
    );
  }

  final String id;
  final String startDate;
  final String? endDate;
  final CycleFlowLevel? flowLevel;
  final String? note;
  final int? cycleLengthDays;
  final int? durationDays;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class CycleInput {
  const CycleInput({
    required this.startDate,
    this.endDate,
    this.flowLevel,
    this.note,
    this.updatedAt,
  });

  final DateTime startDate;
  final DateTime? endDate;
  final CycleFlowLevel? flowLevel;
  final String? note;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'start_date': dateValue(startDate),
    'end_date': endDate == null ? null : dateValue(endDate!),
    'flow_level': flowLevel?.wireValue,
    'note': note,
    'source_type': 'manual',
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };
}

class WeightRecord {
  const WeightRecord({
    required this.id,
    required this.recordDate,
    required this.weightKg,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WeightRecord.fromJson(dynamic value) {
    final json = jsonObject(value, 'weight');
    final weight = jsonDoubleOrNull(json, 'weight_kg');
    if (weight == null) {
      throw ApiFailure('INVALID_RESPONSE', '服务响应缺少字段 weight_kg');
    }
    return WeightRecord(
      id: jsonString(json, 'id'),
      recordDate: jsonString(json, 'record_date'),
      weightKg: weight,
      createdAt: jsonDateTime(json, 'created_at'),
      updatedAt: jsonDateTime(json, 'updated_at'),
    );
  }

  final String id;
  final String recordDate;
  final double weightKg;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TrackingRepository {
  const TrackingRepository(this.api);

  final ApiClient api;

  Future<List<CycleRecord>> listCycles({DateTime? from, DateTime? to}) async =>
      jsonArray(
        await api.get(
          '/api/cycles',
          queryParameters: {
            if (from != null) 'from': dateValue(from),
            if (to != null) 'to': dateValue(to),
          },
        ),
        'cycles',
      ).map(CycleRecord.fromJson).toList();

  Future<CycleRecord> createCycle(CycleInput input) async =>
      CycleRecord.fromJson(await api.post('/api/cycles', data: input.toJson()));

  Future<CycleRecord> updateCycle(String id, CycleInput input) async =>
      CycleRecord.fromJson(
        await api.put('/api/cycles/$id', data: input.toJson()),
      );

  Future<void> deleteCycle(String id) async {
    await api.delete('/api/cycles/$id');
  }

  Future<List<WeightRecord>> listWeights({
    DateTime? from,
    DateTime? to,
  }) async =>
      jsonArray(
        await api.get(
          '/api/weights',
          queryParameters: {
            if (from != null) 'from': dateValue(from),
            if (to != null) 'to': dateValue(to),
          },
        ),
        'weights',
      ).map(WeightRecord.fromJson).toList();

  Future<WeightRecord> createOrUpdateWeight({
    required DateTime recordDate,
    required double weightKg,
  }) async => WeightRecord.fromJson(
    await api.post(
      '/api/weights',
      data: {'record_date': dateValue(recordDate), 'weight_kg': weightKg},
    ),
  );

  Future<WeightRecord> updateWeight({
    required String id,
    required DateTime recordDate,
    required double weightKg,
    required DateTime updatedAt,
  }) async => WeightRecord.fromJson(
    await api.put(
      '/api/weights/$id',
      data: {
        'record_date': dateValue(recordDate),
        'weight_kg': weightKg,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      },
    ),
  );
}
