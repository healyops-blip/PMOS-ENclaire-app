import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/core/json_value.dart';
import 'package:pmos_enclaire/features/auth/onboarding_repository.dart';
import 'package:pmos_enclaire/features/dashboard/dashboard_repository.dart';
import 'package:pmos_enclaire/features/medications/medication_repository.dart';
import 'package:pmos_enclaire/features/profile/patient_repository.dart';
import 'package:pmos_enclaire/features/tracking/tracking_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'onboarding sends step payload and completion idempotency key',
    () async {
      final api = _RecordingApiClient({
        'PUT /api/onboarding/steps/basic': _onboardingDraft,
        'POST /api/onboarding/complete': {
          'account': {
            'uid': 'user-1',
            'account_name': 'pomi-user',
            'onboarding_completed': true,
          },
          'profile': _profile,
        },
      });
      final repository = OnboardingRepository(api);

      final draft = await repository.saveBasic(
        const OnboardingBasicDraft(
          nickname: 'Pomi',
          birthYear: 1997,
          diagnosisYear: 2023,
        ),
      );
      final result = await repository.complete(idempotencyKey: 'complete-1');

      expect(draft.currentStep, OnboardingStep.cycle);
      expect(api.requests.first.data, containsPair('birth_year', 1997));
      expect(api.requests.last.headers, {'Idempotency-Key': 'complete-1'});
      expect(result.account.onboardingCompleted, isTrue);
      expect(result.profile.nickname, 'Pomi');
    },
  );

  test('profile update can explicitly clear nullable values', () async {
    final api = _RecordingApiClient({'PUT /api/patient/profile': _profile});
    final repository = PatientRepository(api);

    await repository.updateProfile(
      PatientProfileUpdate(
        updatedAt: DateTime.utc(2026, 8, 27),
        nickname: 'Pomi',
        heightCm: const JsonPatchField.value(null),
        nextVisitDate: const JsonPatchField.value(null),
      ),
    );

    expect(api.requests.single.data, containsPair('height_cm', null));
    expect(api.requests.single.data, containsPair('next_visit_date', null));
    expect(api.requests.single.data, isNot(contains('health_goal')));
  });

  test(
    'medication and tracking repositories use phase-one wire fields',
    () async {
      final api = _RecordingApiClient({
        'GET /api/medications': {
          'server_date': '2026-08-27',
          'items': [_medication],
          'next_cursor': null,
          'has_more': false,
        },
        'POST /api/cycles': _cycle,
        'POST /api/weights': _weight,
      });

      final medications = await MedicationRepository(
        api,
      ).list(status: MedicationStatus.active, cursor: 'next', limit: 10);
      final tracking = TrackingRepository(api);
      await tracking.createCycle(
        CycleInput(
          startDate: DateTime(2026, 8, 1),
          flowLevel: CycleFlowLevel.medium,
        ),
      );
      await tracking.createOrUpdateWeight(
        recordDate: DateTime(2026, 8, 27),
        weightKg: 55.2,
      );

      expect(medications.items.single.drugName, '二甲双胍');
      expect(api.requests[0].query, {
        'status': 'active',
        'cursor': 'next',
        'limit': 10,
      });
      expect(api.requests[1].data, containsPair('source_type', 'manual'));
      expect(api.requests[2].data, {
        'record_date': '2026-08-27',
        'weight_kg': 55.2,
      });
    },
  );

  test('dashboard parses independent section states', () async {
    final api = _RecordingApiClient({
      'GET /api/dashboard': {
        'server_date': '2026-08-27',
        'data_as_of': '2026-08-27T12:00:00Z',
        'follow_up': {
          'status': 'ok',
          'data': {'date': '2026-09-10', 'timing': 'future', 'days': 14},
          'error_code': null,
        },
        'today_medications': {
          'status': 'empty',
          'data': <dynamic>[],
          'error_code': null,
        },
        'monthly_medication_summary': {
          'status': 'error',
          'data': null,
          'error_code': 'SUMMARY_UNAVAILABLE',
        },
        'tracking_summary': {
          'status': 'ok',
          'data': {'latest_cycle': _cycle, 'latest_weight': _weight},
          'error_code': null,
        },
        'document_summary': {
          'status': 'ok',
          'data': {'confirmed': 2, 'total': 3},
          'error_code': null,
        },
        'latest_report': {'status': 'empty', 'data': null, 'error_code': null},
      },
    });

    final dashboard = await DashboardRepository(
      api,
    ).get(date: DateTime(2026, 8, 27));

    expect(dashboard.followUp.data!.days, 14);
    expect(dashboard.todayMedications.status, DashboardSectionStatus.empty);
    expect(dashboard.monthlyMedicationSummary.errorCode, 'SUMMARY_UNAVAILABLE');
    expect(dashboard.trackingSummary.data!.latestWeight!.weightKg, 55.2);
    expect(api.requests.single.query, {'date': '2026-08-27'});
  });
}

