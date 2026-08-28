import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/upload/upload_screen.dart';

void main() {
  test('builds laboratory confirmation contract from editable draft', () {
    final payload = buildOcrConfirmationPayload(
      documentType: 'lab_report',
      resultId: 'result-1',
      revisionId: 'revision-1',
      draft: {
        'sample_date': '2026-08-20',
        'report_date': '2026-08-21',
        'items': [
          {
            'item_name': '睾酮',
            'raw_value': '1.8',
            'raw_unit': 'nmol/L',
            'reference_range_text': '0.3-2.4',
          },
        ],
      },
    );

    expect(payload['result_id'], 'result-1');
    expect(payload['expected_revision_id'], 'revision-1');
    expect(payload['sample_date'], '2026-08-20');
    expect(payload['items'], [
      {
        'source_index': 0,
        'name': '睾酮',
        'value': '1.8',
        'unit': 'nmol/L',
        'reference_range': '0.3-2.4',
      },
    ]);
  });

  test('builds medical order confirmation contract for every item', () {
    final payload = buildOcrConfirmationPayload(
      documentType: 'medical_order',
      resultId: 'result-2',
      revisionId: 'revision-2',
      draft: {
        'prescribed_at': '2026-08-20',
        'orders': [
          {
            'source_text': '二甲双胍 500mg 每日两次',
            'drug_name': '二甲双胍',
            'specification': '500mg',
            'dosage_value': 500,
            'dosage_unit': 'mg',
            'frequency': '每日两次',
            'duration': '30天',
            'route': '口服',
            'instruction': '随餐服用',
          },
        ],
      },
    );

    final item = (payload['items'] as List).single as Map;
    expect(item['source_index'], 0);
    expect(item['confirmed'], isTrue);
    expect(item['drug_name'], '二甲双胍');
    expect(item['prescribed_at'], '2026-08-20');
    expect(item['explicitly_stopped'], isFalse);
  });

  test('builds clinical text confirmation contract', () {
    final draft = {
      'visit_date': '2026-08-20',
      'diagnosis_summary': '多囊卵巢综合征',
      'medical_advice': '按时复诊',
    };
    final payload = buildOcrConfirmationPayload(
      documentType: 'outpatient_record',
      resultId: 'result-3',
      revisionId: 'revision-3',
      draft: draft,
    );

    expect(payload['document_type'], 'outpatient_record');
    expect(payload['confirmed_data'], draft);
    expect(payload['confirm_all'], isTrue);
  });
}
