import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String _documentType = 'lab';
  File? _file;
  String? _idempotencyKey;
  String? _status;
  bool _working = false;

  static const typeLabels = {
    'lab': '化验 / 检测',
    'medical_order': '医嘱 / 处方',
    'imaging': '影像文字报告',
    'outpatient': '门诊病历',
  };

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    final path = file?.path;
    if (path != null) {
      setState(() {
        _file = File(path);
        _idempotencyKey = null;
      });
    }
  }

  Future<void> _takePhoto() async {
    final result = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 4096,
      maxHeight: 4096,
    );
    if (result != null) {
      setState(() {
        _file = File(result.path);
        _idempotencyKey = null;
      });
    }
  }

  Future<void> _start() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _working = true;
      _status = '正在安全上传原件';
    });
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.recognizeOcr(
        file: file,
        materialType: _wireMaterialType,
        promptVersion: 'pomi-ocr-v1',
        consentVersion: 'pomi-external-processing-v1',
        idempotencyKey:
            _idempotencyKey ??= 'ocr-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() => _status = '识别完成');
      final taskId = result['task_id']?.toString();
      final resultId = result['result_id']?.toString();
      final revisionId = result['document_revision_id']?.toString();
      final draft = result['draft'];
      if (taskId == null ||
          resultId == null ||
          revisionId == null ||
          draft is! Map) {
        throw const FormatException('识别结果缺少确认所需的版本信息，请重新识别');
      }
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder:
              (_) => OcrConfirmScreen(
                taskId: taskId,
                resultId: resultId,
                revisionId: revisionId,
                documentType: _wireMaterialType,
                resultSource: result['result_source']?.toString() ?? 'qwen3-vl',
                draft: Map<String, dynamic>.from(draft),
              ),
        ),
      );
      if (mounted && confirmed == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('资料已确认，可在“记录”中查看和认证')));
        setState(() {
          _file = null;
          _idempotencyKey = null;
          _status = null;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String get _wireMaterialType => switch (_documentType) {
    'lab' => 'lab_report',
    'medical_order' => 'medical_order',
    'imaging' => 'imaging_text_report',
    _ => 'outpatient_record',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('上传资料')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
        children: [
          const Text(
            '选择材料类型',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _documentType,
            onChanged: (value) {
              if (!_working && value != null) {
                setState(() => _documentType = value);
              }
            },
            child: Column(
              children: [
                for (final entry in typeLabels.entries)
                  RadioListTile<String>(
                    value: entry.key,
                    enabled: !_working,
                    title: Text(entry.value),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const Divider(height: 30),
          const Text(
            '添加原件',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _working ? null : _takePhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('拍照'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _working ? null : _pickFile,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('相册 / 文件'),
                ),
              ),
            ],
          ),
          if (_file != null) ...[
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: Icon(
                  _file!.path.toLowerCase().endsWith('.pdf')
                      ? Icons.picture_as_pdf
                      : Icons.image_outlined,
                ),
                title: Text(
                  _file!.uri.pathSegments.last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: '移除',
                  onPressed:
                      _working
                          ? null
                          : () => setState(() {
                            _file = null;
                            _idempotencyKey = null;
                          }),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ],
          if (_working) ...[
            const SizedBox(height: 22),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status ?? '处理中', textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _file == null || _working ? null : _start,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('开始识别'),
          ),
          const SizedBox(height: 12),
          const Text(
            '支持 JPG、PNG 和单页 PDF，最大 20 MB。识别结果必须经你确认后才会进入报告。',
            style: TextStyle(
              color: Color(0xFF686E6A),
              fontSize: 13,
              height: 20 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class OcrConfirmScreen extends ConsumerStatefulWidget {
  const OcrConfirmScreen({
    required this.taskId,
    required this.resultId,
    required this.revisionId,
    required this.documentType,
    required this.resultSource,
    required this.draft,
    super.key,
  });

  final String taskId;
  final String resultId;
  final String revisionId;
  final String documentType;
  final String resultSource;
  final Map<String, dynamic> draft;

  @override
  ConsumerState<OcrConfirmScreen> createState() => _OcrConfirmScreenState();
}

class _OcrConfirmScreenState extends ConsumerState<OcrConfirmScreen> {
  late Map<String, dynamic> _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.draft)) as Map,
    );
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/api/ocr/tasks/${widget.taskId}/confirm',
            data: buildOcrConfirmationPayload(
              documentType: widget.documentType,
              resultId: widget.resultId,
              revisionId: widget.revisionId,
              draft: _draft,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('核对识别结果')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          if (widget.resultSource == 'fallback')
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2D6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE7C878)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF8A6410)),
                  SizedBox(width: 10),
                  Expanded(child: Text('当前为演示兜底结果，不是外部模型的实时识别。请逐项对照原件。')),
                ],
              ),
            ),
          const Text(
            '逐项确认',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('修改后的内容会与模型原值分开保存。'),
          const SizedBox(height: 18),
          _JsonFields(
            value: _draft,
            onChanged:
                (value) => _draft = Map<String, dynamic>.from(value as Map),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _confirm,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(_saving ? '正在保存' : '确认并入库'),
        ),
      ),
    );
  }
}

