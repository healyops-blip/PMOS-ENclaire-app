import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/features/auth/onboarding_repository.dart';
import 'package:pmos_enclaire/features/medications/medication_repository.dart';

import 'support/fake_api_client.dart';

void main() {
  test(
    'parses an optional diagnosis year and saves the basic draft contract',
    () async {
      late ApiCall savedCall;
      final api = FakeApiClient(
        handler: (call) {
          if (call.method == 'GET') return _draft();
          savedCall = call;
          return _draft(currentStep: 'cycle');
        },
      );
      final repository = OnboardingRepository(api);

      final loaded = await repository.getDraft();
      expect(loaded.basic?.diagnosisYear, isNull);
      expect(loaded.basic?.birthYear, 1997);

      final updatedAt = DateTime.parse('2026-08-28T01:02:03Z');
      final saved = await repository.saveBasic(
        OnboardingBasicDraft(
          nickname: 'Pomi',
          birthYear: 1997,
          diagnosisYear: null,
          heightCm: 165.5,
          updatedAt: updatedAt,
        ),
      );

      expect(saved.currentStep, OnboardingStep.cycle);
      expect(savedCall.path, '/api/onboarding/steps/basic');
      expect(savedCall.data, {
        'nickname': 'Pomi',
        'birth_year': 1997,
        'diagnosis_year': null,
        'height_cm': 165.5,
        'weight_kg': null,
        'updated_at': updatedAt.toIso8601String(),
      });
    },
  );

  test(
    'saves and parses the usual period duration in the cycle step',
    () async {
      late ApiCall savedCall;
      final api = FakeApiClient(
        handler: (call) {
          savedCall = call;
          return _draft(
            currentStep: 'medications',
            cycle: {
              'last_menstrual_start_date': null,
              'usual_cycle_min_days': 35,
              'usual_cycle_max_days': 45,
              'period_duration_days': 5,
              'next_visit_date': null,
              'updated_at': null,
            },
          );
        },
      );

      final saved = await OnboardingRepository(api).saveCycle(
        const OnboardingCycleDraft(
          usualCycleMinDays: 35,
          usualCycleMaxDays: 45,
          periodDurationDays: 5,
        ),
      );

      expect(saved.cycle?.periodDurationDays, 5);
      expect(savedCall.path, '/api/onboarding/steps/cycle');
      expect((savedCall.data as Map)['period_duration_days'], 5);
    },
  );

  test(
    'complete sends the idempotency header and parses account plus profile',
    () async {
      late ApiCall call;
      final api = FakeApiClient(
        handler: (value) {
          call = value;
          return {
            'account': {
              'uid': 'uid-1',
              'account_name': 'alice',
              'onboarding_completed': true,
            },
            'profile': _profile(),
          };
        },
      );

      final result = await OnboardingRepository(
        api,
      ).complete(idempotencyKey: 'complete-001');

      expect(call.path, '/api/onboarding/complete');
      expect(call.headers, {'Idempotency-Key': 'complete-001'});
      expect(result.account.onboardingCompleted, isTrue);
      expect(result.profile.diagnosisYear, isNull);
    },
  );

  test('Smoke onboarding preserves the complete response contract', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final repository = OnboardingRepository(
      SmokeApiClient(const FlutterSecureStorage()),
    );

    final basic = await repository.saveBasic(
      const OnboardingBasicDraft(
        nickname: 'Pomi',
        birthYear: 1997,
        diagnosisYear: 2023,
        heightCm: 165,
        weightKg: 60,
      ),
    );
    expect(basic.currentStep, OnboardingStep.cycle);

    final cycle = await repository.saveCycle(
      const OnboardingCycleDraft(
        lastMenstrualStartDate: '2026-08-01',
        usualCycleMinDays: 35,
        usualCycleMaxDays: 45,
        nextVisitDate: '2026-09-01',
      ),
    );
    expect(cycle.currentStep, OnboardingStep.medications);

    final medications = await repository.saveMedications(
      const OnboardingMedicationsDraft(
        items: [
          OnboardingMedicationDraft(
            drugName: '二甲双胍',
            sourceCategory: MedicationSourceCategory.prescribed,
          ),
        ],
      ),
    );
    expect(medications.currentStep, OnboardingStep.complete);

    final completed = await repository.complete(
      idempotencyKey: 'smoke-onboarding-complete',
    );
    expect(completed.account.onboardingCompleted, isTrue);
    expect(completed.profile.onboardingCompleted, isTrue);
    expect(completed.profile.nickname, 'Pomi');
  });
}

Map<String, dynamic> _draft({
  String currentStep = 'basic',
  Map<String, dynamic>? cycle,
}) => {
  'id': 'draft-1',
  'current_step': currentStep,
  'basic': {
    'nickname': 'Pomi',
    'birth_year': 1997,
    'diagnosis_year': null,
    'height_cm': null,
    'weight_kg': null,
    'updated_at': null,
  },
  'cycle': cycle,
  'medications': null,
  'updated_at': '2026-08-28T01:02:03Z',
};

Map<String, dynamic> _profile() => {
  'id': 'patient-1',
  'nickname': 'Pomi',
  'birth_year': 1997,
  'diagnosis_year': null,
  'height_cm': null,
  'usual_cycle_min_days': null,
  'usual_cycle_max_days': null,
  'period_duration_days': null,
  'next_visit_date': null,
  'health_goal': null,
  'onboarding_completed': true,
  'created_at': '2026-08-28T01:02:03Z',
  'updated_at': '2026-08-28T01:02:03Z',
};
