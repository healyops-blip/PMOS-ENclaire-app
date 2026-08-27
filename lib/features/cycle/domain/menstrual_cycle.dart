class MenstrualCycle {
  const MenstrualCycle({
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

  factory MenstrualCycle.fromJson(Map<String, dynamic> json) {
    return MenstrualCycle(
      id: json['id'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      flowLevel: json['flow_level'] as String?,
      note: json['note'] as String?,
      cycleLengthDays: json['cycle_length_days'] as int?,
      durationDays: json['duration_days'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final DateTime startDate;
  final DateTime? endDate;
  final String? flowLevel;
  final String? note;
  final int? cycleLengthDays;
  final int? durationDays;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool contains(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final rawEnd = endDate;
    final end = rawEnd == null
        ? DateTime.now()
        : DateTime(rawEnd.year, rawEnd.month, rawEnd.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

class CycleDraft {
  const CycleDraft({
    required this.startDate,
    this.endDate,
    this.flowLevel,
    this.note,
    this.updatedAt,
  });

  final DateTime startDate;
  final DateTime? endDate;
  final String? flowLevel;
  final String? note;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'start_date': _date(startDate),
    'end_date': endDate == null ? null : _date(endDate!),
    'flow_level': flowLevel,
    'note': note,
    'source_type': 'manual',
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };

  static String _date(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