class _JsonFields extends StatelessWidget {
  const _JsonFields({required this.value, required this.onChanged, this.label});

  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final String? label;

  static const labels = {
    'document_type': '材料类型',
    'sample_date': '采样日期',
    'report_date': '报告日期',
    'observations': '检查项目',
    'items': '检查项目',
    'orders': '药品医嘱',
    'hospital_name': '医院',
    'department_name': '科室',
    'doctor_name': '医生',
    'prescribed_at': '开具日期',
    'examined_at': '检查日期',
    'reported_at': '报告日期',
    'examination_name': '检查名称',
    'body_part': '检查部位',
    'examination_method': '检查方法',
    'item_name': '项目名称',
    'item_code': '项目代码',
    'raw_value': '原始数值',
    'numeric_value': '数值',
    'unit': '单位',
    'raw_unit': '原始单位',
    'normalized_unit': '标准单位',
    'reference_range': '参考范围',
    'reference_range_text': '参考范围',
    'reference_low': '参考下限',
    'reference_high': '参考上限',
    'source_text': '医嘱原文',
    'drug_name': '药名',
    'specification': '规格',
    'dosage_text': '单次剂量',
    'dosage_value': '剂量数值',
    'dosage_unit': '剂量单位',
    'frequency': '频次',
    'duration': '疗程',
    'route': '给药途径',
    'findings_text': '检查所见',
    'conclusion_text': '检查结论',
    'visit_date': '就诊日期',
    'chief_complaint': '主诉',
    'diagnosis_summary': '诊断摘要',
    'treatment_plan': '处理意见',
    'medical_advice': '医嘱',
  };

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      final map = value as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:
            map.entries
                .where((entry) => entry.key != 'confidence')
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _JsonFields(
                      label: labels[entry.key] ?? entry.key.toString(),
                      value: entry.value,
                      onChanged: (next) {
                        map[entry.key] = next;
                        onChanged(map);
                      },
                    ),
                  ),
                )
                .toList(),
      );
    }
    if (value is List) {
      final list = value as List;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                label!,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ...List.generate(
            list.length,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: pomiLine),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _JsonFields(
                label: '${label ?? '项目'} ${index + 1}',
                value: list[index],
                onChanged: (next) {
                  list[index] = next;
                  onChanged(list);
                },
              ),
            ),
          ),
        ],
      );
    }
    final original = value;
    return TextFormField(
      initialValue: value?.toString() ?? '',
      enabled: label != '材料类型',
      maxLines: _longField(label) ? 3 : 1,
      decoration: InputDecoration(labelText: label),
      onChanged: (text) {
        if (original is num) {
          onChanged(num.tryParse(text) ?? text);
        } else {
          onChanged(text.isEmpty ? null : text);
        }
      },
    );
  }

  bool _longField(String? name) =>
      const {'医嘱原文', '检查所见', '检查结论', '主诉', '诊断摘要', '处理意见', '医嘱'}.contains(name);
}

Map<String, dynamic> buildOcrConfirmationPayload({
  required String documentType,
  required String resultId,
  required String revisionId,
  required Map<String, dynamic> draft,
}) {
  if (documentType == 'lab_report') {
    final items = (draft['items'] as List? ?? const []).whereType<Map>().toList(
      growable: false,
    );
    return {
      'result_id': resultId,
      'expected_revision_id': revisionId,
      'sample_date': draft['sample_date'],
      'report_date': draft['report_date'],
      'items': [
        for (var index = 0; index < items.length; index++)
          {
            'source_index': index,
            'name': items[index]['item_name'],
            'value': items[index]['raw_value'] ?? items[index]['numeric_value'],
            'unit': items[index]['raw_unit'] ?? items[index]['normalized_unit'],
            'reference_range': items[index]['reference_range_text'],
          },
      ],
    };
  }
  if (documentType == 'medical_order') {
    final orders = (draft['orders'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    return {
      'result_id': resultId,
      'expected_revision_id': revisionId,
      'items': [
        for (var index = 0; index < orders.length; index++)
          {
            'source_index': index,
            'confirmed': true,
            'source_text': orders[index]['source_text'],
            'drug_name': orders[index]['drug_name'],
            'specification': orders[index]['specification'],
            'dosage_value': orders[index]['dosage_value'],
            'dosage_unit': orders[index]['dosage_unit'],
            'frequency': orders[index]['frequency'],
            'duration': orders[index]['duration'],
            'route': orders[index]['route'],
            'instruction': orders[index]['instruction'],
            'prescribed_at': draft['prescribed_at'],
            'explicitly_stopped': orders[index]['explicitly_stopped'] ?? false,
          },
      ],
    };
  }
  if (documentType == 'imaging_text_report' ||
      documentType == 'outpatient_record') {
    return {
      'result_id': resultId,
      'expected_revision_id': revisionId,
      'document_type': documentType,
      'confirmed_data': draft,
      'field_confirmations': const [],
      'confirm_all': true,
    };
  }
  throw ArgumentError.value(
    documentType,
    'documentType',
    'unsupported OCR material type',
  );
}
