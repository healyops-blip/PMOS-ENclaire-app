import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/application/medication_history_controller.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';
import 'package:pmos_enclaire/features/medications/domain/medication_daily_history.dart';

void main() {
  test('historical status is optimistic and refreshes after success', () async {
    final repository = _ControlledHistoryRepository();
    final controller = MedicationHistoryController(
      repository: repository,
      medicationId: 'medication-1',
    );
    await controller.load();

    final mutation = controller.setStatus(0, MedicationStatus.taken);
    expect(controller.history!.items[0].status, MedicationStatus.taken);
    expect(repository.date, DateTime(2026, 8, 25));

    repository.succeed(MedicationStatus.taken);
    await mutation;
    expect(controller.history!.items[0].status, MedicationStatus.taken);
  });

  test('failed historical mutation rolls the optimistic state back', () async {
    final repository = _ControlledHistoryRepository();
    final controller = MedicationHistoryController(
      repository: repository,
      medicationId: 'medication-1',
    );
    await controller.load();

    final mutation = controller.setStatus(0, MedicationStatus.missed);
    expect(controller.history!.items[0].status, MedicationStatus.missed);

    repository.fail(const MedicationFailure('server unavailable'));
    await expectLater(mutation, throwsA(isA<MedicationFailure>()));
    expect(controller.history!.items[0].status, MedicationStatus.unrecorded);
  });

  test('read-only history does not call the write gateway', () async {
    final repository = _ControlledHistoryRepository();
    final controller = MedicationHistoryController(
      repository: repository,
      medicationId: 'medication-1',
    );
    await controller.load();

    await controller.setStatus(1, MedicationStatus.taken);

    expect(repository.calls, 0);
    expect(controller.history!.items[1].status, MedicationStatus.unrecorded);
  });
}

class _ControlledHistoryRepository extends DemoMedicationRepository {
  _ControlledHistoryRepository()
    : super(const [
        Medication(
          id: 'medication-1',
          name: 'Metformin',
          dose: '500 mg',
          group: '按医嘱用药',
          status: MedicationStatus.unrecorded,
          takenDays: 0,
          missedDays: 0,
        ),
      ]);

  final Completer<void> _result = Completer<void>();
  MedicationStatus _savedStatus = MedicationStatus.unrecorded;
  int calls = 0;
  DateTime? date;

  @override
  Future<MedicationDailyHistory> listDailyHistory(
    String medicationId, {
    int days = 30,
  }) async => MedicationDailyHistory(
    businessDate: DateTime(2026, 8, 27),
    editableFrom: DateTime(2026, 8, 21),
    items: [
      MedicationDailyRecord(
        medicationId: medicationId,
        date: DateTime(2026, 8, 25),
        status: _savedStatus,
        editable: true,
      ),
      MedicationDailyRecord(
        medicationId: medicationId,
        date: DateTime(2026, 8, 20),
        status: MedicationStatus.unrecorded,
        editable: false,
      ),
    ],
    takenCount: _savedStatus == MedicationStatus.taken ? 1 : 0,
    missedCount: _savedStatus == MedicationStatus.missed ? 1 : 0,
    unrecordedCount: _savedStatus == MedicationStatus.unrecorded ? 2 : 1,
  );

  @override
  Future<void> setDailyStatus(
    String medicationId,
    DateTime date,
    MedicationStatus status,
  ) {
    calls += 1;
    this.date = date;
    return _result.future;
  }

  void succeed(MedicationStatus status) {
    _savedStatus = status;
    _result.complete();
  }

  void fail(Object error) => _result.completeError(error);
}
