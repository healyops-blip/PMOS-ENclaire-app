class WeightRecord {
  const WeightRecord({
    required this.id,
    required this.recordDate,
    required this.weightKg,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WeightRecord.fromJson(Map<String, dynamic> json) {
    return WeightRecord(
      id: json['id'] as String,
      recordDate: DateTime.parse(json['record_date'] as String),
      weightKg: (json['weight_kg'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final DateTime recordDate;
  final double weightKg;
  final DateTime createdAt;
  final DateTime updatedAt;
}
