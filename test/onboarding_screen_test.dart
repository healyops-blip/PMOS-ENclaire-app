import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/auth/onboarding_screen.dart';

void main() {
  testWidgets('Smoke onboarding starts with a complete demo preset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: OnboardingScreen(prefillDemo: true)),
      ),
    );

    expect(find.text('Smoke 演示信息已预填，可直接进入下一步'), findsOneWidget);
    final basicValues =
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .map((field) => field.controller?.text)
            .toList();
    expect(basicValues, containsAll(['Pomi', '1997', '2023', '165', '60']));

    await tester.tap(find.widgetWithText(FilledButton, '下一步'));
    await tester.pumpAndSettle();
    final cycleValues =
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .map((field) => field.controller?.text ?? '')
            .toList();
    expect(cycleValues.every((value) => value.isNotEmpty), isTrue);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '35-45 天'))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, '下一步'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '二甲双胍'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '维生素 D3'))
          .selected,
      isTrue,
    );
  });
}
