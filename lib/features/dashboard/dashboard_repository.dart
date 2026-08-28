import '../../core/api_client.dart';
import '../../core/json_value.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../medications/medication_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);

enum DashboardSectionStatus {
  ok('ok'),
  empty('empty'),
  error('error');

  const DashboardSectionStatus(this.wireValue);
  final String wireValue;

  static DashboardSectionStatus parse(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw ApiFailure('INVALID_RESPONSE', '服务返回了未知的首页区块状态'),
  );
}

class DashboardSection<T> {
  const DashboardSection({
    required this.status,
    required this.data,
    this.errorCode,
  });

  factory DashboardSection.fromJson(
    dynamic value,
    T Function(dynamic value) parseData,
  ) {
    final json = jsonObject(value, 'dashboard section');
    final rawData = json['data'];
    return DashboardSection(
      status: DashboardSectionStatus.parse(jsonString(json, 'status')),
      data: rawData == null ? null : parseData(rawData),
      errorCode: jsonStringOrNull(json, 'error_code'),
    );
  }

  final DashboardSectionStatus status;
  final T? data;
  final String? errorCode;
}

class FollowUpSummary {
  const FollowUpSummary({
    required this.date,
    required this.timing,
    required this.days,
  });

  factory FollowUpSummary.fromJson(dynamic value) {
    final json = jsonObject(value, 'follow-up summary');
    return FollowUpSummary(
      date: jsonString(json, 'date'),
      timing: jsonString(json, 'timing'),
      days: jsonInt(json, 'days'),
    );
  }

  final String date;
  final String timing;
  final int days;
}

class TodayMedication {
  const TodayMedication({
    required this.medicationId,
    required this.drugName,
    required this.intakeStatus,
    this.specification,
    this.dosageText,
    this.frequency,
    this.recordedAt,
  });

  factory TodayMedication.fromJson(dynamic value) {
    final json = jsonObject(value, 'today medication');
    return TodayMedication(
      medicationId: jsonString(json, 'medication_id'),
      drugName: jsonString(json, 'drug_name'),
      specification: jsonStringOrNull(json, 'specification'),
      dosageText: jsonStringOrNull(json, 'dosage_text'),
      frequency: jsonStringOrNull(json, 'frequency'),
      intakeStatus: MedicationDailyStatus.parse(
        jsonString(json, 'intake_status'),
      ),
      recordedAt: jsonDateTimeOrNull(json, 'recorded_at'),
    );
  }

  final String medicationId;
  final String drugName;
  final String? specification;
  final String? dosageText;
  final String? frequency;
  final MedicationDailyStatus intakeStatus;
  final DateTime? recordedAt;
}

class MonthlyMedicationSummary {
  const MonthlyMedicationSummary({
    required this.month,
    required this.takenCount,
    required this.missedCount,
    required this.unrecordedCount,
  });

  factory MonthlyMedicationSummary.fromJson(dynamic value) {
    final json = jsonObject(value, 'monthly medication summary');
    return MonthlyMedicationSummary(
      month: jsonString(json, 'month'),
      takenCount: jsonInt(json, 'taken_count'),
      missedCount: jsonInt(json, 'missed_count'),
      unrecordedCount: jsonInt(json, 'unrecorded_count'),
    );
  }

  final String month;
  final int takenCount;
  final int missedCount;
  final int unrecordedCount;
}

class LatestCycleSummary {
  const LatestCycleSummary({required this.id, required this.startDate});

  factory LatestCycleSummary.fromJson(dynamic value) {
    final json = jsonObject(value, 'latest cycle summary');
    return LatestCycleSummary(
      id: jsonString(json, 'id'),
      startDate: jsonString(json, 'start_date'),
    );
  }

  final String id;
  final String startDate;
}

class LatestWeightSummary {
  const LatestWeightSummary({
    required this.id,
    required this.recordDate,
    required this.weightKg,
  });

