import '../../core/api_client.dart';
import '../../core/json_value.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final medicationRepositoryProvider = Provider<MedicationRepository>(
  (ref) => MedicationRepository(ref.watch(apiClientProvider)),
);

enum MedicationSourceCategory {
  prescribed('prescribed'),
  supplement('supplement'),
  otherLongTerm('other_long_term');

  const MedicationSourceCategory(this.wireValue);
  final String wireValue;

  static MedicationSourceCategory parse(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw ApiFailure('INVALID_RESPONSE', '服务返回了未知的药品分类'),
  );
}

enum MedicationStatus {
  active('active'),
  paused('paused'),
  stopped('stopped');

  const MedicationStatus(this.wireValue);
  final String wireValue;

  static MedicationStatus parse(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw ApiFailure('INVALID_RESPONSE', '服务返回了未知的用药状态'),
  );
}

enum MedicationDailyStatus {
  taken('taken'),
  missed('missed'),
  unrecorded('unrecorded');

  const MedicationDailyStatus(this.wireValue);
  final String wireValue;

  static MedicationDailyStatus parse(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw ApiFailure('INVALID_RESPONSE', '服务返回了未知的每日用药状态'),
  );
}

class Medication {
  const Medication({
    required this.id,
    required this.drugName,
    required this.sourceCategory,
    required this.currentStatus,
    required this.createdAt,
    required this.updatedAt,
    this.specification,
    this.dosageValue,
    this.dosageUnit,
    this.frequency,
    this.route,
    this.startDate,
  });

  factory Medication.fromJson(dynamic value) {
    final json = jsonObject(value, 'medication');
    return Medication(
      id: jsonString(json, 'id'),
      drugName: jsonString(json, 'drug_name'),
      sourceCategory: MedicationSourceCategory.parse(
        jsonString(json, 'source_category'),
      ),
      currentStatus: MedicationStatus.parse(jsonString(json, 'current_status')),
      specification: jsonStringOrNull(json, 'specification'),
      dosageValue: jsonDoubleOrNull(json, 'dosage_value'),
      dosageUnit: jsonStringOrNull(json, 'dosage_unit'),
      frequency: jsonStringOrNull(json, 'frequency'),
      route: jsonStringOrNull(json, 'route'),
      startDate: jsonStringOrNull(json, 'start_date'),
      createdAt: jsonDateTime(json, 'created_at'),
      updatedAt: jsonDateTime(json, 'updated_at'),
    );
  }

  final String id;
  final String drugName;
  final MedicationSourceCategory sourceCategory;
  final MedicationStatus currentStatus;
  final String? specification;
  final double? dosageValue;
  final String? dosageUnit;
  final String? frequency;
  final String? route;
  final String? startDate;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MedicationPage {
  const MedicationPage({
    required this.serverDate,
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory MedicationPage.fromJson(dynamic value) {
    final json = jsonObject(value, 'medication page');
    return MedicationPage(
      serverDate: jsonString(json, 'server_date'),
      items:
          jsonArray(
            json['items'],
            'medications',
          ).map(Medication.fromJson).toList(),
      nextCursor: jsonStringOrNull(json, 'next_cursor'),
      hasMore: jsonBool(json, 'has_more'),
    );
  }

  final String serverDate;
  final List<Medication> items;
  final String? nextCursor;
  final bool hasMore;
}

class MedicationCreateInput {
  const MedicationCreateInput({
    required this.drugName,
    required this.sourceCategory,
    this.specification,
    this.dosageValue,
    this.dosageUnit,
    this.frequency,
    this.route,
    this.startDate,
    this.note,
  });

  final String drugName;
  final MedicationSourceCategory sourceCategory;
  final String? specification;
  final double? dosageValue;
  final String? dosageUnit;
  final String? frequency;
  final String? route;
  final String? startDate;
  final String? note;

  Map<String, dynamic> toJson() => {
    'drug_name': drugName,
    'source_category': sourceCategory.wireValue,
    'specification': specification,
    'dosage_value': dosageValue,
    'dosage_unit': dosageUnit,
    'frequency': frequency,
    'route': route,
    'start_date': startDate,
    'note': note,
  };
}

enum MedicationEventType {
  adjusted('adjusted'),
  paused('paused'),
  resumed('resumed'),
  stopped('stopped');

  const MedicationEventType(this.wireValue);
  final String wireValue;
}

class MedicationUpdateInput {
  const MedicationUpdateInput({
    required this.eventType,
    required this.eventDate,
    required this.updatedAt,
    this.stopSource,
    this.changeReason,
    this.note,
  });

  final MedicationEventType eventType;
  final DateTime eventDate;
  final DateTime updatedAt;
  final String? stopSource;
  final String? changeReason;
  final String? note;

  Map<String, dynamic> toJson() => {
    'event_type': eventType.wireValue,
    'event_date': dateValue(eventDate),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'stop_source': stopSource,
    'change_reason': changeReason,
    'note': note,
  };
}

class MedicationDailyRecord {
  const MedicationDailyRecord({
    required this.medicationId,
    required this.recordDate,
    required this.intakeStatus,
    this.id,
    this.recordedAt,
  });

  factory MedicationDailyRecord.fromJson(dynamic value) {
    final json = jsonObject(value, 'medication daily record');
    return MedicationDailyRecord(
      id: jsonStringOrNull(json, 'id'),
      medicationId: jsonString(json, 'medication_id'),
      recordDate: jsonString(json, 'record_date'),
      intakeStatus: MedicationDailyStatus.parse(
        jsonString(json, 'intake_status'),
      ),
      recordedAt: jsonDateTimeOrNull(json, 'recorded_at'),
    );
  }

  final String? id;
  final String medicationId;
  final String recordDate;
  final MedicationDailyStatus intakeStatus;
  final DateTime? recordedAt;
}

class MedicationRepository {
  const MedicationRepository(this.api);

  final ApiClient api;

  Future<MedicationPage> list({
    MedicationStatus? status,
    String? cursor,
    int limit = 20,
  }) async => MedicationPage.fromJson(
    await api.get(
      '/api/medications',
      queryParameters: {
        if (status != null) 'status': status.wireValue,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    ),
  );

  Future<Medication> create(
    MedicationCreateInput input, {
    required String idempotencyKey,
  }) async => Medication.fromJson(
    await api.post(
      '/api/medications',
      data: input.toJson(),
      headers: {'Idempotency-Key': idempotencyKey},
    ),
  );

  Future<Medication> update(String id, MedicationUpdateInput input) async =>
      Medication.fromJson(
        await api.put('/api/medications/$id', data: input.toJson()),
      );

  Future<MedicationDailyRecord> setDailyStatus({
    required String medicationId,
    required DateTime recordDate,
    required MedicationDailyStatus status,
  }) async => MedicationDailyRecord.fromJson(
    await api.put(
      '/api/medications/$medicationId/daily-status',
      data: {
        'record_date': dateValue(recordDate),
        'intake_status': status.wireValue,
      },
    ),
  );

  Future<List<MedicationDailyRecord>> dailyRange({
    required DateTime from,
    required DateTime to,
    String? medicationId,
  }) async =>
      jsonArray(
        await api.get(
          '/api/medication-daily',
          queryParameters: {
            'from': dateValue(from),
            'to': dateValue(to),
            if (medicationId != null) 'medication_id': medicationId,
          },
        ),
        'medication daily records',
      ).map(MedicationDailyRecord.fromJson).toList();
}
