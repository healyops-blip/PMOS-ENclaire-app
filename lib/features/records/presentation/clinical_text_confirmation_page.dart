import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pmos_enclaire/features/certification/presentation/certification_page.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:printing/printing.dart';

class ClinicalTextConfirmationPage extends StatefulWidget {
  const ClinicalTextConfirmationPage({
    required this.repository,
    required this.task,
    super.key,
  });

  final OcrRepository repository;
  final OcrTask task;

  @override
  State<ClinicalTextConfirmationPage> createState() =>
      _ClinicalTextConfirmationPageState();
}

class _ClinicalTextConfirmationPageState
    extends State<ClinicalTextConfirmationPage> {
  final _scrollController = ScrollController();
  final Map<String, TextEditingController> _controllers = {};
  OcrTaskResult? _result;
  Uint8List? _source;
  ClinicalConfirmationResult? _confirmed;
  String? _error;
  bool _submitting = false;

  bool get _imaging => widget.task.materialType == 'imaging_text_report';

  List<_ClinicalField> get _fields => _imaging
      ? const [
          _ClinicalField('facility', '医院／机构'),
          _ClinicalField('examination_name', '检查名称'),
          _ClinicalField('body_part', '检查部位'),
          _ClinicalField('modality', '检查方式'),
          _ClinicalField('examination_date', '检查日期（YYYY-MM-DD）'),
          _ClinicalField('report_date', '报告日期（YYYY-MM-DD）'),
          _ClinicalField('findings', '所见原文', critical: true, longText: true),
          _ClinicalField('impression', '结论原文', critical: true, longText: true),
        ]
      : const [
          _ClinicalField('facility', '医院／机构'),
          _ClinicalField('department', '科室'),
          _ClinicalField('doctor_name', '医生姓名'),
          _ClinicalField('visit_date', '就诊日期（YYYY-MM-DD）', critical: true),
          _ClinicalField('chief_complaint', '主诉原文', longText: true),
          _ClinicalField(
            'diagnosis_summary',
            '诊断摘要原文',
            critical: true,
            longText: true,
          ),
          _ClinicalField('treatment_plan', '治疗计划原文', longText: true),
          _ClinicalField(
            'medical_advice',
            '处理意见原文',
            critical: true,
            longText: true,
          ),
        ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        widget.repository.result(widget.task.id),
        widget.repository.sourceFile(widget.task),
      ]);
      final result = values[0] as OcrTaskResult;
      for (final field in _fields) {
        _controllers[field.key] = TextEditingController(
          text: result.draft[field.key]?.toString() ?? '',
        );
      }
      if (mounted) {
        setState(() {
          _result = result;
          _source = Uint8List.fromList(values[1] as List<int>);
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  OcrFieldDraft? _draftField(String key) {
    for (final field in _result?.fields ?? const <OcrFieldDraft>[]) {
      if (field.path == key) return field;
    }
    return null;
  }

  String? _clientError(_ClinicalField field) {
    final value = _controllers[field.key]!.text.trim();
    if (field.critical && value.isEmpty) return '关键原文不能为空';
    if (field.key.endsWith('_date') && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.isAfter(DateTime.now())) return '日期格式或范围不合理';
    }
    return null;
  }

  Future<void> _confirm() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    final errors = _fields.map(_clientError).whereType<String>();
    if (errors.isNotEmpty) {
      setState(() {
        _error = '请先解决所有高亮的关键字段';
        _submitting = false;
      });
      return;
    }
    final confirmedData = {
      for (final field in _fields)
        field.key: _controllers[field.key]!.text.trim().isEmpty
            ? null
            : _controllers[field.key]!.text.trim(),
    };
    final decisions = [
      for (final field in _fields)
        {
          'field_path': field.key,
          'user_value': confirmedData[field.key],
          'confirmation_status':
              confirmedData[field.key]?.toString() ==
                  _result!.draft[field.key]?.toString()
              ? 'confirmed'
              : 'edited',
        },
    ];
    try {
      final result = await widget.repository.confirmClinical(
        task: widget.task,
        resultId: _result!.resultId,
        confirmedData: confirmedData,
        fieldConfirmations: decisions,
      );
      if (mounted) setState(() => _confirmed = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: Key('clinical-confirmation-${widget.task.materialType}'),
    appBar: AppBar(title: Text(_imaging ? '影像文字报告确认' : '门诊病历确认')),
    body: _result == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('重试加载')),
                    ],
                  ),
          )
        : ListView(
            key: const Key('clinical-confirmation-scroll'),
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _SourcePreview(bytes: _source ?? Uint8List(0)),
              const SizedBox(height: 12),
              const Text('请对照原件逐字段核对。模型结果始终是草稿，确认后才进入正式数据。'),
              if (!_imaging)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('病历中的药物文字仅保存为原文，不会自动新增、调整或停用当前用药。'),
                ),
              const SizedBox(height: 14),
              for (final field in _fields) _fieldEditor(field),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_confirmed == null)
                FilledButton(
                  key: const Key('confirm-clinical-text'),
                  onPressed: _submitting ? null : _confirm,
                  child: Text(_submitting ? '确认保存中…' : '整份核对完成并确认'),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      key: const Key('clinical-confirmation-success'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '已确认并保存',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text('来源修订：${_confirmed!.documentRevisionId}'),
                            Text('正式记录：${_confirmed!.recordId}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CertificationEntryCard(
                      documentId: widget.task.documentId,
                      revisionId: widget.task.documentRevisionId,
                      materialLabel: _imaging ? '影像文字报告' : '门诊病历／就诊记录',
                      ocrConfirmed: true,
                    ),
                  ],
                ),
            ],
          ),
  );

  Widget _fieldEditor(_ClinicalField field) {
    final draft = _draftField(field.key);
    final uncertain =
        draft == null ||
        draft.confidence < 0.75 ||
        draft.uncertaintyReason != null ||
        _clientError(field) != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key('clinical-field-${field.key}'),
        controller: _controllers[field.key],
        minLines: field.longText ? 4 : 1,
        maxLines: field.longText ? 10 : 1,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: field.label,
          errorText:
              _clientError(field) ??
              (uncertain ? draft?.uncertaintyReason ?? '低置信度／缺失，请重点核对' : null),
          helperText: draft?.sourceText == null
              ? null
              : '识别原文：${draft!.sourceText}',
        ),
      ),
    );
  }
}

class _SourcePreview extends StatelessWidget {
  const _SourcePreview({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final pdf =
        bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-';
    return Container(
      height: 220,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: bytes.isEmpty
          ? const Center(child: Text('原件预览（演示数据无文件）'))
          : pdf
          ? PdfPreview(
              build: (_) async => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: false,
              allowSharing: false,
            )
          : InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
    );
  }
}

class _ClinicalField {
  const _ClinicalField(
    this.key,
    this.label, {
    this.critical = false,
    this.longText = false,
  });
  final String key;
  final String label;
  final bool critical;
  final bool longText;
}
