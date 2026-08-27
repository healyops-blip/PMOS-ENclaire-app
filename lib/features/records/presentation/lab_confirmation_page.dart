import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:printing/printing.dart';

class LabConfirmationPage extends StatefulWidget {
  const LabConfirmationPage({
    required this.repository,
    required this.task,
    this.documentRepository,
    super.key,
  });

  final OcrRepository repository;
  final OcrTask task;
  final DocumentRepository? documentRepository;

  @override
  State<LabConfirmationPage> createState() => _LabConfirmationPageState();
}

class _LabConfirmationPageState extends State<LabConfirmationPage> {
  late final Future<OcrTaskResult> _loading = _load();
  final List<_LabItemEditor> _items = [];
  final Map<String, String> _errors = {};
  OcrTaskResult? _result;
  Future<Uint8List>? _sourceBytes;
  LabConfirmationResult? _confirmed;
  bool _submitting = false;

  Future<OcrTaskResult> _load() async {
    final result = await widget.repository.result(widget.task.id);
    final draftItems = result.draft['items'];
    if (draftItems is List) {
      for (var index = 0; index < draftItems.length; index++) {
        final raw = draftItems[index];
        if (raw is! Map) continue;
        _items.add(
          _LabItemEditor.fromDraft(
            Map<String, dynamic>.from(raw),
            confidence: _confidence(result.fields, index),
          ),
        );
      }
    }
    if (_items.isEmpty) _items.add(_LabItemEditor.empty());
    _result = result;
    final source = result.sourceDocument;
    final documents = widget.documentRepository;
    if (source != null && documents != null) {
      _sourceBytes = documents.download(source.documentId, source.revisionId);
    }
    return result;
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(_LabItemEditor.empty()));

