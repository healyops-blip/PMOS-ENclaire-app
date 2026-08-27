import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';

class PatientProfile {
  const PatientProfile({
    required this.patientId,
    required this.onboardingCompleted,
    required this.updatedAt,
    this.nickname,
    this.birthDate,
    this.gender,
    this.heightCm,
    this.diagnosisYear,
    this.primaryCondition,
    this.nextVisitDate,
    this.healthGoal,
  });

  final String patientId;
  final String? nickname;
  final DateTime? birthDate;
  final String? gender;
  final double? heightCm;
  final int? diagnosisYear;
  final String? primaryCondition;
  final DateTime? nextVisitDate;
  final String? healthGoal;
  final bool onboardingCompleted;
  final DateTime updatedAt;

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    DateTime? optionalDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return PatientProfile(
      patientId: json['patient_id'] as String,
      nickname: json['nickname'] as String?,
      birthDate: optionalDate('birth_date'),
      gender: json['gender'] as String?,
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      diagnosisYear: json['diagnosis_year'] as int?,
      primaryCondition: json['primary_condition'] as String?,
      nextVisitDate: optionalDate('next_visit_date'),
      healthGoal: json['health_goal'] as String?,
      onboardingCompleted: json['onboarding_completed'] as bool,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class PatientProfileInput {
  const PatientProfileInput({
    this.nickname,
    this.birthDate,
    this.gender,
    this.heightCm,
    this.diagnosisYear,
    this.primaryCondition,
    this.nextVisitDate,
    this.healthGoal,
    this.completeOnboarding = false,
  });

  final String? nickname;
  final DateTime? birthDate;
  final String? gender;
  final double? heightCm;
  final int? diagnosisYear;
  final String? primaryCondition;
  final DateTime? nextVisitDate;
  final String? healthGoal;
  final bool completeOnboarding;

  Map<String, dynamic> toJson(DateTime updatedAt) => {
    'nickname': nickname,
    'birth_date': _date(birthDate),
    'gender': gender,
    'height_cm': heightCm,
    'diagnosis_year': diagnosisYear,
    'primary_condition': primaryCondition,
    'next_visit_date': _date(nextVisitDate),
    'health_goal': healthGoal,
    'complete_onboarding': completeOnboarding,
    'updated_at': updatedAt.toIso8601String(),
  };

  static String? _date(DateTime? value) {
    if (value == null) return null;
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

abstract interface class PatientProfileRepository {
  Future<PatientProfile> get();

  Future<PatientProfile> update(PatientProfileInput input);
}

class FastApiPatientProfileRepository implements PatientProfileRepository {
  FastApiPatientProfileRepository(this.client);

  final PomiApiClient client;

  @override
  Future<PatientProfile> get() async {
    final response = await client.dio.get<Map<String, dynamic>>(
      '/patient/profile',
    );
    return _profile(response.data!);
  }

  @override
  Future<PatientProfile> update(PatientProfileInput input) async {
    final current = await get();
    try {
      final response = await client.dio.put<Map<String, dynamic>>(
        '/patient/profile',
        data: input.toJson(current.updatedAt),
      );
      return _profile(response.data!);
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map && body['error'] is Map) {
        final message = (body['error'] as Map)['message']?.toString();
        throw PatientProfileFailure(message ?? '保存资料失败，请重试');
      }
      throw const PatientProfileFailure('无法连接服务，资料尚未保存');
    }
  }

  PatientProfile _profile(Map<String, dynamic> envelope) {
    return PatientProfile.fromJson(
      Map<String, dynamic>.from(envelope['data'] as Map),
    );
  }
}

class PatientProfileFailure implements Exception {
  const PatientProfileFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class DemoPatientProfileRepository implements PatientProfileRepository {
  DemoPatientProfileRepository({PatientProfile? initial})
    : _profile =
          initial ??
          PatientProfile(
            patientId: 'demo-patient',
            onboardingCompleted: false,
            updatedAt: DateTime(2026, 8, 27),
          );

  PatientProfile _profile;

  @override
  Future<PatientProfile> get() async => _profile;

  @override
  Future<PatientProfile> update(PatientProfileInput input) async {
    _profile = PatientProfile(
      patientId: _profile.patientId,
      nickname: input.nickname,
      birthDate: input.birthDate,
      gender: input.gender,
      heightCm: input.heightCm,
      diagnosisYear: input.diagnosisYear,
      primaryCondition: input.primaryCondition,
      nextVisitDate: input.nextVisitDate,
      healthGoal: input.healthGoal,
      onboardingCompleted:
          _profile.onboardingCompleted || input.completeOnboarding,
      updatedAt: _profile.updatedAt.add(const Duration(seconds: 1)),
    );
    return _profile;
  }
}
