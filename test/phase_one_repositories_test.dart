import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/json_value.dart';
import 'package:pmos_enclaire/features/dashboard/dashboard_repository.dart';
import 'package:pmos_enclaire/features/medications/medication_repository.dart';
import 'package:pmos_enclaire/features/profile/patient_repository.dart';
import 'package:pmos_enclaire/features/tracking/tracking_repository.dart';

import 'support/fake_api_client.dart';

void main() {
  test(
    'patient profile accepts nullable pre-onboarding fields and preserves clear semantics',
    () async {
      late ApiCall updateCall;
      final api = FakeApiClient(
        handler: (call) {
          if (call.method == 'GET') return _profile();
          updateCall = call;
          return {..._profile(), 'nickname': 'Alice'};
        },
      );
      final repository = PatientRepository(api);

      final profile = await repository.getProfile();
      expect(profile.nickname, isNull);
      expect(profile.birthYear, isNull);
      expect(profile.diagnosisYear, isNull);

      final updated = await repository.updateProfile(
        PatientProfileUpdate(
          updatedAt: profile.updatedAt,
          nickname: 'Alice',
          nextVisitDate: const JsonPatchField<String>.value(null),
        ),
      );

      expect(updated.nickname, 'Alice');
      expect(updateCall.path, '/api/patient/profile');
      expect(updateCall.data, {
        'nickname': 'Alice',
        'next_visit_date': null,
        'updated_at': '2026-08-28T01:02:03.000Z',
      });
    },
  );

  test(
    'medication repository uses the direct item contract and idempotency header',
    () async {
      const testRequestKey = 'repeatable-test-request';
      late ApiCall createCall;
      final api = FakeApiClient(
        handler: (call) {
          createCall = call;
          return _medication();
        },
      );

      final medication = await MedicationRepository(api).create(
        const MedicationCreateInput(
          drugName: '二甲双胍',
          sourceCategory: MedicationSourceCategory.prescribed,
          dosageValue: 500,
          dosageUnit: 'mg',
        ),
        idempotencyKey: testRequestKey,
      );

      expect(medication.currentStatus, MedicationStatus.active);
      expect(createCall.path, '/api/medications');
      expect(createCall.headers, {'Idempotency-Key': testRequestKey});
      expect((createCall.data as Map)['drug_name'], '二甲双胍');
    },
  );

  test(
    'tracking update sends optimistic-lock time and parses weight response',
    () async {
      late ApiCall call;
      final api = FakeApiClient(
        handler: (value) {
          call = value;
          return _weight();
        },
      );
      final updatedAt = DateTime.parse('2026-08-28T01:02:03Z');

      final weight = await TrackingRepository(api).updateWeight(
        id: 'weight-1',
        recordDate: DateTime(2026, 8, 29),
        weightKg: 63.2,
        updatedAt: updatedAt,
      );

      expect(weight.weightKg, 63.2);
      expect(call.path, '/api/weights/weight-1');
      expect(call.data, {
        'record_date': '2026-08-29',
        'weight_kg': 63.2,
        'updated_at': updatedAt.toIso8601String(),
      });
    },
  );

  test(
    'dashboard parses the current follow-up and monthly summary fields',
    () async {
      final api = FakeApiClient(handler: (_) => _dashboard());

      final dashboard = await DashboardRepository(api).get();

      expect(dashboard.serverDate, '2026-08-28');
      expect(dashboard.followUp.data?.nextVisitDate, '2026-09-01');
      expect(dashboard.followUp.data?.state, 'upcoming');
      expect(dashboard.followUp.data?.daysRemaining, 4);
      expect(dashboard.monthlyMedicationSummary.data?.takenCount, 12);
      expect(
        dashboard.todayMedications.data?.single.intakeStatus,
        MedicationDailyStatus.taken,
      );
    },
  );
}

Map<String, dynamic> _profile() => {
  'id': 'patient-1',
  'nickname': null,
  'birth_year': null,
  'diagnosis_year': null,
  'height_cm': null,
  'usual_cycle_min_days': null,
  'usual_cycle_max_days': null,
  'next_visit_date': null,
  'health_goal': null,
  'onboarding_completed': false,
  'created_at': '2026-08-28T01:02:03Z',
  'updated_at': '2026-08-28T01:02:03Z',
};

Map<String, dynamic> _medication() => {
  'id': 'medication-1',
  'drug_name': '二甲双胍',
  'source_category': 'prescribed',
  'specification': null,
  'dosage_value': 500,
  'dosage_unit': 'mg',
  'frequency': '每日两次',
  'route': null,
  'current_status': 'active',
  'start_date': '2026-08-26',
  'created_at': '2026-08-28T01:02:03Z',
  'updated_at': '2026-08-28T01:02:03Z',
};

Map<String, dynamic> _weight() => {
  'id': 'weight-1',
  'record_date': '2026-08-29',
  'weight_kg': 63.2,
  'created_at': '2026-08-28T01:02:03Z',
  'updated_at': '2026-08-28T02:03:04Z',
};

Map<String, dynamic> _dashboard() => {
  'server_date': '2026-08-28',
  'data_as_of': '2026-08-28T01:02:03Z',
  'follow_up': {
    'status': 'ok',
    'data': {
      'next_visit_date': '2026-09-01',
      'state': 'upcoming',
      'days_remaining': 4,
    },
    'error_code': null,
  },
  'today_medications': {
    'status': 'ok',
    'data': [
      {
        'medication_id': 'medication-1',
        'drug_name': '二甲双胍',
        'specification': null,
        'dosage_text': '500mg',
        'frequency': '每日两次',
        'intake_status': 'taken',
        'recorded_at': '2026-08-28T01:00:00Z',
      },
    ],
    'error_code': null,
  },
  'monthly_medication_summary': {
    'status': 'ok',
    'data': {
      'month': '2026-08',
      'taken_count': 12,
      'missed_count': 1,
      'unrecorded_count': 3,
    },
    'error_code': null,
  },
  'tracking_summary': {'status': 'empty', 'data': null, 'error_code': null},
  'document_summary': {
    'status': 'ok',
    'data': {'confirmed': 2, 'total': 3},
    'error_code': null,
  },
  'latest_report': {'status': 'empty', 'data': null, 'error_code': null},
};
