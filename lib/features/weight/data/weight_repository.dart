import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_record.dart';

abstract interface class WeightRepository {
  Future<List<WeightRecord>> listWeights({DateTime? from, DateTime? to});

  Future<WeightRecord> createWeight({
    required DateTime recordDate,
    required double weightKg,
  });

  Future<WeightRecord> updateWeight({
    required String id,
    required DateTime recordDate,
    required double weightKg,
  });
}

class WeightRepositoryException implements Exception {
  const WeightRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiWeightRepository implements WeightRepository {
  ApiWeightRepository(this._client);

  final PomiApiClient _client;

  @override
  Future<List<WeightRecord>> listWeights({DateTime? from, DateTime? to}) async {
    try {
      final response = await _client.dio.get<dynamic>(
        '/weights',
        queryParameters: {
          if (from != null) 'from': _formatDate(from),
          if (to != null) 'to': _formatDate(to),
        },
      );
      final data = _unwrap(response.data);
      return [
        for (final item in data as List<dynamic>)
          WeightRecord.fromJson(Map<String, dynamic>.from(item as Map)),
      ]..sort((a, b) => a.recordDate.compareTo(b.recordDate));
    } on DioException catch (error) {
      throw WeightRepositoryException(_messageFor(error));
    }
  }

  @override
  Future<WeightRecord> createWeight({
    required DateTime recordDate,
    required double weightKg,
  }) => _write('/weights', recordDate: recordDate, weightKg: weightKg);

  @override
  Future<WeightRecord> updateWeight({
    required String id,
    required DateTime recordDate,
    required double weightKg,
  }) => _write(
    '/weights/$id',
    recordDate: recordDate,
    weightKg: weightKg,
    put: true,
  );

  Future<WeightRecord> _write(
    String path, {
    required DateTime recordDate,
    required double weightKg,
    bool put = false,
  }) async {
    try {
      final body = {
        'record_date': _formatDate(recordDate),
        'weight_kg': weightKg,
      };
      final response = put
          ? await _client.dio.put<dynamic>(path, data: body)
          : await _client.dio.post<dynamic>(path, data: body);
      return WeightRecord.fromJson(
        Map<String, dynamic>.from(_unwrap(response.data) as Map),
      );
    } on DioException catch (error) {
      throw WeightRepositoryException(_messageFor(error));
    }
  }

  static dynamic _unwrap(dynamic body) {
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }

  static String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _messageFor(DioException error) {
    return switch (error.response?.statusCode) {
      401 => '登录状态已失效，请重新登录',
      422 => '体重或日期不符合要求',
      _ => '体重数据暂时无法同步，请稍后重试',
    };
  }
}

class MemoryWeightRepository implements WeightRepository {
  MemoryWeightRepository({Iterable<WeightRecord> records = const []})
    : _records = [...records];

  factory MemoryWeightRepository.seeded({DateTime Function()? now}) {
    final current = (now ?? DateTime.now)();
    final today = DateTime(current.year, current.month, current.day);
    return MemoryWeightRepository(
      records: [
        for (final item in const [
          ('demo-weight-1', 24, 70.8),
          ('demo-weight-2', 17, 70.2),
          ('demo-weight-3', 10, 69.9),
          ('demo-weight-4', 3, 69.6),
        ])
          WeightRecord(
            id: item.$1,
            recordDate: today.subtract(Duration(days: item.$2)),
            weightKg: item.$3,
            createdAt: current,
            updatedAt: current,
          ),
      ],
    );
  }

  final List<WeightRecord> _records;
  int _nextId = 1;

  @override
  Future<List<WeightRecord>> listWeights({DateTime? from, DateTime? to}) async {
    final result = _records.where((record) {
      final date = _dateOnly(record.recordDate);
      return (from == null || !date.isBefore(_dateOnly(from))) &&
          (to == null || !date.isAfter(_dateOnly(to)));
    }).toList()..sort((a, b) => a.recordDate.compareTo(b.recordDate));
    return result;
  }

  @override
  Future<WeightRecord> createWeight({
    required DateTime recordDate,
    required double weightKg,
  }) async {
    final index = _records.indexWhere(
      (record) => _dateOnly(record.recordDate) == _dateOnly(recordDate),
    );
    if (index >= 0) {
      return updateWeight(
        id: _records[index].id,
        recordDate: recordDate,
        weightKg: weightKg,
      );
    }
    final now = DateTime.now();
    final record = WeightRecord(
      id: 'memory-weight-${_nextId++}',
      recordDate: _dateOnly(recordDate),
      weightKg: weightKg,
      createdAt: now,
      updatedAt: now,
    );
    _records.add(record);
    return record;
  }

  @override
  Future<WeightRecord> updateWeight({
    required String id,
    required DateTime recordDate,
    required double weightKg,
  }) async {
    final index = _records.indexWhere((record) => record.id == id);
    if (index < 0) throw const WeightRepositoryException('体重记录不存在');
    final old = _records[index];
    final updated = WeightRecord(
      id: old.id,
      recordDate: _dateOnly(recordDate),
      weightKg: weightKg,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
    );
    _records[index] = updated;
    return updated;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
