import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({this.modal = false, super.key});

  final bool modal;

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String _documentType = 'lab';
  Uint8List? _bytes;
  String? _fileName;
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
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _showMessage('所选文件内容为空，请重新选择');
        return;
      }
      setState(() {
        _bytes = bytes;
        _fileName = file.name;
        _idempotencyKey = null;
      });
      await _start();
    } catch (error) {
      _showMessage('读取文件失败：$error');
    }
  }

  Future<void> _takePhoto() async {
    final result = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 4096,
      maxHeight: 4096,
    );
    if (result == null) return;
    try {
      final bytes = await result.readAsBytes();
      if (bytes.isEmpty) {
        _showMessage('照片内容为空，请重试');
        return;
      }
      setState(() {
        _bytes = bytes;
        _fileName = result.name;
        _idempotencyKey = null;
      });
      await _start();
    } catch (error) {
      _showMessage('读取照片失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    final bytes = _bytes;
    final fileName = _fileName;
    if (bytes == null || fileName == null) return;
    setState(() {
      _working = true;
      _status = '正在安全上传原件';
    });
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.recognizeOcr(
        bytes: bytes,
        filename: fileName,
        materialType: _wireMaterialType,
        promptVersion: 'pomi-ocr-v1',
        consentVersion: 'pomi-external-processing-v1',
        idempotencyKey:
            _idempotencyKey ??= 'ocr-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() => _status = '识别完成');
      final resultId = result['ocr_result_id']?.toString();
      if (resultId == null) {
        throw const FormatException('识别结果缺少确认所需的版本信息，请重新识别');
      }
      final taskId = result['ocr_task_id']?.toString();
      final revisionId = result['document_revision_id']?.toString();
      final materialType =
          result['material_type']?.toString() ?? _wireMaterialType;
      final draft = Map<String, dynamic>.from(result)
        ..removeWhere((key, _) => _ocrMetadataKeys.contains(key));
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder:
              (_) => OcrConfirmScreen(
                resultId: resultId,
                taskId: taskId,
                revisionId: revisionId,
                materialType: materialType,
                resultSource: result['result_source']?.toString() ?? 'qwen3-vl',
                draft: draft,
              ),
        ),
      );
      if (mounted && confirmed == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('资料已确认，可在“记录”中查看和认证')));
        // 弹窗模式：确认成功后自动关闭上传弹窗，让打开它的入口
        // （AppShell / 记录页）在 showDialog 返回时立即刷新记录列表。
        // 否则弹窗停在原地，记录页拿不到刷新信号，新材料要重启才出现。
        if (widget.modal && Navigator.canPop(context)) {
          Navigator.of(context).pop();
          return;
        }
        setState(() {
          _bytes = null;
          _fileName = null;
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
    'outpatient' => 'outpatient_record',
    _ => 'imaging_text_report',
  };

  @override
  Widget build(BuildContext context) {
    final form = ListView(
      padding: EdgeInsets.fromLTRB(18, 8, 18, widget.modal ? 24 : 96),
      children: [
        const Text(
          '选择材料类型',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
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
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
        if (_bytes != null) ...[
          const SizedBox(height: 14),
          PomiGlassCard(
            child: ListTile(
              leading: Icon(
                _fileName!.toLowerCase().endsWith('.pdf')
                    ? Icons.picture_as_pdf
                    : Icons.image_outlined,
              ),
              title: Text(
                _fileName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: '移除',
                onPressed:
                    _working
                        ? null
                        : () => setState(() {
                          _bytes = null;
                          _fileName = null;
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
          onPressed: _bytes == null || _working ? null : _start,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('开始识别'),
        ),
      ],
    );

    if (!widget.modal) {
      return Scaffold(appBar: AppBar(title: const Text('上传资料')), body: form);
    }

    return PomiGlassCard(
      borderRadius: 28,
      backgroundOpacity: 1,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                  tooltip: '关闭上传弹窗',
                  onPressed: _working ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: form),
        ],
      ),
    );
  }
}

const _ocrMetadataKeys = {
  'ocr_task_id',
  'ocr_result_id',
  'document_id',
  'document_revision_id',
  'material_type',
  'result_source',
  'evidence',
};

class OcrConfirmScreen extends ConsumerStatefulWidget {
  const OcrConfirmScreen({
    required this.resultId,
    required this.resultSource,
    required this.draft,
    this.taskId,
    this.revisionId,
    this.materialType = 'lab_report',
    super.key,
  });

  final String resultId;
  final String resultSource;
  final Map<String, dynamic> draft;
  final String? taskId;
  final String? revisionId;
  final String materialType;

  @override
  ConsumerState<OcrConfirmScreen> createState() => _OcrConfirmScreenState();
}

class _OcrConfirmScreenState extends ConsumerState<OcrConfirmScreen> {
  late Map<String, dynamic> _draft;
  bool _saving = false;
  final _scrollController = ScrollController();

  /// 归一化后的草稿字段路径（如 `examinations.0.value`）-> 出错原因。
  final Map<String, String> _fieldErrors = {};

  /// 顶部错误横幅逐条文案，覆盖所有出错项（包括无法定位到输入框的）。
  List<String> _errorSummary = const [];

  @override
  void initState() {
    super.initState();
    _draft = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.draft)) as Map,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 后端错误路径 -> 草稿输入框路径。
  /// 化验项后端前缀是 `items.`，草稿里在 `examinations.` 下，字段名 `name` 对应
  /// 草稿的 `item_name`；影像/门诊后端包了一层 `confirmed_data.`。
  static String _toDraftPath(String backendPath) {
    var path = backendPath;
    if (path.startsWith('confirmed_data.')) {
      path = path.substring('confirmed_data.'.length);
    }
    if (path.startsWith('items.')) {
      path = 'examinations.${path.substring('items.'.length)}';
      if (path.endsWith('.name')) {
        path = '${path.substring(0, path.length - '.name'.length)}.item_name';
      }
    }
    const topRemap = {
      'hospital_name': 'hospital',
      'department_name': 'department',
    };
    return topRemap[path] ?? path;
  }

  String _friendlyLabel(String draftPath) {
    final parts = <String>[];
    for (final part in draftPath.split('.')) {
      final index = int.tryParse(part);
      parts.add(
        index != null ? '第 ${index + 1} 项' : (_JsonFields.labels[part] ?? part),
      );
    }
    return parts.join(' · ');
  }

  void _applyFieldIssues(List<Map<String, dynamic>> issues) {
    _fieldErrors.clear();
    final summary = <String>[];
    for (final issue in issues) {
      final backendPath = issue['path']?.toString() ?? '';
      final message = issue['message']?.toString() ?? '该项未通过校验';
      final draftPath = _toDraftPath(backendPath);
      _fieldErrors[draftPath] = message;
      summary.add(
        backendPath.isEmpty
            ? message
            : '「${_friendlyLabel(draftPath)}」$message',
      );
    }
    setState(() => _errorSummary = summary);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _errorSummary = const [];
      _fieldErrors.clear();
    });
    try {
      final api = ref.read(apiClientProvider);
      final materialType = widget.materialType;
      final endpoint =
          materialType == 'imaging_text_report' ||
                  materialType == 'outpatient_record'
              ? '/api/ocr/tasks/${widget.taskId}/confirm'
              : '/api/ocr/results/${widget.resultId}/confirm';
      final payload = buildOcrConfirmationPayload(
        _draft,
        materialType: materialType,
        taskId: widget.taskId,
        revisionId: widget.revisionId,
        resultId: widget.resultId,
      );
      await api.post(endpoint, data: payload);
      if (mounted) Navigator.pop(context, true);
    } on ApiFailure catch (error) {
      if (!mounted) return;
      if (error.fieldIssues.isNotEmpty) {
        _applyFieldIssues(error.fieldIssues);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
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
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          if (_errorSummary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PomiGlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '有 ${_errorSummary.length} 处需要修正',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final line in _errorSummary)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('· $line'),
                      ),
                  ],
                ),
              ),
            ),
          if (widget.resultSource == 'fallback')
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PomiGlassCard(
                padding: const EdgeInsets.all(14),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF8A6410)),
                    SizedBox(width: 10),
                    Expanded(child: Text('当前为演示兜底结果，不是外部模型的实时识别。请逐项对照原件。')),
                  ],
                ),
              ),
            ),
          const Text(
            '逐项确认',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('修改后的内容会与模型原值分开保存。'),
          const SizedBox(height: 18),
          _JsonFields(
            value: _draft,
            fieldErrors: _fieldErrors,
            onErrorCleared: (path) {
              if (_fieldErrors.remove(path) != null) setState(() {});
            },
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
  const _JsonFields({
    required this.value,
    required this.onChanged,
    this.label,
    this.path = '',
    this.fieldErrors = const {},
    this.onErrorCleared,
  });

  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final String? label;

  /// 当前节点在草稿里的点分路径，用于匹配后端 `fields[]` 的出错项。
  final String path;
  final Map<String, String> fieldErrors;
  final ValueChanged<String>? onErrorCleared;

  String _childPath(Object key) => path.isEmpty ? '$key' : '$path.$key';

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
    'name': '项目名称',
    'item_code': '项目代码',
    'raw_value': '原始数值',
    'numeric_value': '数值',
    'value': '数值',
    'source_index': '来源序号',
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
    'hospital': '医院',
    'department': '科室',
    'examinations': '检查项目',
    'medication_suggestions': '用药建议',
    'dosage': '剂量',
    'instruction': '用药说明',
    'start_date': '开始日期',
    'source_category': '药物分类',
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
                      path: _childPath(entry.key),
                      fieldErrors: fieldErrors,
                      onErrorCleared: onErrorCleared,
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
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ...List.generate(
            list.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PomiGlassCard(
                padding: const EdgeInsets.all(14),
                child: _JsonFields(
                  label: '${label ?? '项目'} ${index + 1}',
                  value: list[index],
                  path: _childPath(index),
                  fieldErrors: fieldErrors,
                  onErrorCleared: onErrorCleared,
                  onChanged: (next) {
                    list[index] = next;
                    onChanged(list);
                  },
                ),
              ),
            ),
          ),
        ],
      );
    }
    final original = value;
    final error = fieldErrors[path];
    return TextFormField(
      initialValue: value?.toString() ?? '',
      enabled: label != '材料类型',
      maxLines: _longField(label) ? 3 : 1,
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: (text) {
        if (error != null) onErrorCleared?.call(path);
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

/// 按材料类型构造「确认并入库」请求体。
///
/// - lab_report：走 /api/ocr/results/{result_id}/confirm（OCRResultConfirmRequest，
///   examinations/medication_suggestions 扁平结构，front-end 只编辑名称/值/单位/参考范围）。
/// - medical_order：走 /api/ocr/results/{result_id}/confirm，但 draft 中药品在
///   medication_suggestions 列表里，dosage 等字段一并透传。
/// - imaging_text_report / outpatient_record：走 /api/ocr/tasks/{task_id}/confirm
///   （ClinicalTextConfirmRequest：document_type + confirmed_data + field_confirmations）。
Map<String, dynamic> buildOcrConfirmationPayload(
  Map<String, dynamic> draft, {
  String materialType = 'lab_report',
  String? taskId,
  String? revisionId,
  String? resultId,
}) {
  final examinations = (draft['examinations'] as List? ?? const [])
      .whereType<Map>()
      .toList(growable: false);
  final medications = (draft['medication_suggestions'] as List? ?? const [])
      .whereType<Map>()
      .toList(growable: false);

  // 影像文字报告 / 门诊病历：临床文本确认契约。
  if (materialType == 'imaging_text_report' ||
      materialType == 'outpatient_record') {
    final confirmedData = <String, dynamic>{
      for (final key in const [
        'examination_name',
        'body_part',
        'examination_method',
        'findings_text',
        'conclusion_text',
        'examined_at',
        'reported_at',
        'hospital_name',
        'department_name',
        'doctor_name',
        'visit_date',
        'chief_complaint',
        'diagnosis_summary',
        'treatment_plan',
        'medical_advice',
      ])
        if (draft[key] != null) key: draft[key],
      // 识别响应顶层统一用 hospital/department，schema 用 *_name。
      if (draft['hospital'] != null) 'hospital_name': draft['hospital'],
      if (draft['department'] != null) 'department_name': draft['department'],
    };
    return {
      'result_id': resultId,
      'expected_revision_id': revisionId,
      'document_type': materialType,
      'confirmed_data': confirmedData,
      'field_confirmations': <Map<String, dynamic>>[],
      'confirm_all': true,
    };
  }

  // 化验 / 医嘱：扁平确认契约。
  return {
    'visit_date': draft['visit_date'],
    'examinations': [
      for (var index = 0; index < examinations.length; index++)
        {
          'source_index': index,
          'item_name': examinations[index]['item_name'],
          'value': examinations[index]['value'],
          'unit': examinations[index]['unit'],
          'reference_range': examinations[index]['reference_range'],
          if (examinations[index]['note'] != null)
            'note': examinations[index]['note'],
        },
    ],
    'medication_suggestions': [
      for (var index = 0; index < medications.length; index++)
        {
          'source_index': index,
          'drug_name': medications[index]['drug_name'],
          'dosage': medications[index]['dosage'],
          'frequency': medications[index]['frequency'],
          'duration': medications[index]['duration'],
          'instruction': medications[index]['instruction'],
          'source_text': medications[index]['source_text'],
          'source_category':
              medications[index]['source_category'] ?? 'prescribed',
          'start_date': medications[index]['start_date'] ?? draft['visit_date'],
        },
    ],
  };
}
