import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/dashboard/presentation/dashboard_page.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

void main() {
  testWidgets('empty state validates, saves, edits, and refreshes dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = MemoryWeightRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: PomiTheme.light,
        home: DashboardPage(
          account: DemoAccount.existingUser,
          weightRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-经期')));
    await tester.pumpAndSettle();
    await _show(
      tester,
      find.byKey(const Key('record-weight-button')),
      const Key('cycle-page'),
    );
    await tester.tap(find.byKey(const Key('record-weight-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('weight-input')), '63.55');
    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pump();
    expect(find.text('最多保留一位小数'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weight-input')), '19.9');
    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pump();
    expect(find.text('体重需在 20.0–300.0 kg 之间'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weight-input')), '68.4');
    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pumpAndSettle();
    expect(find.text('体重已保存'), findsOneWidget);
    expect((await repository.listWeights()).single.weightKg, 68.4);

    await tester.tap(find.byKey(const Key('record-weight-button')));
    await tester.pumpAndSettle();
    expect(find.text('修改体重'), findsWidgets);
    await tester.enterText(find.byKey(const Key('weight-input')), '68.1');
    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pumpAndSettle();
    final records = await repository.listWeights();
    expect(records, hasLength(1));
    expect(records.single.weightKg, 68.1);

    await tester.tap(find.byKey(const Key('nav-首页')));
    await tester.pumpAndSettle();
    await _show(
      tester,
      find.byKey(const Key('dashboard-weight-summary')),
      const Key('dashboard-page'),
    );
    expect(find.byKey(const Key('dashboard-weight-value')), findsOneWidget);
    expect(find.text('68.1 kg'), findsOneWidget);
    expect(find.byKey(const Key('dashboard-weight-date')), findsOneWidget);
  });

  testWidgets('new patient sees an explicit weight empty state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: PomiTheme.light,
        home: DashboardPage(
          account: DemoAccount.newUser,
          weightRepository: MemoryWeightRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-经期')));
    await tester.pumpAndSettle();
    await _show(
      tester,
      find.byKey(const Key('weight-empty-state')),
      const Key('cycle-page'),
    );
    expect(find.text('还没有体重记录'), findsOneWidget);
  });
}

Future<void> _show(WidgetTester tester, Finder target, Key pageKey) async {
  final scrollable = find.descendant(
    of: find.byKey(pageKey),
    matching: find.byType(CustomScrollView),
  );
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollable.first, const Offset(0, -400));
    await tester.pump();
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}
