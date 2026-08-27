import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';
import 'package:pmos_enclaire/features/medications/presentation/medication_page.dart';

void main() {
  testWidgets('seven-day history distinguishes editable and read-only dates', (
    tester,
  ) async {
    final repository = DemoMedicationRepository(const [
      _medication,
    ], () => DateTime(2026, 8, 27));
    await tester.pumpWidget(
      MaterialApp(
        home: MedicationPage(
          initialMedications: const [_medication],
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-medication-daily-history')));
    await tester.pumpAndSettle();

    expect(find.text('08-21 至 08-27 可修改；更早日期只读。'), findsOneWidget);
    expect(find.byKey(const Key('edit-daily-2026-08-27')), findsOneWidget);

    final readOnlyRow = find.byKey(const Key('daily-history-2026-08-20'));
    await tester.scrollUntilVisible(readOnlyRow, 120);
    expect(readOnlyRow, findsOneWidget);
    expect(
      find.descendant(of: readOnlyRow, matching: find.text('只读')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('edit-daily-2026-08-20')), findsNothing);
  });

  testWidgets('historical mutation refreshes the three-state summary', (
    tester,
  ) async {
    final repository = DemoMedicationRepository(const [
      _medication,
    ], () => DateTime(2026, 8, 27));
    await tester.pumpWidget(
      MaterialApp(
        home: MedicationPage(
          initialMedications: const [_medication],
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-medication-daily-history')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-daily-2026-08-27')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主动漏服').last);
    await tester.pumpAndSettle();

    expect(find.text('主动漏服 1'), findsOneWidget);
    expect(find.text('未记录 29'), findsOneWidget);
  });
}

const _medication = Medication(
  id: 'medication-1',
  name: 'Metformin',
  dose: '500 mg',
  group: '按医嘱用药',
  status: MedicationStatus.unrecorded,
  takenDays: 0,
  missedDays: 0,
);