  factory LatestWeightSummary.fromJson(dynamic value) {
    final json = jsonObject(value, 'latest weight summary');
    final weight = jsonDoubleOrNull(json, 'weight_kg');
    if (weight == null) {
      throw ApiFailure('INVALID_RESPONSE', '服务响应缺少字段 weight_kg');
    }
    return LatestWeightSummary(
      id: jsonString(json, 'id'),
      recordDate: jsonString(json, 'record_date'),
      weightKg: weight,
    );
  }

  final String id;
  final String recordDate;
  final double weightKg;
}

class TrackingSummary {
  const TrackingSummary({this.latestCycle, this.latestWeight});

  factory TrackingSummary.fromJson(dynamic value) {
    final json = jsonObject(value, 'tracking summary');
    return TrackingSummary(
      latestCycle:
          json['latest_cycle'] == null
              ? null
              : LatestCycleSummary.fromJson(json['latest_cycle']),
      latestWeight:
          json['latest_weight'] == null
              ? null
              : LatestWeightSummary.fromJson(json['latest_weight']),
    );
  }

  final LatestCycleSummary? latestCycle;
  final LatestWeightSummary? latestWeight;
}

class DocumentSummary {
  const DocumentSummary({required this.confirmed, required this.total});

  factory DocumentSummary.fromJson(dynamic value) {
    final json = jsonObject(value, 'document summary');
    return DocumentSummary(
      confirmed: jsonInt(json, 'confirmed'),
      total: jsonInt(json, 'total'),
    );
  }

  final int confirmed;
  final int total;
}

class LatestReportSummary {
  const LatestReportSummary({
    required this.id,
    required this.status,
    required this.generatedAt,
  });

  factory LatestReportSummary.fromJson(dynamic value) {
    final json = jsonObject(value, 'latest report summary');
    return LatestReportSummary(
      id: jsonString(json, 'id'),
      status: jsonString(json, 'status'),
      generatedAt: jsonDateTime(json, 'generated_at'),
    );
  }

  final String id;
  final String status;
  final DateTime generatedAt;
}

class DashboardData {
  const DashboardData({
    required this.serverDate,
    required this.dataAsOf,
    required this.followUp,
    required this.todayMedications,
    required this.monthlyMedicationSummary,
    required this.trackingSummary,
    required this.documentSummary,
    required this.latestReport,
  });

  factory DashboardData.fromJson(dynamic value) {
    final json = jsonObject(value, 'dashboard');
    return DashboardData(
      serverDate: jsonString(json, 'server_date'),
      dataAsOf: jsonDateTime(json, 'data_as_of'),
      followUp: DashboardSection.fromJson(
        json['follow_up'],
        FollowUpSummary.fromJson,
      ),
      todayMedications: DashboardSection.fromJson(
        json['today_medications'],
        (value) =>
            jsonArray(
              value,
              'today medications',
            ).map(TodayMedication.fromJson).toList(),
      ),
      monthlyMedicationSummary: DashboardSection.fromJson(
        json['monthly_medication_summary'],
        MonthlyMedicationSummary.fromJson,
      ),
      trackingSummary: DashboardSection.fromJson(
        json['tracking_summary'],
        TrackingSummary.fromJson,
      ),
      documentSummary: DashboardSection.fromJson(
        json['document_summary'],
        DocumentSummary.fromJson,
      ),
      latestReport: DashboardSection.fromJson(
        json['latest_report'],
        LatestReportSummary.fromJson,
      ),
    );
  }

  final String serverDate;
  final DateTime dataAsOf;
  final DashboardSection<FollowUpSummary> followUp;
  final DashboardSection<List<TodayMedication>> todayMedications;
  final DashboardSection<MonthlyMedicationSummary> monthlyMedicationSummary;
  final DashboardSection<TrackingSummary> trackingSummary;
  final DashboardSection<DocumentSummary> documentSummary;
  final DashboardSection<LatestReportSummary> latestReport;
}

class DashboardRepository {
  const DashboardRepository(this.api);

  final ApiClient api;

  Future<DashboardData> get({DateTime? date}) async => DashboardData.fromJson(
    await api.get(
      '/api/dashboard',
      queryParameters: {if (date != null) 'date': dateValue(date)},
    ),
  );
}
