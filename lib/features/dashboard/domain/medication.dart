enum MedicationStatus { taken, missed, unrecorded }

enum MedicationLifecycle { active, paused, stopped }

class Medication {
  const Medication({
    this.id = '',
    required this.name,
    required this.dose,
    required this.group,
    required this.status,
    required this.takenDays,
    required this.missedDays,
    this.lifecycle = MedicationLifecycle.active,
    this.sourceCategory = 'other_long_term',
    this.specification,
    this.dosageValue,
    this.dosageUnit,
    this.frequency,
    this.route,
    this.startDate,
    this.endDate,
    this.replacesMedicationId,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String dose;
  final String group;
  final MedicationStatus status;
  final int takenDays;
  final int missedDays;
  final MedicationLifecycle lifecycle;
  final String sourceCategory;
  final String? specification;
  final num? dosageValue;
  final String? dosageUnit;
  final String? frequency;
  final String? route;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? replacesMedicationId;
  final DateTime? updatedAt;

  Medication copyWith({
    String? id,
    String? name,
    String? dose,
    String? group,
    MedicationStatus? status,
    int? takenDays,
    int? missedDays,
    MedicationLifecycle? lifecycle,
    DateTime? updatedAt,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      dose: dose ?? this.dose,
      group: group ?? this.group,
      status: status ?? this.status,
      takenDays: takenDays ?? this.takenDays,
      missedDays: missedDays ?? this.missedDays,
      lifecycle: lifecycle ?? this.lifecycle,
      sourceCategory: sourceCategory,
      specification: specification,
      dosageValue: dosageValue,
      dosageUnit: dosageUnit,
      frequency: frequency,
      route: route,
      startDate: startDate,
      endDate: endDate,
      replacesMedicationId: replacesMedicationId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Medication.fromJson(Map<String, dynamic> json) {
    final category = json['source_category'] as String? ?? 'other_long_term';
    final dosageValue = json['dosage_value'] as num?;
    final dosageUnit = json['dosage_unit'] as String?;
    final frequency = json['frequency'] as String?;
    final doseParts = <String>[
      if (dosageValue != null) '$dosageValue ${dosageUnit ?? ''}'.trim(),
      if (frequency != null && frequency.isNotEmpty) frequency,
    ];
    return Medication(
      id: json['id'] as String? ?? '',
      name: json['drug_name'] as String? ?? '',
      dose: doseParts.isEmpty ? '剂量待确认' : doseParts.join(' · '),
      group: medicationGroupLabel(category),
      status: MedicationStatus.unrecorded,
      takenDays: 0,
      missedDays: 0,
      lifecycle: MedicationLifecycle.values.byName(
        json['status'] as String? ?? 'active',
      ),
      sourceCategory: category,
      specification: json['specification'] as String?,
      dosageValue: dosageValue,
      dosageUnit: dosageUnit,
      frequency: frequency,
      route: json['route'] as String?,
      startDate: DateTime.tryParse(json['start_date'] as String? ?? ''),
      endDate: DateTime.tryParse(json['end_date'] as String? ?? ''),
      replacesMedicationId: json['replaces_medication_id'] as String?,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }
}

class MedicationEvent {
  const MedicationEvent({
    required this.type,
    required this.date,
    this.note,
    this.oldInstruction,
    this.newInstruction,
  });

  final String type;
  final DateTime date;
  final String? note;
  final Map<String, dynamic>? oldInstruction;
  final Map<String, dynamic>? newInstruction;

  factory MedicationEvent.fromJson(Map<String, dynamic> json) {
    return MedicationEvent(
      type: json['event_type'] as String,
      date: DateTime.parse(json['event_date'] as String),
      note: json['note'] as String?,
      oldInstruction: json['old_instruction'] as Map<String, dynamic>?,
      newInstruction: json['new_instruction'] as Map<String, dynamic>?,
    );
  }
}

String medicationGroupLabel(String sourceCategory) => switch (sourceCategory) {
  'prescribed' => '按医嘱用药',
  'supplement' => '自行补充',
  _ => '其他长期用药',
};