  void _removeItem(int index) {
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
      _errors.removeWhere((path, _) => path.startsWith('items.$index.'));
    });
  }

  Future<void> _confirm() async {
    final localErrors = _validate();
    if (localErrors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(localErrors);
      });
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认写入正式数据？'),
        content: const Text('只有本次由你确认的数据会进入趋势和报告。OCR 内容始终只是草稿，请先与原始材料逐项核对。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续核对'),
          ),
          FilledButton(
            key: const Key('confirm-lab-dialog-action'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认全部项目'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _submitting = true;
      _errors.clear();
    });
    try {
      final result = await widget.repository.confirmLab(
        taskId: widget.task.id,
        resultId: _result!.resultId,
        expectedRevisionId: widget.task.documentRevisionId,
        items: _items.map((item) => item.value).toList(),
        reportDate: _text(_result!.draft['report_date']),
      );
      if (!mounted) return;
      setState(() => _confirmed = result);
    } on OcrException catch (error) {
      if (!mounted) return;
      setState(() {
        for (final field in error.fieldErrors) {
          _errors[field.path] = field.message;
        }
        if (error.fieldErrors.isEmpty) _errors['form'] = error.message;
      });
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _errors['form'] = '提交失败，已保留全部编辑内容，请检查网络后重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      if (item.name.text.trim().isEmpty) {
        errors['items.$index.name'] = '项目名称不能为空';
      }
      if (double.tryParse(item.valueController.text.trim()) == null) {
        errors['items.$index.value'] = '请输入可解析的数值';
      }
      if (!_allowedUnits.contains(item.unit.text.trim())) {
        errors['items.$index.unit'] = '单位不在允许范围内';
      }
      for (final entry in {
        'sample_date': item.sampleDate,
        'exam_date': item.examDate,
        'report_date': item.reportDate,
        'visit_date': item.visitDate,
      }.entries) {
        final value = entry.value.text.trim();
        if (value.isNotEmpty && !_validDate(value)) {
          errors['items.$index.${entry.key}'] = '日期请使用 YYYY-MM-DD';
        }
      }
      final reference = item.referenceRange.text.trim();
      if (reference.isNotEmpty &&
          !RegExp(
            r'^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*[-~～—]\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*$|^\s*(?:<=|>=|<|>|≤|≥)\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)\s*$',
          ).hasMatch(reference)) {
        errors['items.$index.reference_range'] = '输入如 3.9-6.1，或留空';
      }
    }
    return errors;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('ocr-confirmation-lab_report'),
    appBar: AppBar(title: const Text('核对化验报告')),
    body: FutureBuilder<OcrTaskResult>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_confirmed != null) return _success(context, _confirmed!);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _sourcePanel(snapshot.data!),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('低置信度、缺失或格式异常字段会突出显示。未确认、确认失败的数据都不会进入正式趋势或报告。'),
              ),
            ),
            if (_errors['form'] case final message?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  message,
                  key: const Key('lab-submit-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (var index = 0; index < _items.length; index++)
              _itemCard(index, _items[index]),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _addItem,
              icon: const Icon(Icons.add),
              label: const Text('添加一项'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('confirm-all-lab-items'),
              onPressed: _submitting ? null : _confirm,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_submitting ? '正在确认…' : '核对完成，批量确认'),
            ),
          ],
        );
      },
    ),
  );

  Widget _sourcePanel(OcrTaskResult result) {
    final source = result.sourceDocument;
    return Card(
      key: const Key('lab-source-document'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('原始材料对照', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              source == null
                  ? '修订 ${widget.task.documentRevisionId}'
                  : '${source.fileName} · 修订 V${source.revisionNumber}',
            ),
            if (_sourceBytes case final bytesFuture?)
              FutureBuilder<Uint8List>(
                future: bytesFuture,
                builder: (context, bytes) {
                  if (bytes.hasError) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('原件暂时加载失败，字段编辑内容不会丢失。'),
                    );
                  }
                  if (!bytes.hasData) return const LinearProgressIndicator();
                  return SizedBox(
                    height: 260,
                    child: source?.mimeType == 'application/pdf'
                        ? PdfPreview(
                            build: (_) async => bytes.data!,
                            allowPrinting: false,
                            allowSharing: false,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                          )
                        : InteractiveViewer(
                            child: Image.memory(
                              bytes.data!,
                              fit: BoxFit.contain,
                            ),
                          ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(int index, _LabItemEditor item) {
    final lowConfidence = item.confidence < 0.8;
    final color =
        lowConfidence ||
            _errors.keys.any((path) => path.startsWith('items.$index.'))
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.outlineVariant;
    return Card(
      key: Key('lab-item-$index'),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '项目 ${index + 1} · 置信度 ${(item.confidence * 100).round()}%',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (lowConfidence)
                  const Chip(
                    avatar: Icon(Icons.warning_amber_rounded, size: 18),
                    label: Text('需重点核对'),
                  ),
                if (_items.length > 1)
                  IconButton(
                    onPressed: () => _removeItem(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            _field(index, 'name', '项目名称 *', item.name),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    index,
                    'value',
                    '数值 *',
                    item.valueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _field(index, 'unit', '单位 *', item.unit)),
              ],
            ),
            _field(index, 'reference_range', '参考范围（可留空）', item.referenceRange),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('日期与备注（可留空）'),
              children: [
                _field(index, 'sample_date', '采样日期', item.sampleDate),
                _field(index, 'exam_date', '检查日期', item.examDate),
                _field(index, 'report_date', '报告日期', item.reportDate),
                _field(index, 'visit_date', '就诊日期', item.visitDate),
                _field(index, 'note', '备注', item.note),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    int index,
    String name,
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      key: Key('lab-$name-$index'),
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors['items.$index.$name'],
      ),
      onChanged: (_) => setState(() => _errors.remove('items.$index.$name')),
    ),
  );

  Widget _success(BuildContext context, LabConfirmationResult result) =>
      ListView(
        key: const Key('lab-confirmation-success'),
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            Icons.verified_rounded,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            '已确认 ${result.observations.length} 项正式数据',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            '以下数据现在可以用于趋势与报告，并可追溯到本次原件修订。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          for (final item in result.observations)
            ListTile(
              title: Text(item.name),
              subtitle: Text(
                item.mappingStatus == 'needs_manual_review'
                    ? '未映射标准指标 · 已保留原名并标记人工核对'
                    : '${item.metricId} · ${item.abnormalStatus}',
              ),
              trailing: Text('${item.value} ${item.unit}'),
            ),
        ],
      );
}

class _LabItemEditor {
  _LabItemEditor({
    required this.name,
    required this.valueController,
    required this.unit,
    required this.referenceRange,
    required this.sampleDate,
    required this.examDate,
    required this.reportDate,
    required this.visitDate,
    required this.note,
    required this.confidence,
  });

  factory _LabItemEditor.fromDraft(
    Map<String, dynamic> draft, {
    required double confidence,
  }) => _LabItemEditor(
    name: TextEditingController(text: _text(draft['name'])),
    valueController: TextEditingController(text: _text(draft['value'])),
    unit: TextEditingController(text: _text(draft['unit'])),
    referenceRange: TextEditingController(
      text: _text(draft['reference_range']),
    ),
    sampleDate: TextEditingController(text: _text(draft['sample_date'])),
    examDate: TextEditingController(text: _text(draft['exam_date'])),
    reportDate: TextEditingController(text: _text(draft['report_date'])),
    visitDate: TextEditingController(text: _text(draft['visit_date'])),
    note: TextEditingController(text: _text(draft['note'])),
    confidence: confidence,
  );

  factory _LabItemEditor.empty() =>
      _LabItemEditor.fromDraft(const {}, confidence: 0);

  final TextEditingController name;
  final TextEditingController valueController;
  final TextEditingController unit;
  final TextEditingController referenceRange;
  final TextEditingController sampleDate;
  final TextEditingController examDate;
  final TextEditingController reportDate;
  final TextEditingController visitDate;
  final TextEditingController note;
  final double confidence;

  LabConfirmationItem get value => LabConfirmationItem(
    name: name.text.trim(),
    value: valueController.text.trim(),
    unit: unit.text.trim(),
    referenceRange: referenceRange.text,
    sampleDate: sampleDate.text,
    examDate: examDate.text,
    reportDate: reportDate.text,
    visitDate: visitDate.text,
    note: note.text,
  );

  void dispose() {
    name.dispose();
    valueController.dispose();
    unit.dispose();
    referenceRange.dispose();
    sampleDate.dispose();
    examDate.dispose();
    reportDate.dispose();
    visitDate.dispose();
    note.dispose();
  }
}

double _confidence(List<OcrFieldDraft> fields, int index) {
  final relevant = fields.where(
    (field) => field.path.startsWith('items.$index.'),
  );
  if (relevant.isEmpty) return 0;
  return relevant
      .map((field) => field.confidence)
      .reduce((a, b) => a < b ? a : b);
}

String _text(Object? value) => value?.toString() ?? '';

bool _validDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

const _allowedUnits = {
  'mmol/L',
  'mg/dL',
  'μIU/mL',
  'mIU/L',
  'mIU/mL',
  'IU/L',
  'nmol/L',
  'ng/dL',
  'ng/mL',
  'pmol/L',
  '%',
  'g/L',
  'mg/L',
  'U/L',
  '10^9/L',
  '10^12/L',
};
