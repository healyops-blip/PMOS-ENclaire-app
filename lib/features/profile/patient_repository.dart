import '../../core/api_client.dart';
import '../../core/json_value.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final patientRepositoryProvider = Provider<PatientRepository>(
  (ref) => PatientRepository(ref.watch(apiClientProvider)),
);

class PatientProfile {
  const PatientProfile({
    required this.id,
    this.nickname,
    this.birthYear,
    this.diagnosisYear,
    required this.onboardingCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.heightCm,
    this.usualCycleMinDays,
    this.usualCycleMaxDays,
    this.periodDurationDays,
    this.nextVisitDate,
    this.healthGoal,
  });

  factory PatientProfile.fromJson(dynamic value) {
    final json = jsonObject(value, 'patient profile');
    return PatientProfile(
      id: jsonString(json, 'id'),
      nickname: jsonStringOrNull(json, 'nickname'),
      birthYear: jsonIntOrNull(json, 'birth_year'),
      diagnosisYear: jsonIntOrNull(json, 'diagnosis_year'),
      heightCm: jsonDoubleOrNull(json, 'height_cm'),
      usualCycleMinDays: jsonIntOrNull(json, 'usual_cycle_min_days'),
      usualCycleMaxDays: jsonIntOrNull(json, 'usual_cycle_max_days'),
      periodDurationDays: jsonIntOrNull(json, 'period_duration_days'),
      nextVisitDate: jsonStringOrNull(json, 'next_visit_date'),
      healthGoal: jsonStringOrNull(json, 'health_goal'),
      onboardingCompleted: jsonBool(json, 'onboarding_completed'),
      createdAt: jsonDateTime(json, 'created_at'),
      updatedAt: jsonDateTime(json, 'updated_at'),
    );
  }

  final String id;
  final String? nickname;
  final int? birthYear;
  final int? diagnosisYear;
  final double? heightCm;
  final int? usualCycleMinDays;
  final int? usualCycleMaxDays;
  final int? periodDurationDays;
  final String? nextVisitDate;
  final String? healthGoal;
  final bool onboardingCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PatientProfileUpdate {
  const PatientProfileUpdate({
    required this.updatedAt,
    this.nickname,
    this.birthYear,
    this.diagnosisYear,
    this.heightCm = const JsonPatchField.absent(),
    this.usualCycleMinDays = const JsonPatchField.absent(),
    this.usualCycleMaxDays = const JsonPatchField.absent(),
    this.periodDurationDays = const JsonPatchField.absent(),
    this.nextVisitDate = const JsonPatchField.absent(),
    this.healthGoal = const JsonPatchField.absent(),
  });

  final DateTime updatedAt;
  final String? nickname;
  final int? birthYear;
  final int? diagnosisYear;
  final JsonPatchField<double> heightCm;
  final JsonPatchField<int> usualCycleMinDays;
  final JsonPatchField<int> usualCycleMaxDays;
  final JsonPatchField<int> periodDurationDays;
  final JsonPatchField<String> nextVisitDate;
  final JsonPatchField<String> healthGoal;

  Map<String, dynamic> toJson() => {
    if (nickname != null) 'nickname': nickname,
    if (birthYear != null) 'birth_year': birthYear,
    if (diagnosisYear != null) 'diagnosis_year': diagnosisYear,
    if (heightCm.isPresent) 'height_cm': heightCm.value,
    if (usualCycleMinDays.isPresent)
      'usual_cycle_min_days': usualCycleMinDays.value,
    if (usualCycleMaxDays.isPresent)
      'usual_cycle_max_days': usualCycleMaxDays.value,
    if (periodDurationDays.isPresent)
      'period_duration_days': periodDurationDays.value,
    if (nextVisitDate.isPresent) 'next_visit_date': nextVisitDate.value,
    if (healthGoal.isPresent) 'health_goal': healthGoal.value,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

class PatientRepository {
  const PatientRepository(this.api);

  final ApiClient api;

  Future<PatientProfile> getProfile() async =>
      PatientProfile.fromJson(await api.get('/api/patient/profile'));

  Future<PatientProfile> updateProfile(PatientProfileUpdate input) async =>
      PatientProfile.fromJson(
        await api.put('/api/patient/profile', data: input.toJson()),
      );
}
