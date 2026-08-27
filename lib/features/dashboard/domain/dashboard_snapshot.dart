import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';

enum DashboardSectionStatus { ok, empty, error }

class DashboardSection<T> {
  const DashboardSection({required this.status, this.data, this.errorCode});

  factory DashboardSection.fromJson(
    Map<String, dynamic> json,
    T? Function(Object? json) decode,
  ) {
    return DashboardSection(
      status: DashboardSectionStatus.values.byName(json['status'] as String),
      data: decode(json['data']),
      errorCode: (json['error'] as Map?)?['code']?.toString(),
    );
  }

  final DashboardSectionStatus status;
  final T? data;
  final String? errorCode;
}

class FollowUpSummary {
  const FollowUpSummary({
    required this.nextVisitDate,
    required this.state,
    required this.daysRemaining,
  });

  factory FollowUpSummary.fromJson(Map<String, dynamic> json) {
    return FollowUpSummary(
      nextVisitDate: DateTime.parse(json['next_visit_date'] as String),
      state: json['state'] as String,
      daysRemaining: json['days_remaining'] as int,
    );
  }

  final DateTime nextVisitDate;
  final String state;
  final int daysRemaining;
}

class MedicationMonthSummary {
  const MedicationMonthSummary({
    required this.taken,
    required this.missed,
    required this.unrecorded,
  });

  factory MedicationMonthSummary.fromJson(Map<String, dynamic> json) {
    return MedicationMonthSummary(
      taken: json['taken'] as int,
      missed: json['missed'] as int,
      unrecorded: json['unrecorded'] as int,
    );
  }

  final int taken;
  final int missed;
  final int unrecorded;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.businessDate,
    required this.followUp,
    required this.todayMedications,
    required this.monthSummary,
    required this.latestReport,
  });

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    return DashboardSnapshot(
      businessDate: DateTime.parse(json['business_date'] as String),
      followUp: DashboardSection.fromJson(
        Map<String, dynamic>.from(json['follow_up'] as Map),
        (value) => value == null
            ? null
            : FollowUpSummary.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
      todayMedications: DashboardSection.fromJson(
        Map<String, dynamic>.from(json['today_medications'] as Map),
        (value) => value == null
            ? null
            : [
                for (final item in value as List)
                  _medicationFromJson(Map<String, dynamic>.from(item as Map)),
              ],
      ),
      monthSummary: DashboardSection.fromJson(
        Map<String, dynamic>.from(json['monthly_medication_summary'] as Map),
        (value) => value == null
            ? null
            : MedicationMonthSummary.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
      ),
      latestReport: DashboardSection.fromJson(
        Map<String, dynamic>.from(json['latest_report'] as Map),
        (value) => value,
      ),
    );
  }

  final DateTime businessDate;
  final DashboardSection<FollowUpSummary> followUp;
  final DashboardSection<List<Medication>> todayMedications;
  final DashboardSection<MedicationMonthSummary> monthSummary;
  final DashboardSection<Object?> latestReport;
}

Medication _medicationFromJson(Map<String, dynamic> json) {
  final daily = Map<String, dynamic>.from(json['daily'] as Map);
  final status = switch (daily['intake_status']) {
    'taken' => MedicationStatus.taken,
    'missed' => MedicationStatus.missed,
    _ => MedicationStatus.unrecorded,
  };
  final dose = [
    json['dosage_value']?.toString(),
    json['dosage_unit']?.toString(),
    json['frequency']?.toString(),
  ].where((item) => item != null && item.isNotEmpty).join(' · ');
  return Medication(
    id: json['id'] as String,
    name: json['drug_name'] as String,
    dose: dose,
    group: json['source_category'] == 'supplement' ? '日常补剂' : '多囊用药',
    status: status,
    takenDays: 0,
    missedDays: 0,
  );
}
