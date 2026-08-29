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

  test(
    'builds the strict outpatient confirmation DTO without display-only fields',
    () {
      final payload = buildOcrConfirmationPayload(
        {
          'hospital': '上海医院',
          'department': '生殖科',
          'visit_date': '2026-08-03',
          'diagnosis_summary': '多囊卵巢综合征',
          'medical_advice': '按需随访',
          'examinations': <Map<String, dynamic>>[],
          'original_file_name': 'record.jpg',
        },
        resultId: 'result-1',
        expectedRevisionId: 'revision-1',
        materialType: 'outpatient_record',
      );

      expect(payload['document_type'], 'outpatient_record');
      expect(payload['confirmed_data'], {
        'hospital_name': '上海医院',
        'department_name': '生殖科',
        'visit_date': '2026-08-03',
        'diagnosis_summary': '多囊卵巢综合征',
        'medical_advice': '按需随访',
        'treatment_plan': '按需随访',
      });
      expect(
        (payload['confirmed_data'] as Map).containsKey('examinations'),
        isFalse,
      );
      expect(
        (payload['confirmed_data'] as Map).containsKey('original_file_name'),
        isFalse,
      );
    },
  );
}
