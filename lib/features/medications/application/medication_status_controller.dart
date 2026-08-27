import 'package:flutter/foundation.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';

class MedicationStatusController extends ChangeNotifier {
  MedicationStatusController({
    required this.gateway,
    required List<Medication> medications,
    Future<DateTime> Function()? businessDate,
  }) : _medications = [...medications],
       _businessDate = businessDate ?? gateway.businessDate;

  final MedicationDailyGateway gateway;
  final Future<DateTime> Function() _businessDate;
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
      final date = await _businessDate();
      await gateway.setDailyStatus(previous.id, date, status);
    } catch (_) {
      _medications = [..._medications]..[index] = previous;
      notifyListeners();
      rethrow;
    }
  }
}
