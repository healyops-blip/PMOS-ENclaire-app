import 'package:flutter/foundation.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';

class MedicationStatusController extends ChangeNotifier {
  MedicationStatusController({
    required this.gateway,
    required List<Medication> medications,
    DateTime Function()? now,
  }) : _medications = [...medications],
       _now = now ?? DateTime.now;

  final MedicationDailyGateway gateway;
  final DateTime Function() _now;
  List<Medication> _medications;

  List<Medication> get medications => List.unmodifiable(_medications);

  void replaceMedications(List<Medication> medications) {
    _medications = [...medications];
    notifyListeners();
  }

  Future<void> setStatus(int index, MedicationStatus status) async {
    final previous = _medications[index];
    _medications = [..._medications]
      ..[index] = previous.copyWith(status: status);
    notifyListeners();
    try {
      await gateway.setDailyStatus(previous.id, _now(), status);
    } catch (_) {
      _medications = [..._medications]..[index] = previous;
      notifyListeners();
      rethrow;
    }
  }
}
