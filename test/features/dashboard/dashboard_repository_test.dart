import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/dashboard/dashboard_repository.dart';

void main() {
  test('parses the fault-isolated dashboard response contract', () {
    final dashboard = DashboardData.fromJson({
      'server_date': '2026-08-28',
      'data_as_of': '2026-08-28T07:00:00Z',
      'follow_up': {
        'status': 'ok',
        'data': {
          'next_visit_date': '2026-09-05',
          'state': 'upcoming',
          'days_remaining': 8,
        },
        'error_code': null,
      },
      'today_medications': {
        'status': 'ok',
        'data': [
          {
            'medication_id': 'med-1',
            'drug_name': '二甲双胍',
            'specification': '500mg',
            'dosage_text': '500mg',
            'frequency': '每日两次',
            'intake_status': 'unrecorded',
            'recorded_at': null,
          },
        ],
        'error_code': null,
      },
      'monthly_medication_summary': {
        'status': 'ok',
        'data': {
          'month': '2026-08',
          'taken_count': 4,
          'missed_count': 1,
          'unrecorded_count': 2,
        },
        'error_code': null,
      },
      'tracking_summary': {'status': 'empty', 'data': null, 'error_code': null},
      'document_summary': {
        'status': 'ok',
        'data': {'confirmed': 1, 'total': 2},
        'error_code': null,
      },
      'latest_report': {
        'status': 'ok',
        'data': {
          'report_id': 'report-1',
          'status': 'succeeded',
          'generated_at': '2026-08-28T06:00:00Z',
          'snapshot_hash': 'hash',
        },
        'error_code': null,
      },
    });

    expect(dashboard.followUp.data?.daysRemaining, 8);
    expect(dashboard.todayMedications.data?.single.medicationId, 'med-1');
    expect(dashboard.latestReport.data?.id, 'report-1');
    expect(dashboard.documentSummary.data?.total, 2);
  });
}
