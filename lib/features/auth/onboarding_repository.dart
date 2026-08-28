import '../../core/api_client.dart';
import '../../core/json_value.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../medications/medication_repository.dart';
import '../profile/patient_repository.dart';
import 'auth_controller.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(ref.watch(apiClientProvider)),
);

enum OnboardingStep {
  basic('basic'),
  cycle('cycle'),
  medications('medications'),
  complete('complete');

  const OnboardingStep(this.wireValue);
  final String wireValue;

  static OnboardingStep parse(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse:
        () => throw ApiFailure('INVALID_RESPONSE', '服务返回了未知的 onboarding 步骤'),
  );
}

class OnboardingBasicDraft {
  const OnboardingBasicDraft({
    required this.nickname,
    required this.birthYear,
    this.diagnosisYear,
    this.heightCm,
    this.weightKg,
    this.updatedAt,
  });

  factory OnboardingBasicDraft.fromJson(dynamic value) {
    final json = jsonObject(value, 'onboarding basic step');
    return OnboardingBasicDraft(
      nickname: jsonString(json, 'nickname'),
      birthYear: jsonInt(json, 'birth_year'),
      diagnosisYear: jsonIntOrNull(json, 'diagnosis_year'),
      heightCm: jsonDoubleOrNull(json, 'height_cm'),
      weightKg: jsonDoubleOrNull(json, 'weight_kg'),
      updatedAt: jsonDateTimeOrNull(json, 'updated_at'),
    );
  }

  final String nickname;
  final int birthYear;
  final int? diagnosisYear;
  final double? heightCm;
  final double? weightKg;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'birth_year': birthYear,
    'diagnosis_year': diagnosisYear,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };
}

class OnboardingCycleDraft {
  const OnboardingCycleDraft({
    this.lastMenstrualStartDate,
    this.usualCycleMinDays,
    this.usualCycleMaxDays,
    this.nextVisitDate,
    this.updatedAt,
  });

  factory OnboardingCycleDraft.fromJson(dynamic value) {
    final json = jsonObject(value, 'onboarding cycle step');
    return OnboardingCycleDraft(
      lastMenstrualStartDate: jsonStringOrNull(
        json,
        'last_menstrual_start_date',
      ),
      usualCycleMinDays: jsonIntOrNull(json, 'usual_cycle_min_days'),
      usualCycleMaxDays: jsonIntOrNull(json, 'usual_cycle_max_days'),
      nextVisitDate: jsonStringOrNull(json, 'next_visit_date'),
      updatedAt: jsonDateTimeOrNull(json, 'updated_at'),
    );
  }

  final String? lastMenstrualStartDate;
  final int? usualCycleMinDays;
  final int? usualCycleMaxDays;
  final String? nextVisitDate;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'last_menstrual_start_date': lastMenstrualStartDate,
    'usual_cycle_min_days': usualCycleMinDays,
    'usual_cycle_max_days': usualCycleMaxDays,
    'next_visit_date': nextVisitDate,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };
}

class OnboardingMedicationDraft {
  const OnboardingMedicationDraft({
    required this.drugName,
    required this.sourceCategory,
    this.catalogId,
    this.startDate,
  });

  factory OnboardingMedicationDraft.fromJson(dynamic value) {
    final json = jsonObject(value, 'onboarding medication');
    return OnboardingMedicationDraft(
      catalogId: jsonStringOrNull(json, 'catalog_id'),
      drugName: jsonString(json, 'drug_name'),
      sourceCategory: MedicationSourceCategory.parse(
        jsonString(json, 'source_category'),
      ),
      startDate: jsonStringOrNull(json, 'start_date'),
    );
  }

  final String? catalogId;
  final String drugName;
  final MedicationSourceCategory sourceCategory;
  final String? startDate;

  Map<String, dynamic> toJson() => {
    'catalog_id': catalogId,
    'drug_name': drugName,
    'source_category': sourceCategory.wireValue,
    'start_date': startDate,
  };
}

class OnboardingMedicationsDraft {
  const OnboardingMedicationsDraft({required this.items, this.updatedAt});

  factory OnboardingMedicationsDraft.fromJson(dynamic value) {
    final json = jsonObject(value, 'onboarding medications step');
    return OnboardingMedicationsDraft(
      items:
          jsonArray(
            json['items'],
            'onboarding medications',
          ).map(OnboardingMedicationDraft.fromJson).toList(),
      updatedAt: jsonDateTimeOrNull(json, 'updated_at'),
    );
  }

  final List<OnboardingMedicationDraft> items;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };
}

class OnboardingDraft {
  const OnboardingDraft({
    required this.id,
    required this.currentStep,
    required this.updatedAt,
    this.basic,
    this.cycle,
    this.medications,
  });

  factory OnboardingDraft.fromJson(dynamic value) {
    final json = jsonObject(value, 'onboarding draft');
    return OnboardingDraft(
      id: jsonString(json, 'id'),
      currentStep: OnboardingStep.parse(jsonString(json, 'current_step')),
      basic:
          json['basic'] == null
              ? null
              : OnboardingBasicDraft.fromJson(json['basic']),
      cycle:
          json['cycle'] == null
              ? null
              : OnboardingCycleDraft.fromJson(json['cycle']),
      medications:
          json['medications'] == null
              ? null
              : OnboardingMedicationsDraft.fromJson(json['medications']),
      updatedAt: jsonDateTime(json, 'updated_at'),
    );
  }

  final String id;
  final OnboardingStep currentStep;
  final OnboardingBasicDraft? basic;
  final OnboardingCycleDraft? cycle;
  final OnboardingMedicationsDraft? medications;
  final DateTime updatedAt;
}

class OnboardingCompleteResult {
  const OnboardingCompleteResult({
    required this.account,
    required this.profile,
  });

  factory OnboardingCompleteResult.fromJson(dynamic value) {
    final json = jsonObject(value, 'onboarding completion');
    return OnboardingCompleteResult(
      account: AuthAccount.fromJson(jsonObject(json['account'], 'account')),
      profile: PatientProfile.fromJson(json['profile']),
    );
  }

  final AuthAccount account;
  final PatientProfile profile;
}

class OnboardingRepository {
  const OnboardingRepository(this.api);

  final ApiClient api;

  Future<OnboardingDraft> getDraft() async =>
      OnboardingDraft.fromJson(await api.get('/api/onboarding'));

  Future<OnboardingDraft> saveBasic(OnboardingBasicDraft input) async =>
      OnboardingDraft.fromJson(
        await api.put('/api/onboarding/steps/basic', data: input.toJson()),
      );

  Future<OnboardingDraft> saveCycle(OnboardingCycleDraft input) async =>
      OnboardingDraft.fromJson(
        await api.put('/api/onboarding/steps/cycle', data: input.toJson()),
      );

  Future<OnboardingDraft> saveMedications(
    OnboardingMedicationsDraft input,
  ) async => OnboardingDraft.fromJson(
    await api.put('/api/onboarding/steps/medications', data: input.toJson()),
  );

  Future<OnboardingCompleteResult> complete({
    required String idempotencyKey,
  }) async => OnboardingCompleteResult.fromJson(
    await api.post(
      '/api/onboarding/complete',
      headers: {'Idempotency-Key': idempotencyKey},
    ),
  );
}
