import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';

abstract interface class MedicationDailyGateway {
  Future<void> setDailyStatus(
    String medicationId,
    DateTime date,
    MedicationStatus status,
  );
}

abstract interface class MedicationRepository
    implements MedicationDailyGateway {
  Future<List<Medication>> listMedications();

  Future<Medication> createMedication({
    required String name,
    required String sourceCategory,
    required DateTime startDate,
    num? dosageValue,
    String? dosageUnit,
    String? frequency,
  });

  Future<Medication> updateMedication(
    Medication medication, {
    required String eventType,
    num? dosageValue,
    String? dosageUnit,
    String? frequency,
    String? stopSource,
  });

  Future<List<MedicationEvent>> listEvents(String medicationId);
}

class MedicationFailure implements Exception {
  const MedicationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class FastApiMedicationRepository implements MedicationRepository {
  FastApiMedicationRepository(this._client);

  final PomiApiClient _client;

  @override
  Future<List<Medication>> listMedications() async {
    try {
      final today = DateTime.now();
      final responses = await Future.wait([
        _client.dio.get<Map<String, dynamic>>('/medications'),
        _client.dio.get<Map<String, dynamic>>(
          '/medication-daily',
          queryParameters: {
            'from': _date(DateTime(today.year, today.month)),
            'to': _date(today),
          },
        ),
      ]);
      final data = _data(responses[0].data);
      final medications = (data['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Medication.fromJson)
          .toList(growable: false);
      final dailyItems = (_data(responses[1].data)['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final todayKey = _date(today);
      final todayStatus = <String, MedicationStatus>{};
      final taken = <String, int>{};
      final missed = <String, int>{};
      for (final item in dailyItems) {
        final medicationId = item['medication_id'] as String;
        final status = MedicationStatus.values.byName(
          item['intake_status'] as String,
        );
        if (item['record_date'] == todayKey) {
          todayStatus[medicationId] = status;
        }
        if (status == MedicationStatus.taken) {
          taken.update(medicationId, (value) => value + 1, ifAbsent: () => 1);
        } else if (status == MedicationStatus.missed) {
          missed.update(medicationId, (value) => value + 1, ifAbsent: () => 1);
        }
      }
      return medications
          .map(
            (medication) => medication.copyWith(
              status: todayStatus[medication.id] ?? MedicationStatus.unrecorded,
              takenDays: taken[medication.id] ?? 0,
              missedDays: missed[medication.id] ?? 0,
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw MedicationFailure(_message(error));
    }
  }

  @override
  Future<Medication> createMedication({
    required String name,
    required String sourceCategory,
    required DateTime startDate,
    num? dosageValue,
    String? dosageUnit,
    String? frequency,
  }) async {
    final date = _date(startDate);
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/medications',
        data: {
          'drug_name': name,
          'source_category': sourceCategory,
          'start_date': date,
          'event_date': date,
          'dosage_value': ?dosageValue,
          'dosage_unit': ?dosageUnit,
          'frequency': ?frequency,
        },
        options: Options(
          headers: {
            'Idempotency-Key':
                'flutter-${DateTime.now().microsecondsSinceEpoch}-$name',
          },
        ),
      );
      return Medication.fromJson(
        _data(response.data)['medication'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw MedicationFailure(_message(error));
    }
  }

  @override
  Future<Medication> updateMedication(
    Medication medication, {
    required String eventType,
    num? dosageValue,
    String? dosageUnit,
    String? frequency,
    String? stopSource,
  }) async {
    if (medication.updatedAt == null) {
      throw const MedicationFailure('用药版本时间缺失，请刷新后重试');
    }
    try {
      final response = await _client.dio.put<Map<String, dynamic>>(
        '/medications/${medication.id}',
        data: {
          'event_type': eventType,
          'event_date': _date(DateTime.now()),
          'updated_at': medication.updatedAt!.toIso8601String(),
          'dosage_value': ?dosageValue,
          'dosage_unit': ?dosageUnit,
          'frequency': ?frequency,
          'stop_source': ?stopSource,
        },
      );
      return Medication.fromJson(
        _data(response.data)['medication'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw MedicationFailure(_message(error));
    }
  }

  @override
  Future<List<MedicationEvent>> listEvents(String medicationId) async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        '/medications/$medicationId/events',
      );
      return _dataList(response.data)
          .cast<Map<String, dynamic>>()
          .map(MedicationEvent.fromJson)
          .toList(growable: false);
    } on DioException catch (error) {
      throw MedicationFailure(_message(error));
    }
  }

  @override
  Future<void> setDailyStatus(
    String medicationId,
    DateTime date,
    MedicationStatus status,
  ) async {
    try {
      await _client.dio.put<Map<String, dynamic>>(
        '/medications/$medicationId/daily-status',
        data: {'record_date': _date(date), 'intake_status': status.name},
      );
    } on DioException catch (error) {
      throw MedicationFailure(_message(error));
    }
  }

  static Map<String, dynamic> _data(Map<String, dynamic>? body) {
    return body?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  static List<dynamic> _dataList(Map<String, dynamic>? body) {
    return body?['data'] as List<dynamic>? ?? const [];
  }

  static String _message(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final detail = body['error'];
      if (detail is Map<String, dynamic> && detail['message'] is String) {
        return detail['message'] as String;
      }
    }
    return '网络请求失败，请检查连接后重试';
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class DemoMedicationRepository implements MedicationRepository {
  DemoMedicationRepository([List<Medication> initial = const []])
    : _medications = [...initial];

  final List<Medication> _medications;

  @override
  Future<List<Medication>> listMedications() async =>
      List.unmodifiable(_medications);

  @override
  Future<Medication> createMedication({
    required String name,
    required String sourceCategory,
    required DateTime startDate,
    num? dosageValue,
    String? dosageUnit,
    String? frequency,
  }) async {
    final medication = Medication(
      id: 'demo-${_medications.length + 1}',
      name: name,
      dose: [
        if (dosageValue != null) '$dosageValue ${dosageUnit ?? ''}'.trim(),
        ?frequency,
      ].join(' · '),
      group: medicationGroupLabel(sourceCategory),
      status: MedicationStatus.unrecorded,
      takenDays: 0,
      missedDays: 0,
      sourceCategory: sourceCategory,
      startDate: startDate,
      updatedAt: DateTime.now(),
    );
    _medications.add(medication);
    return medication;
  }

  @override
  Future<Medication> updateMedication(
    Medication medication, {
    required String eventType,
    num? dosageValue,
    String? dosageUnit,
    String? frequency,
    String? stopSource,
  }) async => medication.copyWith(
    id: eventType == 'adjusted' ? '${medication.id}-v2' : medication.id,
    dose: dosageValue == null
        ? medication.dose
        : '$dosageValue ${dosageUnit ?? medication.dosageUnit ?? ''}'.trim(),
    lifecycle: switch (eventType) {
      'paused' => MedicationLifecycle.paused,
      'resumed' => MedicationLifecycle.active,
      'stopped' => MedicationLifecycle.stopped,
      _ => medication.lifecycle,
    },
    updatedAt: DateTime.now(),
  );

  @override
  Future<List<MedicationEvent>> listEvents(String medicationId) async => [
    MedicationEvent(type: 'created', date: DateTime(2026, 8, 1)),
  ];

  @override
  Future<void> setDailyStatus(
    String medicationId,
    DateTime date,
    MedicationStatus status,
  ) async {}
}
