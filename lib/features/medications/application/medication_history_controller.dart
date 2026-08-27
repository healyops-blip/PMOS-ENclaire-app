import 'package:flutter/foundation.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';
import 'package:pmos_enclaire/features/medications/domain/medication_daily_history.dart';

class MedicationHistoryController extends ChangeNotifier {
  MedicationHistoryController({
    required this.repository,
    required this.medicationId,
  });

  final MedicationRepository repository;
  final String medicationId;
  MedicationDailyHistory? _history;

  MedicationDailyHistory? get history => _history;

  Future<void> load() async {
    _history = await repository.listDailyHistory(medicationId);
    notifyListeners();
  }

  Future<void> setStatus(int index, MedicationStatus status) async {
    final previous = _history;
    if (previous == null) return;
    final record = previous.items[index];
    if (!record.editable) return;
    _history = previous.replaceAt(index, record.copyWith(status: status));
    notifyListeners();
    try {
      await repository.setDailyStatus(medicationId, record.date, status);
      _history = await repository.listDailyHistory(medicationId);
      notifyListeners();
    } catch (_) {
      _history = previous;
      notifyListeners();
      rethrow;
    }
  }
}
