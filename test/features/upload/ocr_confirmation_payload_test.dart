import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/upload/upload_screen.dart';

void main() {
  test('builds unified confirmation contract from editable OCR result', () {
    final payload = buildOcrConfirmationPayload({
      'visit_date': '2026-08-20',
      'examinations': [
        {
          'item_name': '空腹血糖',
          'value': '5.2',
          'unit': 'mmol/L',
          'reference_range': '3.9-6.1',
        },
      ],
      'medication_suggestions': [
        {
          'drug_name': '二甲双胍',
          'dosage': '500mg',
          'frequency': '每日两次',
          'duration': '30天',
          'instruction': '随餐服用',
          'source_text': '二甲双胍 500mg 每日两次',
        },
      ],
    });

    expect(payload['visit_date'], '2026-08-20');
    expect(payload['examinations'], [
      {
        'source_index': 0,
        'item_name': '空腹血糖',
        'value': '5.2',
        'unit': 'mmol/L',
        'reference_range': '3.9-6.1',
      },
    ]);
    final item = (payload['medication_suggestions'] as List).single as Map;
    expect(item['source_index'], 0);
    expect(item['drug_name'], '二甲双胍');
    expect(item['dosage'], '500mg');
    expect(item['source_category'], 'prescribed');
    expect(item['start_date'], '2026-08-20');
  });

  test('preserves explicitly selected medication source fields', () {
    final payload = buildOcrConfirmationPayload({
      'visit_date': '2026-08-20',
      'examinations': <Map<String, dynamic>>[],
      'medication_suggestions': [
        {
          'drug_name': '肌醇',
          'dosage': '2g',
          'source_category': 'supplement',
          'start_date': '2026-08-22',
        },
      ],
    });

    final item = (payload['medication_suggestions'] as List).single as Map;
    expect(item['source_category'], 'supplement');
    expect(item['start_date'], '2026-08-22');
  });
}
