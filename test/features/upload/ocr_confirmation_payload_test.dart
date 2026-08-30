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

  test('builds clinical text contract for imaging text report', () {
    final payload = buildOcrConfirmationPayload(
      {
        'hospital': '上海瑞宁医院',
        'examination_name': '超声影像文字报告',
        'body_part': '妇科盆腔',
        'findings_text': '内膜线居中。',
        'conclusion_text': '未见明显异常。',
        'examined_at': '2026-08-22',
      },
      materialType: 'imaging_text_report',
      taskId: 'task-1',
      revisionId: 'rev-1',
      resultId: 'result-1',
    );

    expect(payload['result_id'], 'result-1');
    expect(payload['expected_revision_id'], 'rev-1');
    expect(payload['document_type'], 'imaging_text_report');
    expect(payload['confirm_all'], true);
    expect(payload['field_confirmations'], isEmpty);
    final confirmed = payload['confirmed_data'] as Map;
    expect(confirmed['hospital_name'], '上海瑞宁医院');
    expect(confirmed['examination_name'], '超声影像文字报告');
    expect(confirmed['findings_text'], '内膜线居中。');
    expect(confirmed['conclusion_text'], '未见明显异常。');
  });

  test('builds clinical text contract for outpatient record', () {
    final payload = buildOcrConfirmationPayload(
      {
        'hospital': '西安达济医院',
        'visit_date': '2026-07-31',
        'chief_complaint': '月经不调',
        'diagnosis_summary': '多囊卵巢综合征',
        'treatment_plan': '生活方式干预',
        'medical_advice': '20天后复诊',
      },
      materialType: 'outpatient_record',
      taskId: 'task-2',
      revisionId: 'rev-2',
      resultId: 'result-2',
    );

    expect(payload['document_type'], 'outpatient_record');
    final confirmed = payload['confirmed_data'] as Map;
    expect(confirmed['hospital_name'], '西安达济医院');
    expect(confirmed['visit_date'], '2026-07-31');
    expect(confirmed['chief_complaint'], '月经不调');
    expect(confirmed['diagnosis_summary'], '多囊卵巢综合征');
    expect(confirmed['medical_advice'], '20天后复诊');
    // 空字段不进入 confirmed_data，避免必填校验误伤。
    expect(confirmed.containsKey('doctor_name'), isFalse);
  });

  test('lab payload tolerates missing value and unit', () {
    final payload = buildOcrConfirmationPayload({
      'visit_date': '2026-08-20',
      'examinations': [
        {
          'item_name': '白细胞计数',
          'value': null,
          'unit': null,
          'reference_range': null,
        },
      ],
      'medication_suggestions': <Map<String, dynamic>>[],
    });

    final exam = (payload['examinations'] as List).single as Map;
    expect(exam['value'], isNull);
    expect(exam['unit'], isNull);
  });
}