const _onboardingDraft = {
  'id': 'draft-1',
  'current_step': 'cycle',
  'basic': {
    'nickname': 'Pomi',
    'birth_year': 1997,
    'diagnosis_year': 2023,
    'height_cm': null,
    'weight_kg': null,
    'updated_at': '2026-08-27T12:00:00Z',
  },
  'cycle': null,
  'medications': null,
  'updated_at': '2026-08-27T12:00:00Z',
};

const _profile = {
  'id': 'profile-1',
  'nickname': 'Pomi',
  'birth_year': 1997,
  'diagnosis_year': 2023,
  'height_cm': null,
  'usual_cycle_min_days': 28,
  'usual_cycle_max_days': 32,
  'next_visit_date': null,
  'health_goal': null,
  'onboarding_completed': true,
  'created_at': '2026-08-27T12:00:00Z',
  'updated_at': '2026-08-27T12:00:00Z',
};

const _medication = {
  'id': 'medication-1',
  'drug_name': '二甲双胍',
  'source_category': 'prescribed',
  'current_status': 'active',
  'created_at': '2026-08-27T12:00:00Z',
  'updated_at': '2026-08-27T12:00:00Z',
};

const _cycle = {
  'id': 'cycle-1',
  'start_date': '2026-08-01',
  'end_date': null,
  'flow_level': 'medium',
  'note': null,
  'source_type': 'manual',
  'updated_at': '2026-08-27T12:00:00Z',
  'cycle_length_days': null,
  'duration_days': null,
  'created_at': '2026-08-27T12:00:00Z',
};

const _weight = {
  'id': 'weight-1',
  'record_date': '2026-08-27',
  'weight_kg': 55.2,
  'created_at': '2026-08-27T12:00:00Z',
  'updated_at': '2026-08-27T12:00:00Z',
};

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    this.data,
    this.query,
    this.headers,
  });

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic>? query;
  final Map<String, String>? headers;
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient(this.responses)
    : super(const FlutterSecureStorage(), baseUrl: 'http://example.invalid');

  final Map<String, dynamic> responses;
  final List<_RecordedRequest> requests = [];

  dynamic _response(String method, String path) => responses['$method $path'];

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(
      _RecordedRequest(method: 'GET', path: path, query: queryParameters),
    );
    return _response('GET', path);
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    requests.add(
      _RecordedRequest(
        method: 'POST',
        path: path,
        data: data,
        headers: headers,
      ),
    );
    return _response('POST', path);
  }

  @override
  Future<dynamic> put(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    requests.add(
      _RecordedRequest(method: 'PUT', path: path, data: data, headers: headers),
    );
    return _response('PUT', path);
  }

  @override
  Future<dynamic> delete(String path, {Object? data}) async {
    requests.add(_RecordedRequest(method: 'DELETE', path: path, data: data));
    return _response('DELETE', path);
  }
}
