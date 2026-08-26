import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/main.dart';

void main() {
  testWidgets('shows both fixed demo accounts on the login screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());

    expect(find.byKey(const Key('login-page')), findsOneWidget);
    expect(find.text('新用户演示'), findsWidgets);
    expect(find.text('老用户演示'), findsWidgets);
    expect(find.textContaining('模拟医疗数据，不构成诊断或治疗建议'), findsOneWidget);
  });

  testWidgets('existing demo user opens the dashboard and updates medication', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());

    final loginButton = find.byKey(const Key('demo-login-button'));
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.text('模拟患者 · 林晓晴'), findsOneWidget);
    expect(find.text('今日用药'), findsOneWidget);
    final secondMedicationStatus = find.byKey(const Key('medication-status-1'));
    expect(
      find.descendant(of: secondMedicationStatus, matching: find.text('未记录')),
      findsOneWidget,
    );

    await tester.tap(secondMedicationStatus);
    await tester.pump();

    expect(
      find.descendant(of: secondMedicationStatus, matching: find.text('未记录')),
      findsNothing,
    );
    expect(
      find.descendant(of: secondMedicationStatus, matching: find.text('已服用')),
      findsOneWidget,
    );
  });

  testWidgets('switches between password code login and phone registration', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const MainApp());

    expect(find.byKey(const Key('auth-identifier-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('auth-code-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-code-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsNothing);

    await tester.tap(find.byKey(const Key('auth-register-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-phone-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-register-code-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('auth-phone-field')),
      '13800005678',
    );
    await tester.enterText(
      find.byKey(const Key('auth-register-code-field')),
      '2026',
    );
    final registerButton = find.byKey(const Key('demo-login-button'));
    await tester.ensureVisible(registerButton);
    await tester.tap(registerButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
  });

  testWidgets('new demo user completes onboarding before the dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MainApp());
    await tester.tap(find.byKey(const Key('account-demo-new-user')));
    await tester.tap(find.byKey(const Key('demo-login-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(find.text('基本信息'), findsOneWidget);

    for (var step = 0; step < 3; step++) {
      final next = find.byKey(const Key('onboarding-next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.text('模拟患者 · 林晓晴'), findsOneWidget);
  });

  testWidgets('main navigation opens cycle records and profile pages', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await _loginExistingUser(tester);

    await tester.tap(find.byKey(const Key('nav-经期')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-记录')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('records-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-我的')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('certification-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('certification-page')), findsOneWidget);
  });

  testWidgets('upload flow reaches OCR confirmation and reconciliation', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await _loginExistingUser(tester);

    await tester.tap(find.byKey(const Key('upload-button')));
    await tester.pumpAndSettle();
    expect(find.text('上传就诊记录'), findsOneWidget);

    await tester.tap(find.byKey(const Key('upload-camera-option')));
    await tester.pumpAndSettle();
    expect(find.text('识别完成'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ocr-review-button')));
    await tester.pumpAndSettle();
    expect(find.text('待确认草稿 · 化验单'), findsOneWidget);

    final confirmOcr = find.byKey(const Key('confirm-ocr-button'));
    await tester.ensureVisible(confirmOcr);
    await tester.tap(confirmOcr);
    await tester.pumpAndSettle();
    expect(find.text('用药对账'), findsOneWidget);

    final confirmReconciliation = find.byKey(
      const Key('confirm-reconciliation-button'),
    );
    await tester.ensureVisible(confirmReconciliation);
    await tester.tap(confirmReconciliation);
    await tester.pumpAndSettle();
    expect(find.text('材料已确认，用药清单已更新'), findsOneWidget);
  });

  testWidgets('dashboard generates the three-layer report UI', (tester) async {
    _setPhoneViewport(tester);
    await _loginExistingUser(tester);

    final reportEntry = find.byKey(const Key('report-cta'));
    await tester.ensureVisible(reportEntry);
    await tester.tap(reportEntry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-generator-page')), findsOneWidget);

    final generate = find.byKey(const Key('generate-report-button'));
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-page')), findsOneWidget);
    expect(find.text('1 · 摘要'), findsOneWidget);
    expect(find.text('2 · 趋势'), findsOneWidget);
    expect(find.text('3 · 来源'), findsOneWidget);

    await tester.tap(find.text('2 · 趋势'));
    await tester.pumpAndSettle();
    expect(find.text('空腹血糖 · 完整趋势'), findsOneWidget);

    final sourceButton = find.byKey(const Key('view-report-source-button'));
    await tester.ensureVisible(sourceButton);
    await tester.tap(sourceButton);
    await tester.pumpAndSettle();
    expect(find.text('原始化验单预览 · 模拟材料'), findsOneWidget);
  });
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _loginExistingUser(WidgetTester tester) async {
  await tester.pumpWidget(const MainApp());
  await tester.tap(find.byKey(const Key('demo-login-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
}
