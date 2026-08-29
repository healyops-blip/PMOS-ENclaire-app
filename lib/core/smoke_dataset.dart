import 'dart:convert';

import 'package:flutter/services.dart';

/// The product-provided OCR fixture set used by the local Smoke Preview.
///
/// The source bundle intentionally keeps the original JSON and image files so
/// that demo recognition uses the same field values as the supplied materials.
const smokeDatasetJsonAssets = <String>[
  'assets/data/smoke_dataset/影像文字报告/影像文字报告__case_00001.json',
  'assets/data/smoke_dataset/影像文字报告/影像文字报告__case_00002.json',
  'assets/data/smoke_dataset/影像文字报告/影像文字报告__case_00003.json',
  'assets/data/smoke_dataset/影像文字报告/影像文字报告__case_00004.json',
  'assets/data/smoke_dataset/影像文字报告/影像文字报告__case_00005.json',
  'assets/data/smoke_dataset/化验_检测报告/化验_检测报告__case_00006.json',
  'assets/data/smoke_dataset/化验_检测报告/化验_检测报告__case_00007.json',
  'assets/data/smoke_dataset/化验_检测报告/化验_检测报告__case_00008.json',
  'assets/data/smoke_dataset/化验_检测报告/化验_检测报告__case_00009.json',
  'assets/data/smoke_dataset/化验_检测报告/化验_检测报告__case_00010.json',
  'assets/data/smoke_dataset/医嘱_处方/医嘱_处方__case_00011.json',
  'assets/data/smoke_dataset/医嘱_处方/医嘱_处方__case_00012.json',
  'assets/data/smoke_dataset/医嘱_处方/医嘱_处方__case_00013.json',
  'assets/data/smoke_dataset/医嘱_处方/医嘱_处方__case_00014.json',
  'assets/data/smoke_dataset/医嘱_处方/医嘱_处方__case_00015.json',
  'assets/data/smoke_dataset/门诊病历_就诊记录/门诊病历_就诊记录__case_00016.json',
  'assets/data/smoke_dataset/门诊病历_就诊记录/门诊病历_就诊记录__case_00017.json',
  'assets/data/smoke_dataset/门诊病历_就诊记录/门诊病历_就诊记录__case_00018.json',
  'assets/data/smoke_dataset/门诊病历_就诊记录/门诊病历_就诊记录__case_00019.json',
  'assets/data/smoke_dataset/门诊病历_就诊记录/门诊病历_就诊记录__case_00020.json',
];

Future<List<Map<String, dynamic>>> loadSmokeDataset() async {
  final values = await Future.wait(
    smokeDatasetJsonAssets.map((asset) async {
      final value = jsonDecode(await rootBundle.loadString(asset));
      return {
        ...Map<String, dynamic>.from(value as Map),
        '_dataset_json_asset': asset,
      };
    }),
  );
  return values;
}

String smokeDatasetType(String path) {
  if (path.contains('/化验_检测报告/')) return 'lab_report';
  if (path.contains('/医嘱_处方/')) return 'medical_order';
  if (path.contains('/影像文字报告/')) return 'imaging_text_report';
  return 'outpatient_record';
}

String smokeDatasetImageAsset(String jsonAsset) =>
    jsonAsset.replaceFirst(RegExp(r'\.json$'), '.jpg');

Map<String, dynamic> smokeDatasetDocument(
  Map<String, dynamic> value,
  String jsonAsset,
) {
  final id = value['doc_id']?.toString() ?? jsonAsset.hashCode.toString();
  final visitDate = value['visit_date']?.toString();
  return {
    'id': id,
    'document_type': smokeDatasetType(jsonAsset),
    'original_file_name':
        value['original_file_name'] ?? jsonAsset.split('/').last,
    'uploaded_at': visitDate == null ? null : '${visitDate}T09:00:00Z',
    'mime_type': 'image/jpeg',
    'latest_ocr_status': 'confirmed',
    'current_revision_id': 'revision-$id',
    'hospital': value['hospital'],
    'department': value['department'],
    'visit_date': visitDate,
    'diagnosis_summary': value['diagnosis_summary'],
    'medical_advice': value['medical_advice'],
    'examinations': value['examinations'] ?? const <Map<String, dynamic>>[],
    'medication_suggestions':
        value['medication_suggestions'] ?? const <Map<String, dynamic>>[],
    'dataset_json_asset': jsonAsset,
    'dataset_image_asset': smokeDatasetImageAsset(jsonAsset),
  };
}
