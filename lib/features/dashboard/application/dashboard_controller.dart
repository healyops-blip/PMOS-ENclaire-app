import 'package:flutter/foundation.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_repository.dart';
import 'package:pmos_enclaire/features/dashboard/domain/dashboard_snapshot.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({required this.repository, required this.uid});

  final DashboardRepository repository;
  final String uid;
  DashboardSnapshot? snapshot;
  bool loading = false;
  bool offline = false;
  DateTime? updatedAt;
  Object? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.load(uid);
      snapshot = result.snapshot;
      offline = result.offline;
      updatedAt = result.updatedAt;
    } catch (caught) {
      error = caught;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
