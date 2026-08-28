import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_record.dart';

class WeightController extends ChangeNotifier {
  WeightController(this._repository);

  final WeightRepository _repository;
  List<WeightRecord> _records = const [];
  bool _isLoading = false;
  String? _errorMessage;

  UnmodifiableListView<WeightRecord> get records =>
      UnmodifiableListView(_records);
  WeightRecord? get latest => _records.isEmpty ? null : _records.last;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _records = await _repository.listWeights();
      _records.sort((a, b) => a.recordDate.compareTo(b.recordDate));
    } on WeightRepositoryException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> save({
    required DateTime recordDate,
    required double weightKg,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      WeightRecord? existing;
      for (final record in _records) {
        if (_sameDate(record.recordDate, recordDate)) {
          existing = record;
          break;
        }
      }
      if (existing == null) {
        await _repository.createWeight(
          recordDate: recordDate,
          weightKg: weightKg,
        );
      } else {
        await _repository.updateWeight(
          id: existing.id,
          recordDate: recordDate,
          weightKg: weightKg,
        );
      }
      _records = await _repository.listWeights();
      _records.sort((a, b) => a.recordDate.compareTo(b.recordDate));
      return true;
    } on WeightRepositoryException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  static bool _sameDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
