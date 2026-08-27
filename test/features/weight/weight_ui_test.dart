import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/app/pomi_app.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/auth/data/auth_repository.dart';
import 'package:pmos_enclaire/features/auth/domain/account.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/dashboard/presentation/dashboard_page.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/weight/application/weight_controller.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_record.dart';
import 'package:pmos_enclaire/features/cycle/presentation/cycle_page.dart';

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
          profileRepository: DemoPatientProfileRepository(),
          documentRepository: DemoDocumentRepository(),
          patientNoteRepository: DemoPatientNoteRepository(),
          weightRepository: repository,
          now: () => DateTime(2031, 2, 18),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-经期')));
    await tester.pumpAndSettle();
    expect(find.text('2031 年 2 月'), findsOneWidget);
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
          profileRepository: DemoPatientProfileRepository(),
          documentRepository: DemoDocumentRepository(),
          patientNoteRepository: DemoPatientNoteRepository(),
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

  testWidgets('save failure keeps the weight value and permits retry', (
    tester,
  ) async {
    final repository = _ControlledWeightRepository()..failNextSave = true;
    final controller = WeightController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: PomiTheme.light,
        home: Scaffold(
          body: CyclePage(
            weightController: controller,
            now: () => DateTime(2032, 4, 9),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _show(
      tester,
      find.byKey(const Key('record-weight-button')),
      const Key('cycle-page'),
    );
    await tester.tap(find.byKey(const Key('record-weight-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weight-input')), '68.4');
    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('weight-input')), findsOneWidget);
    expect(find.text('模拟保存失败'), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('weight-input')))
          .controller
          ?.text,
      '68.4',
    );

    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weight-input')), findsNothing);
    expect((await repository.listWeights()).single.weightKg, 68.4);
  });

  testWidgets('marks retained records stale when a refresh fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ControlledWeightRepository(
      records: [
        WeightRecord(
          id: 'existing',
          recordDate: DateTime(2030, 1, 2),
          weightKg: 66.2,
          createdAt: DateTime(2030, 1, 2),
          updatedAt: DateTime(2030, 1, 2),
        ),
      ],
    );
    final controller = WeightController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: PomiTheme.light,
        home: Scaffold(
          body: CyclePage(
            weightController: controller,
            now: () => DateTime(2032, 4, 9),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.failNextLoad = true;
    await controller.load();
    expect(controller.errorMessage, '模拟同步失败');
    await tester.pumpAndSettle();
    await _show(
      tester,
      find.byKey(const Key('weight-stale-warning')),
      const Key('cycle-page'),
    );

    expect(find.byKey(const Key('weight-stale-warning')), findsOneWidget);
    expect(find.textContaining('上次同步的数据'), findsOneWidget);
    expect(find.text('66.2 kg'), findsOneWidget);
  });

  testWidgets('production app wiring uses API GET, POST, and PUT', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <String>[];
    Map<String, dynamic>? serverRecord;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add('${options.method} ${options.path}');
          final body = switch ((options.method, options.path)) {
            ('GET', '/weights') =>
              serverRecord == null ? <Map<String, dynamic>>[] : [serverRecord!],
            ('POST', '/weights') => serverRecord = _apiRecord(
              options.data as Map<String, dynamic>,
            ),
            ('PUT', '/weights/api-weight') => serverRecord = _apiRecord(
              options.data as Map<String, dynamic>,
            ),
            _ => throw StateError(
              'Unexpected request: ${options.method} ${options.path}',
            ),
          };
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: {'data': body},
              statusCode: 200,
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(
      PomiApp(
        authRepository: const _RestoringAuthRepository(),
        profileRepository: DemoPatientProfileRepository(),
        apiClient: PomiApiClient(dio: dio),
        now: () => DateTime(2031, 2, 18),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-经期')));
    await tester.pumpAndSettle();
    await _show(
      tester,
      find.byKey(const Key('record-weight-button')),
      const Key('cycle-page'),
    );
    await tester.tap(find.byKey(const Key('record-weight-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weight-input')), '68.4');
    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('record-weight-button')));
    await tester.tap(find.byKey(const Key('record-weight-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weight-input')), '68.1');
    await tester.tap(find.byKey(const Key('save-weight-button')));
    await tester.pumpAndSettle();

    expect(
      requests,
      containsAllInOrder([
        'GET /weights',
        'POST /weights',
        'GET /weights',
        'PUT /weights/api-weight',
        'GET /weights',
      ]),
    );
    expect(serverRecord?['weight_kg'], 68.1);
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

class _ControlledWeightRepository extends MemoryWeightRepository {
  _ControlledWeightRepository({super.records});

  bool failNextLoad = false;
  bool failNextSave = false;

  @override
  Future<List<WeightRecord>> listWeights({DateTime? from, DateTime? to}) {
    if (failNextLoad) {
      failNextLoad = false;
      throw const WeightRepositoryException('模拟同步失败');
    }
    return super.listWeights(from: from, to: to);
  }

  @override
  Future<WeightRecord> createWeight({
    required DateTime recordDate,
    required double weightKg,
  }) {
    if (failNextSave) {
      failNextSave = false;
      throw const WeightRepositoryException('模拟保存失败');
    }
    return super.createWeight(recordDate: recordDate, weightKg: weightKg);
  }

  @override
  Future<WeightRecord> updateWeight({
    required String id,
    required DateTime recordDate,
    required double weightKg,
  }) {
    if (failNextSave) {
      failNextSave = false;
      throw const WeightRepositoryException('模拟保存失败');
    }
    return super.updateWeight(
      id: id,
      recordDate: recordDate,
      weightKg: weightKg,
    );
  }
}

Map<String, dynamic> _apiRecord(Map<String, dynamic> body) => {
  'id': 'api-weight',
  'record_date': body['record_date'],
  'weight_kg': body['weight_kg'],
  'created_at': '2031-02-18T12:00:00Z',
  'updated_at': '2031-02-18T12:00:00Z',
};

class _RestoringAuthRepository implements AuthRepository {
  const _RestoringAuthRepository();

  @override
  Future<Account?> restore() async => const Account(
    uid: 'real-user',
    accountName: 'real-user',
    accountType: 'user',
    onboardingCompleted: true,
    status: 'active',
    phoneVerified: false,
  );

  @override
  Future<AuthSession> login({
    required String accountName,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> register({
    required String accountName,
    required String password,
    String? phoneNumber,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}
}
