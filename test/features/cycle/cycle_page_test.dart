import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/cycle/data/cycle_repository.dart';
import 'package:pmos_enclaire/features/cycle/domain/menstrual_cycle.dart';
import 'package:pmos_enclaire/features/cycle/presentation/cycle_page.dart';

void main() {
  testWidgets('shows loading and empty history states without prediction', (
    tester,
  ) async {
    final gate = Completer<List<MenstrualCycle>>();
    final repository = _FakeCycleRepository(listGate: gate);

    await _pumpPage(tester, repository);
    expect(find.byKey(const Key('cycle-loading-state')), findsOneWidget);

    gate.complete([]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-empty-state')), findsOneWidget);
    expect(find.textContaining('结束日期可以稍后补录'), findsOneWidget);
    expect(find.textContaining('预测'), findsNothing);
  });

  testWidgets('shows failure state and retries loading', (tester) async {
    final repository = _FakeCycleRepository(failuresRemaining: 1);
    await _pumpPage(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cycle-error-state')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-cycle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cycle-empty-state')), findsOneWidget);
    expect(repository.listCalls, 2);
  });

  testWidgets('renders calendar, current record, trend, and history', (
    tester,
  ) async {
    final repository = _FakeCycleRepository(
      records: [
        _cycle('current', DateTime(2026, 8, 1), null, cycleLength: 29),
        _cycle('older', DateTime(2026, 7, 3), DateTime(2026, 7, 7)),
      ],
    );
    await _pumpPage(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cycle-calendar')), findsOneWidget);
    expect(find.byKey(const Key('ongoing-cycle-card')), findsOneWidget);
    expect(find.byKey(const Key('cycle-trend-success')), findsOneWidget);
    expect(find.byKey(const Key('cycle-record-current')), findsOneWidget);
    expect(find.textContaining('预测'), findsNothing);
  });

  testWidgets('uses Material system date picker and creates an open record', (
    tester,
  ) async {
    final repository = _FakeCycleRepository();
    await _pumpPage(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-cycle-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-editor-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cycle-start-date-button')));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.text('选择开始日期'), findsOneWidget);
    await tester.tap(find.text('取消选择'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-cycle-button')));
    await tester.pumpAndSettle();

    expect(repository.createdDraft?.endDate, isNull);
    expect(find.byKey(const Key('ongoing-cycle-card')), findsOneWidget);
  });

  testWidgets('confirms deletion and refreshes history', (tester) async {
    final repository = _FakeCycleRepository(
      records: [
        _cycle('remove-me', DateTime(2026, 6, 1), DateTime(2026, 6, 5)),
      ],
    );
    await _pumpPage(tester, repository);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('delete-cycle-remove-me')));
    await tester.tap(find.byKey(const Key('delete-cycle-remove-me')));
    await tester.pumpAndSettle();
    expect(find.text('删除这条经期记录？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-delete-cycle')));
    await tester.pumpAndSettle();

    expect(repository.deletedIds, ['remove-me']);
    expect(find.byKey(const Key('cycle-empty-state')), findsOneWidget);
  });

  testWidgets('keeps the editor draft open when saving fails', (tester) async {
    final repository = _FakeCycleRepository(mutationFailuresRemaining: 1);
    await _pumpPage(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-cycle-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cycle-note-field')), '保留输入');
    await tester.tap(find.byKey(const Key('save-cycle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cycle-editor-dialog')), findsOneWidget);
    expect(find.byKey(const Key('cycle-editor-error')), findsOneWidget);
    expect(find.text('保留输入'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-cycle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cycle-editor-dialog')), findsNothing);
    expect(repository.createdDraft?.note, '保留输入');
    expect(find.byKey(const Key('ongoing-cycle-card')), findsOneWidget);
  });

  test(
    'demo repository recalculates adjacent cycle lengths after editing',
    () async {
      final repository = DemoCycleRepository();

      final updated = await repository.update(
        'demo-2',
        CycleDraft(startDate: DateTime(2026, 7), endDate: DateTime(2026, 7, 5)),
      );
      final cycles = await repository.list();

      expect(updated.cycleLengthDays, 23);
      expect(
        cycles.singleWhere((cycle) => cycle.id == 'demo-3').cycleLengthDays,
        36,
      );
      expect(
        cycles.singleWhere((cycle) => cycle.id == 'demo-1').cycleLengthDays,
        isNull,
      );
    },
  );
}

Future<void> _pumpPage(WidgetTester tester, CycleRepository repository) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CyclePage(repository: repository)),
    ),
  );
}

MenstrualCycle _cycle(
  String id,
  DateTime start,
  DateTime? end, {
  int? cycleLength,
}) {
  return MenstrualCycle(
    id: id,
    startDate: start,
    endDate: end,
    cycleLengthDays: cycleLength,
    durationDays: end == null ? null : end.difference(start).inDays + 1,
    createdAt: start,
    updatedAt: end ?? start,
  );
}

class _FakeCycleRepository implements CycleRepository {
  _FakeCycleRepository({
    List<MenstrualCycle>? records,
    this.listGate,
    this.failuresRemaining = 0,
    this.mutationFailuresRemaining = 0,
  }) : records = [...?records];

  final List<MenstrualCycle> records;
  final Completer<List<MenstrualCycle>>? listGate;
  int failuresRemaining;
  int mutationFailuresRemaining;
  int listCalls = 0;
  CycleDraft? createdDraft;
  final List<String> deletedIds = [];

  @override
  Future<List<MenstrualCycle>> list() async {
    listCalls += 1;
    if (listGate != null && listCalls == 1) return listGate!.future;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const CycleRepositoryException('网络暂时不可用');
    }
    return List.unmodifiable(records);
  }

  @override
  Future<MenstrualCycle> create(CycleDraft draft) async {
    if (mutationFailuresRemaining > 0) {
      mutationFailuresRemaining -= 1;
      throw const CycleRepositoryException('保存失败，请重试');
    }
    createdDraft = draft;
    final value = _cycle('created', draft.startDate, draft.endDate);
    records.insert(0, value);
    return value;
  }

  @override
  Future<MenstrualCycle> update(String id, CycleDraft draft) async {
    if (mutationFailuresRemaining > 0) {
      mutationFailuresRemaining -= 1;
      throw const CycleRepositoryException('保存失败，请重试');
    }
    final value = _cycle(id, draft.startDate, draft.endDate);
    records[records.indexWhere((item) => item.id == id)] = value;
    return value;
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    records.removeWhere((item) => item.id == id);
  }
}
