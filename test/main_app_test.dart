import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/main.dart';

void main() {
  testWidgets('shows both fixed demo accounts on the login screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MainApp(authRepository: DemoAuthRepository()),
    );

    expect(find.byKey(const Key('login-page')), findsOneWidget);
    expect(find.text('新用户演示'), findsWidgets);
    expect(find.text('老用户演示'), findsWidgets);
    expect(find.textContaining('模拟医疗数据，不构成诊断或治疗建议'), findsOneWidget);
  });

  testWidgets('existing demo user opens the dashboard and updates medication', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MainApp(authRepository: DemoAuthRepository()),
    );

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

  testWidgets('dashboard uses an explicit action for active missed status', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await _loginExistingUser(tester);

    final status = find.byKey(const Key('medication-status-1'));
    await tester.longPress(status);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mark-medication-missed')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: status, matching: find.text('主动漏服')),
      findsOneWidget,
    );
  });

  testWidgets('uses account password login and registration without SMS', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(
      const MainApp(authRepository: DemoAuthRepository()),
    );

    expect(find.byKey(const Key('auth-identifier-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsOneWidget);
    expect(find.textContaining('不发送短信验证码'), findsOneWidget);

    await tester.tap(find.byKey(const Key('auth-register-tab')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('auth-register-account-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('auth-register-password-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('auth-register-confirm-field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('auth-register-phone-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('auth-register-account-field')),
      'pomi_created',
    );
    await tester.enterText(
      find.byKey(const Key('auth-register-password-field')),
      'Pomi2026!',
    );
    await tester.enterText(
      find.byKey(const Key('auth-register-confirm-field')),
      'Pomi2026!',
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

    await tester.pumpWidget(
      const MainApp(authRepository: DemoAuthRepository()),
    );
    await tester.tap(find.byKey(const Key('account-preset-new-user')));
    await tester.tap(find.byKey(const Key('demo-login-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding-page')), findsOneWidget);
    expect(find.text('基本信息'), findsOneWidget);

    for (var step = 0; step < 4; step++) {
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
    expect(find.text('医院认证演示'), findsWidgets);
    expect(find.textContaining('KYC'), findsNothing);
    expect(find.textContaining('交易哈希'), findsNothing);

    await tester.tap(find.byKey(const Key('advance-certification-button')));
    await tester.pump();
    expect(find.text('认证处理中…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('演示认证成功'), findsOneWidget);
    expect(find.text('演示认证'), findsOneWidget);
  });

  testWidgets(
    'document upload requires preview and external-processing consent',
    (tester) async {
      _setPhoneViewport(tester);
      await _loginExistingUser(tester);

      await tester.tap(find.byKey(const Key('upload-button')));
      await tester.pumpAndSettle();
      expect(find.text('选择材料类型'), findsOneWidget);
      expect(find.text('化验／检测'), findsOneWidget);
      expect(find.text('医嘱／处方'), findsOneWidget);
      expect(find.text('影像文字报告'), findsOneWidget);
      expect(find.text('门诊病历／就诊记录'), findsOneWidget);

      await tester.tap(find.byKey(const Key('material-type-prescription')));
      await tester.pumpAndSettle();
      expect(find.text('上传医嘱'), findsOneWidget);

      await tester.tap(find.byKey(const Key('upload-demo-option')));
      await tester.pumpAndSettle();
      expect(find.text('确认材料预览'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-document-preview')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-external-ocr')));
      await tester.pumpAndSettle();
      expect(find.text('医嘱已安全保存，可在材料列表查看'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-记录')));
      await tester.pumpAndSettle();
      expect(find.text('pomi-demo-material.png'), findsOneWidget);
    },
  );

  testWidgets('declining external processing creates no upload request', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final repository = _UploadCountingDocumentRepository();
    await tester.pumpWidget(
      MainApp(
        authRepository: const DemoAuthRepository(),
        documentRepository: repository,
      ),
    );
    await tester.tap(find.byKey(const Key('demo-login-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('upload-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('material-type-laboratory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload-demo-option')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-document-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decline-external-ocr')));
    await tester.pumpAndSettle();

    expect(repository.uploadRequests, 0);
    expect(find.byKey(const Key('document-upload-progress')), findsNothing);
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

    await tester.tap(find.byKey(const Key('report-pdf-menu')));
    await tester.pumpAndSettle();
    expect(find.text('保存 PDF'), findsOneWidget);
    expect(find.text('分享 PDF'), findsOneWidget);
    expect(find.text('打印 PDF'), findsOneWidget);
    await tester.tapAt(const Offset(12, 180));
    await tester.pumpAndSettle();

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
  await tester.pumpWidget(const MainApp(authRepository: DemoAuthRepository()));
  await tester.tap(find.byKey(const Key('demo-login-button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
}

class _UploadCountingDocumentRepository extends DemoDocumentRepository {
  int uploadRequests = 0;

  @override
  Future<MedicalDocument> upload({
    required SelectedDocumentFile file,
    required String documentType,
    required String consentVersion,
    required String idempotencyKey,
    required void Function(int sent, int total) onProgress,
  }) {
    uploadRequests++;
    return super.upload(
      file: file,
      documentType: documentType,
      consentVersion: consentVersion,
      idempotencyKey: idempotencyKey,
      onProgress: onProgress,
    );
  }
}
