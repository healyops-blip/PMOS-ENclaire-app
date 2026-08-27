import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';

class MedicationDailyRecord {
  const MedicationDailyRecord({
    required this.medicationId,
    required this.date,
    required this.status,
    required this.editable,
    this.id,
    this.recordedAt,
    this.recordedByUid,
  });

  final String? id;
  final String medicationId;
  final DateTime date;
  final MedicationStatus status;
  final bool editable;
  final DateTime? recordedAt;
  final String? recordedByUid;

  MedicationDailyRecord copyWith({MedicationStatus? status}) =>
      MedicationDailyRecord(
        id: id,
        medicationId: medicationId,
        date: date,
        status: status ?? this.status,
        editable: editable,
        recordedAt: recordedAt,
        recordedByUid: recordedByUid,
      );

  factory MedicationDailyRecord.fromJson(Map<String, dynamic> json) =>
      MedicationDailyRecord(
        id: json['id'] as String?,
        medicationId: json['medication_id'] as String,
        date: DateTime.parse(json['record_date'] as String),
        status: MedicationStatus.values.byName(json['intake_status'] as String),
        editable: json['editable'] as bool? ?? false,
        recordedAt: DateTime.tryParse(json['recorded_at'] as String? ?? ''),
        recordedByUid: json['recorded_by_uid'] as String?,
      );
}

class MedicationDailyHistory {
  const MedicationDailyHistory({
    required this.businessDate,
    required this.editableFrom,
    required this.items,
    required this.takenCount,
    required this.missedCount,
    required this.unrecordedCount,
  });

  final DateTime businessDate;
  final DateTime editableFrom;
  final List<MedicationDailyRecord> items;
  final int takenCount;
  final int missedCount;
  final int unrecordedCount;

  MedicationDailyHistory replaceAt(
    int index,
    MedicationDailyRecord replacement,
  ) {
    final previous = items[index];
    if (previous.status == replacement.status) return this;

    int adjustedCount(int current, MedicationStatus countedStatus) =>
        current -
        (previous.status == countedStatus ? 1 : 0) +
        (replacement.status == countedStatus ? 1 : 0);

    return MedicationDailyHistory(
      businessDate: businessDate,
      editableFrom: editableFrom,
      items: [...items]..[index] = replacement,
      takenCount: adjustedCount(takenCount, MedicationStatus.taken),
      missedCount: adjustedCount(missedCount, MedicationStatus.missed),
      unrecordedCount: adjustedCount(
        unrecordedCount,
        MedicationStatus.unrecorded,
      ),
    );
  }
}
