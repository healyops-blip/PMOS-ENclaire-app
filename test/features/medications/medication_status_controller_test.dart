import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/application/medication_status_controller.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';

void main() {
  const medication = Medication(
    id: 'medication-1',
    name: 'Metformin',
    dose: '500 mg',
    group: '按医嘱用药',
    status: MedicationStatus.unrecorded,
    takenDays: 0,
    missedDays: 0,
  );

  test('optimistically updates then keeps state after API success', () async {
    final gateway = _ControlledGateway();
    final controller = MedicationStatusController(
      gateway: gateway,
      medications: const [medication],
      businessDate: () async => DateTime(2026, 8, 27),
    );

    final future = controller.setStatus(0, MedicationStatus.taken);
    expect(controller.medications.single.status, MedicationStatus.taken);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.medicationId, 'medication-1');
    expect(gateway.date, DateTime(2026, 8, 27));

    gateway.complete();
    await future;
    expect(controller.medications.single.status, MedicationStatus.taken);
  });

  test('rolls optimistic state back and surfaces the API failure', () async {
    final gateway = _ControlledGateway();
    final controller = MedicationStatusController(
      gateway: gateway,
      medications: const [medication],
    );

    final future = controller.setStatus(0, MedicationStatus.missed);
    expect(controller.medications.single.status, MedicationStatus.missed);

    gateway.fail(const MedicationFailure('server unavailable'));
    await expectLater(future, throwsA(isA<MedicationFailure>()));
    expect(controller.medications.single.status, MedicationStatus.unrecorded);
  });
}

class _ControlledGateway implements MedicationDailyGateway {
  final _result = Completer<void>();
  String? medicationId;
  DateTime? date;

  @override
  Future<DateTime> businessDate() async => DateTime(2026, 8, 27);

  @override
  Future<void> setDailyStatus(
    String medicationId,
    DateTime date,
    MedicationStatus status,
  ) {
    this.medicationId = medicationId;
    this.date = date;
    return _result.future;
  }

  void complete() => _result.complete();

  void fail(Object error) => _result.completeError(error);
}
