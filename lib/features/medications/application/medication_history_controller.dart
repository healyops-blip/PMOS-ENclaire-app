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
  int _generation = 0;
  bool _mutating = false;

  MedicationDailyHistory? get history => _history;
  bool get mutating => _mutating;

  Future<void> load() async {
    final generation = ++_generation;
    final history = await repository.listDailyHistory(medicationId);
    if (generation != _generation) return;
    _history = history;
    notifyListeners();
  }

  Future<void> setStatus(int index, MedicationStatus status) async {
    if (_mutating) {
      throw const MedicationFailure('用药状态正在保存，请稍候');
    }
    final previous = _history;
    if (previous == null) return;
    final record = previous.items[index];
    if (!record.editable) return;
    if (record.status == status) return;
    final generation = ++_generation;
    _mutating = true;
    _history = previous.replaceAt(index, record.copyWith(status: status));
    notifyListeners();
    try {
      await repository.setDailyStatus(medicationId, record.date, status);
    } catch (_) {
      if (generation == _generation) {
        _history = previous;
        notifyListeners();
      }
      _mutating = false;
      rethrow;
    }

    try {
      final refreshed = await repository.listDailyHistory(medicationId);
      if (generation == _generation) {
        _history = refreshed;
        notifyListeners();
      }
    } catch (_) {
      throw const MedicationFailure('状态已保存，但历史刷新失败，请重新打开每日记录');
    } finally {
      _mutating = false;
    }
  }
}
