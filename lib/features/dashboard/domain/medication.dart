enum MedicationStatus { taken, missed, unrecorded }

class Medication {
  const Medication({
    required this.name,
    required this.dose,
    required this.group,
    required this.status,
    required this.takenDays,
    required this.missedDays,
  });

  final String name;
  final String dose;
  final String group;
  final MedicationStatus status;
  final int takenDays;
  final int missedDays;

  Medication copyWith({MedicationStatus? status}) {
    return Medication(
      name: name,
      dose: dose,
      group: group,
      status: status ?? this.status,
      takenDays: takenDays,
      missedDays: missedDays,
    );
  }
}
