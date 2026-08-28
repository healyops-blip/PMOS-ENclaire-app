import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/profile/presentation/profile_page.dart';

void main() {
  test('formats upcoming, due, and overdue visit states without negatives', () {
    final today = DateTime(2026, 8, 27);

    expect(nextVisitStatus(DateTime(2026, 9, 1), today: today), '还有 5 天');
    expect(nextVisitStatus(DateTime(2026, 8, 27), today: today), '已到复诊日期');
    expect(nextVisitStatus(DateTime(2026, 8, 25), today: today), '已超过 2 天');
  });

  test('strictly validates profile dates', () {
    expect(validateProfileDate(''), isNull);
    expect(validateProfileDate('2026-09-10'), isNull);
    expect(validateProfileDate('2026-02-30'), isNotNull);
    expect(validateProfileDate('09/10/2026'), isNotNull);
  });

  testWidgets('invalid edit stays open and a valid edit preserves onboarding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RecordingProfileRepository(
      PatientProfile(
        patientId: 'patient-profile-test',
        nickname: 'Pomi User',
        nextVisitDate: DateTime(2020, 1, 1),
        onboardingCompleted: true,
        updatedAt: DateTime(2026, 8, 27),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            account: DemoAccount.existingUser,
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已超过'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-edit-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-next-visit-input')),
      '2026-02-30',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pump();

    expect(find.text('请输入有效日期（YYYY-MM-DD）'), findsOneWidget);
    expect(find.text('编辑患者画像'), findsOneWidget);
    expect((await repository.get()).nextVisitDate, DateTime(2020, 1, 1));

    await tester.enterText(
      find.byKey(const Key('profile-next-visit-input')),
      '2026-09-10',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final saved = await repository.get();
    expect(saved.nextVisitDate, DateTime(2026, 9, 10));
    expect(saved.onboardingCompleted, isTrue);
    expect(repository.lastInput?.completeOnboarding, isFalse);
  });
}

class _RecordingProfileRepository implements PatientProfileRepository {
  _RecordingProfileRepository(this.profile);

  PatientProfile profile;
  PatientProfileInput? lastInput;

  @override
  Future<PatientProfile> get() async => profile;

  @override
  Future<PatientProfile> update(PatientProfileInput input) async {
    lastInput = input;
    profile = PatientProfile(
      patientId: profile.patientId,
      nickname: input.nickname,
      birthDate: input.birthDate,
      gender: input.gender,
      heightCm: input.heightCm,
      diagnosisYear: input.diagnosisYear,
      primaryCondition: input.primaryCondition,
      nextVisitDate: input.nextVisitDate,
      healthGoal: input.healthGoal,
      onboardingCompleted: profile.onboardingCompleted,
      updatedAt: profile.updatedAt.add(const Duration(seconds: 1)),
    );
    return profile;
  }
}
