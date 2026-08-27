import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_line_chart.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_pdf_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_repository.dart';
import 'package:pmos_enclaire/features/reports/presentation/report_viewer_page.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:printing/printing.dart';

enum _PdfAction { save, share, print }

class ReportGeneratorPage extends StatefulWidget {
  ReportGeneratorPage({
    required this.repository,
    ReportRepository? reportRepository,
    ReportPdfRepository? reportPdfRepository,
    DocumentRepository? documentRepository,
    CertificationRepository? certificationRepository,
    super.key,
  }) : reportRepository = reportRepository ?? DemoReportRepository(),
       reportPdfRepository = reportPdfRepository ?? DemoReportPdfRepository(),
       documentRepository = documentRepository ?? DemoDocumentRepository(),
       certificationRepository =
           certificationRepository ?? LocalCertificationRepository();

  final PatientNoteRepository repository;
  final ReportRepository reportRepository;
  final ReportPdfRepository reportPdfRepository;
  final DocumentRepository documentRepository;
  final CertificationRepository certificationRepository;

  @override
  State<ReportGeneratorPage> createState() => _ReportGeneratorPageState();
}

class _ReportGeneratorPageState extends State<ReportGeneratorPage> {
  final _noteController = TextEditingController();
  PatientNote? _note;
  bool _busy = true;
  String? _error;
  List<ReportSnapshotItem> _reports = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.repository.latest(),
        widget.reportRepository.list(),
      ]);
      final note = values[0] as PatientNote?;
      if (!mounted) return;
      setState(() {
        _note = note;
        _reports = values[1] as List<ReportSnapshotItem>;
        _noteController.text = note?.originalText ?? '';
        _busy = false;
      });
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  Future<PatientNote> _saveCurrent() async {
    final current = _note;
    if (current == null) return widget.repository.create(_noteController.text);
    if (current.status == PatientNoteStatus.consumed) {
      final copied = await widget.repository.copy(current.id);
      return widget.repository.update(copied.id, _noteController.text);
    }
    return widget.repository.update(current.id, _noteController.text);
  }

  Future<void> _run(Future<PatientNote> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await action();
      if (mounted) {
        setState(() {
          _note = note;
          _noteController.text = note.originalText;
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() => _run(() async {
    final saved = await _saveCurrent();
    return widget.repository.confirm(saved.id);
  });

  Future<void> _skip() => _run(() async {
    var current = _note;
    if (current == null || current.status == PatientNoteStatus.consumed) {
      current = await widget.repository.create('');
    }
    return widget.repository.skip(current.id);
  });

  Future<void> _copy() => _run(() async {
    final copied = await widget.repository.copy(_note!.id);
    return copied;
  });

  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preflight = await widget.reportRepository.preflight(_note?.id);
      var confirmed = preflight.missingSections.isEmpty;
      if (!confirmed && mounted) {
        confirmed =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('资料尚不完整'),
                content: Text(
                  '以下区块将显示固定空状态：${preflight.missingSections.join('、')}。\n仍要继续生成吗？',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('返回补充'),
                  ),
                  FilledButton(
                    key: const Key('confirm-incomplete-report'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认继续'),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (!confirmed) return;
      final report = await widget.reportRepository.create(
        _note?.id,
        confirmIncomplete: preflight.missingSections.isNotEmpty,
      );
      final reports = await widget.reportRepository.list();
      if (!mounted) return;
      setState(() => _reports = reports);
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReportViewerPage(
            report: report,
            repository: widget.reportRepository,
            documentRepository: widget.documentRepository,
            certificationRepository: widget.certificationRepository,
            pdfRepository: widget.reportPdfRepository,
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReport(ReportSnapshotItem report) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportViewerPage(
            report: report,
            repository: widget.reportRepository,
            documentRepository: widget.documentRepository,
            certificationRepository: widget.certificationRepository,
            pdfRepository: widget.reportPdfRepository,
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('report-generator-page'),
      appBar: AppBar(title: const Text('生成复诊报告')),
      backgroundColor: PomiColors.surfaceMuted,
      body: ListView(
        key: const Key('report-generator-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const PomiSectionCard(
            color: PomiColors.primaryPale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fact_check_outlined, color: PomiColors.primary),
                    SizedBox(width: 8),
                    Text(
                      '数据覆盖检查',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _CoverageRow('已确认化验指标', '18 项', true),
                _CoverageRow('当前用药', '3 种', true),
                _CoverageRow('经期记录', '6 个周期', true),
                _CoverageRow('体重记录', '12 条', true),
                _CoverageRow('待确认材料', '1 份，不进入报告', false, last: true),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const PomiSectionTitle(title: '患者自述'),
          const SizedBox(height: 8),
          PomiSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('patient-note-field'),
                  controller: _noteController,
                  onChanged: (_) => setState(() {}),
                  minLines: 5,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: '描述近期症状、用药感受和希望与医生讨论的问题',
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '患者自述，仅供参考，不构成诊断，不进入正式病历。原文不会经过模型改写。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Chip(label: Text(_noteStatusLabel(_note?.status))),
                    const Spacer(),
                    if (_busy)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('save-patient-note-draft'),
                      onPressed: _busy ? null : () => _run(_saveCurrent),
                      child: const Text('保存草稿'),
                    ),
                    FilledButton(
                      key: const Key('confirm-patient-note'),
                      onPressed: _busy || _noteController.text.trim().isEmpty
                          ? null
                          : _confirm,
                      child: const Text('确认原文'),
                    ),
                    TextButton(
                      key: const Key('skip-patient-note'),
                      onPressed: _busy ? null : _skip,
                      child: const Text('本次跳过'),
                    ),
                    if (_note?.status == PatientNoteStatus.confirmed ||
                        _note?.status == PatientNoteStatus.consumed)
                      TextButton(
                        key: const Key('copy-patient-note'),
                        onPressed: _busy ? null : _copy,
                        child: const Text('复制为新草稿'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const PomiSectionTitle(title: '报告将包含'),
          const SizedBox(height: 8),
          const PomiSectionCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PomiPill(
                  label: '60 秒摘要',
                  color: PomiColors.primary,
                  icon: Icons.bolt_rounded,
                ),
                PomiPill(
                  label: '指标趋势',
                  color: Color(0xFF2A7BC8),
                  icon: Icons.show_chart_rounded,
                ),
                PomiPill(
                  label: '用药三状态',
                  color: PomiColors.success,
                  icon: Icons.medication_outlined,
                ),
                PomiPill(
                  label: '来源追溯',
                  color: Color(0xFFB8860B),
                  icon: Icons.manage_search_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('generate-report-button'),
            onPressed:
                !_busy &&
                    ((_note?.status == PatientNoteStatus.confirmed &&
                            _noteController.text == _note?.originalText) ||
                        _note?.status == PatientNoteStatus.skipped)
                ? _generate
                : null,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('继续查看报告演示'),
          ),
          const SizedBox(height: 10),
          if (_reports.isNotEmpty) ...[
            const PomiSectionTitle(title: '历史报告'),
            const SizedBox(height: 8),
            for (final report in _reports)
              Card(
                key: Key('report-history-${report.reportId}'),
                child: ListTile(
                  title: Text('报告 ${report.generatedAt.toLocal()}'),
                  subtitle: Text(
                    report.hasUpdates
                        ? '该报告生成后有新数据，可重新生成'
                        : report.previousReportId == null
                        ? '首个成功版本'
                        : '关联上一成功版本',
                  ),
                  trailing: report.hasUpdates
                      ? const Icon(Icons.update_rounded)
                      : const Icon(Icons.lock_outline_rounded),
                  onTap: _busy ? null : () => _openReport(report),
                ),
              ),
            const SizedBox(height: 10),
          ],
          const Text(
            '报告只使用用户已确认的数据 · 模拟数据不构成诊断',
            textAlign: TextAlign.center,
            style: TextStyle(color: PomiColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

String _noteStatusLabel(PatientNoteStatus? status) => switch (status) {
  null => '尚未保存',
  PatientNoteStatus.draft => '草稿 · 待确认',
  PatientNoteStatus.confirmed => '原文已确认',
  PatientNoteStatus.skipped => '本次已明确跳过',
  PatientNoteStatus.consumed => '已用于历史报告 · 只读',
};

class ReportPage extends StatefulWidget {
  const ReportPage({this.report, super.key});

  final ReportSnapshotItem? report;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  int _layer = 0;
  String _metricKey = 'glu';

  static const _metrics = <String, _MetricData>{
    'glu': _MetricData(
      title: '空腹血糖',
      value: '5.6 mmol/L',
      status: '参考范围内',
      values: [5.9, 5.7, 5.8, 5.5, 5.4, 5.6],
      labels: ['9月', '11月', '2月', '4月', '6月', '8月'],
      normalLow: 3.9,
      normalHigh: 6.1,
    ),
    'a1c': _MetricData(
      title: 'HbA1c',
      value: '5.5 %',
      status: '稳定',
      values: [5.9, 5.8, 5.8, 5.7, 5.6, 5.5],
      labels: ['9月', '11月', '2月', '4月', '6月', '8月'],
      normalLow: 4,
      normalHigh: 6,
    ),
    'tt': _MetricData(
      title: '总睾酮',
      value: '0.9 ng/mL',
      status: '高于参考上限',
      values: [1.1, 1.0, 0.85, 0.78, 0.82, 0.9],
      labels: ['9月', '11月', '2月', '4月', '6月', '8月'],
      normalLow: 0.2,
      normalHigh: 0.8,
      abnormal: true,
    ),
    'tg': _MetricData(
      title: '甘油三酯',
      value: '1.4 mmol/L',
      status: '参考范围内',
      values: [1.7, 1.6, 1.55, 1.5, 1.45, 1.4],
      labels: ['9月', '11月', '2月', '4月', '6月', '8月'],
      normalLow: 0.45,
      normalHigh: 1.7,
    ),
  };

  Future<Uint8List> _buildPdf() async {
    final logoData = await rootBundle.load('assets/images/pomi_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    final document = pw.Document(
      title: 'POMI PCOS Visit Preparation Report',
      author: 'POMI',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Row(
            children: [
              pw.Image(logo, width: 56, height: 56, fit: pw.BoxFit.cover),
              pw.SizedBox(width: 14),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'POMI PCOS VISIT REPORT',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#6A4C93'),
                    ),
                  ),
                  pw.Text('Demo patient / Generated 2026-08-27'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            color: PdfColor.fromHex('#F5F0F9'),
            child: pw.Text(
              'Patient statement (verbatim): Irregular menstrual cycles during the past two months. Occasional missed metformin doses due to stomach discomfort.',
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Latest confirmed indicators',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Indicator', 'Value', 'Reference / status'],
            data: const [
              ['Fasting glucose', '5.6 mmol/L', '3.9 - 6.1'],
              ['HbA1c', '5.5 %', '4.0 - 6.0'],
              ['Total testosterone', '0.9 ng/mL', 'Above 0.8'],
              ['Triglycerides', '1.4 mmol/L', '0.45 - 1.70'],
            ],
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#EDE5F3'),
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Current medications',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.Bullet(text: 'Metformin XR 850 mg / once daily'),
          pw.Bullet(text: 'Folic acid 0.4 mg / once daily'),
          pw.Bullet(text: 'Vitamin D3 1000 IU / once daily'),
          pw.SizedBox(height: 22),
          pw.Divider(),
          pw.Text(
            'Demo data only. Patient-reported information is for visit preparation and does not constitute diagnosis, treatment advice, or an official medical record.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> _handlePdf(_PdfAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在生成 PDF…')));
    try {
      final bytes = await _buildPdf();
      switch (action) {
        case _PdfAction.save:
          await FilePicker.platform.saveFile(
            fileName: 'pomi-visit-report-20260827.pdf',
            bytes: bytes,
            type: FileType.custom,
            allowedExtensions: const ['pdf'],
          );
        case _PdfAction.share:
          await Printing.sharePdf(
            bytes: bytes,
            filename: 'pomi-visit-report-20260827.pdf',
            subject: 'POMI 复诊准备报告',
          );
        case _PdfAction.print:
          await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(switch (action) {
              _PdfAction.save => 'PDF 已生成',
              _PdfAction.share => '已打开系统分享面板',
              _PdfAction.print => '已打开系统打印面板',
            }),
          ),
        );
      }
    } on Exception {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('PDF 操作失败，但 App 内报告不受影响')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.report?.snapshot;
    if (snapshot != null) {
      return Scaffold(
        key: const Key('report-page'),
        appBar: AppBar(title: const Text('复诊报告')),
        backgroundColor: PomiColors.surfaceMuted,
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              color: Colors.white,
              child: Row(
                children: [
                  _LayerChip(
                    index: 0,
                    current: _layer,
                    label: '1 · 摘要',
                    onTap: _setLayer,
                  ),
                  const SizedBox(width: 7),
                  _LayerChip(
                    index: 1,
                    current: _layer,
                    label: '2 · 趋势',
                    onTap: _setLayer,
                  ),
                  const SizedBox(width: 7),
                  _LayerChip(
                    index: 2,
                    current: _layer,
                    label: '3 · 来源',
                    onTap: _setLayer,
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_layer) {
                0 => _SnapshotSummaryLayer(snapshot: snapshot),
                1 => _SnapshotTrendLayer(snapshot: snapshot),
                _ => _SnapshotSourceLayer(snapshot: snapshot),
              },
            ),
          ],
        ),
      );
    }
    return Scaffold(
      key: const Key('report-page'),
      appBar: AppBar(
        title: const Text('复诊报告'),
        actions: [
          PopupMenuButton<_PdfAction>(
            key: const Key('report-pdf-menu'),
            tooltip: 'PDF 操作',
            onSelected: _handlePdf,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _PdfAction.save,
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('保存 PDF'),
                ),
              ),
              PopupMenuItem(
                value: _PdfAction.share,
                child: ListTile(
                  leading: Icon(Icons.ios_share_outlined),
                  title: Text('分享 PDF'),
                ),
              ),
              PopupMenuItem(
                value: _PdfAction.print,
                child: ListTile(
                  leading: Icon(Icons.print_outlined),
                  title: Text('打印 PDF'),
                ),
              ),
            ],
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      backgroundColor: PomiColors.surfaceMuted,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            color: Colors.white,
            child: Row(
              children: [
                _LayerChip(
                  index: 0,
                  current: _layer,
                  label: '1 · 摘要',
                  onTap: _setLayer,
                ),
                const SizedBox(width: 7),
                _LayerChip(
                  index: 1,
                  current: _layer,
                  label: '2 · 趋势',
                  onTap: _setLayer,
                ),
                const SizedBox(width: 7),
                _LayerChip(
                  index: 2,
                  current: _layer,
                  label: '3 · 来源',
                  onTap: _setLayer,
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: switch (_layer) {
                0 => _SummaryLayer(
                  key: const ValueKey('report-summary'),
                  metrics: _metrics,
                  onMetric: (key) {
                    setState(() {
                      _metricKey = key;
                      _layer = 1;
                    });
                  },
                ),
                1 => _TrendLayer(
                  key: ValueKey('report-trend-$_metricKey'),
                  metric: _metrics[_metricKey]!,
                  onSource: () => setState(() => _layer = 2),
                ),
                _ => _SourceLayer(
                  key: ValueKey('report-source-$_metricKey'),
                  metric: _metrics[_metricKey]!,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  void _setLayer(int value) => setState(() => _layer = value);
}

Map<String, dynamic> _reportMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<dynamic> _reportList(Object? value) => value is List ? value : const [];

class _SnapshotSummaryLayer extends StatelessWidget {
  const _SnapshotSummaryLayer({required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final summary = _reportMap(snapshot['summary']);
    final note = summary['patient_note_text'] as String?;
    final medications = _reportList(summary['current_medications']);
    final observations = _reportList(summary['latest_observations']);
    final missing = _reportList(summary['missing_sections']);
    final disclaimers = _reportList(summary['disclaimers']);
    return ListView(
      key: const Key('snapshot-report-summary'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        const PomiSectionTitle(title: '患者自述原文'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: Text(
            note ??
                (summary['patient_note_empty_state'] == 'explicitly_skipped'
                    ? '本次已明确跳过'
                    : '未提供'),
          ),
        ),
        const SizedBox(height: 14),
        const PomiSectionTitle(title: '当前用药'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: medications.isEmpty
              ? const Text('暂无已确认用药')
              : Column(
                  children: [
                    for (final value in medications)
                      Builder(
                        builder: (_) {
                          final item = _reportMap(value);
                          return ListTile(
                            dense: true,
                            title: Text(
                              item['drug_name']?.toString() ?? '未命名用药',
                            ),
                            subtitle: Text(
                              [
                                item['dosage_value'],
                                item['dosage_unit'],
                                item['frequency'],
                              ].where((value) => value != null).join(' '),
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        const PomiSectionTitle(title: '最新已确认指标'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: observations.isEmpty
              ? const Text('暂无已确认指标')
              : Column(
                  children: [
                    for (final value in observations)
                      Builder(
                        builder: (_) {
                          final item = _reportMap(value);
                          return ListTile(
                            dense: true,
                            title: Text(
                              item['original_item_name']?.toString() ?? '指标',
                            ),
                            subtitle: Text(
                              '${item['raw_value'] ?? ''} ${item['original_unit'] ?? ''} · ${item['abnormal_status'] ?? 'unknown'}',
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 14),
          PomiSectionCard(
            color: PomiColors.primaryPale,
            child: Text('缺失资料：${missing.join('、')}（使用固定空状态）'),
          ),
        ],
        const SizedBox(height: 14),
        for (final disclaimer in disclaimers)
          Text(
            disclaimer.toString(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _SnapshotTrendLayer extends StatelessWidget {
  const _SnapshotTrendLayer({required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final trends = _reportMap(snapshot['trends']);
    final labs = _reportList(trends['labs']);
    return ListView(
      key: const Key('snapshot-report-trends'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        PomiSectionCard(
          child: Text(
            '体重 ${_reportList(trends['weights']).length} 点 · 经期 ${_reportList(trends['cycles']).length} 条 · 本月用药 ${_reportList(trends['medication_daily']).length} 条',
          ),
        ),
        const SizedBox(height: 12),
        if (labs.isEmpty)
          const PomiSectionCard(child: Text('暂无可展示的化验结果'))
        else
          for (final value in labs) ...[
            Builder(
              builder: (_) {
                final trend = _reportMap(value);
                final points = _reportList(trend['points']);
                return PomiSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trend['metric_name']?.toString() ?? '化验指标',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${trend['display_mode']} · ${trend['comparability']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (final pointValue in points)
                        Builder(
                          builder: (_) {
                            final point = _reportMap(pointValue);
                            return ListTile(
                              dense: true,
                              title: Text(
                                '${point['date'] ?? '日期缺失'} · ${point['raw_value']} ${point['original_unit'] ?? ''}',
                              ),
                              subtitle: Text(
                                point['exclusion_reason']?.toString() ??
                                    '${point['freshness']} · ${point['abnormal_status']}',
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _SnapshotSourceLayer extends StatelessWidget {
  const _SnapshotSourceLayer({required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final sources = _reportList(snapshot['sources']);
    return ListView(
      key: const Key('snapshot-report-sources'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        for (final value in sources)
          Builder(
            builder: (_) {
              final source = _reportMap(value);
              return Card(
                child: ListTile(
                  title: Text(
                    '#${source['source_number']} ${source['source_type']}',
                  ),
                  subtitle: Text(
                    source['document_revision_id'] == null
                        ? source['origin_kind']?.toString() ?? '来源未知'
                        : '${source['origin_kind']} · revision ${source['document_revision_id']}',
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _SummaryLayer extends StatelessWidget {
  const _SummaryLayer({
    required this.metrics,
    required this.onMetric,
    super.key,
  });

  final Map<String, _MetricData> metrics;
  final ValueChanged<String> onMetric;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        const _ReportHeader(),
        const SizedBox(height: 14),
        const PomiSectionTitle(title: '60 秒摘要'),
        const SizedBox(height: 8),
        const PomiSectionCard(
          color: PomiColors.primaryPale,
          child: Text(
            '最新体重记录为 69.6 kg。空腹血糖和 HbA1c 本次位于材料所列参考范围内；总睾酮本次数值高于该报告参考上限。以下内容仅整理已确认数据，不作病因解释或治疗建议。',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '关键指标'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 1.35,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            for (final entry in metrics.entries)
              _MetricCard(
                metric: entry.value,
                onTap: () => onMetric(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '患者自述'),
        const SizedBox(height: 8),
        const PomiSectionCard(
          child: Text(
            '最近两个月经期仍不规律，体重略有下降。二甲双胍偶尔因胃部不适漏服，希望复诊时讨论剂量。',
            style: TextStyle(fontSize: 12, height: 1.65),
          ),
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '体重与用药'),
        const SizedBox(height: 8),
        const PomiSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '69.6 kg',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  Spacer(),
                  PomiPill(label: '用药三状态', color: PomiColors.primary),
                ],
              ),
              SizedBox(height: 8),
              PomiLineChart(
                values: [72.1, 71.7, 71.2, 70.6, 70.1, 69.6],
                labels: ['3月', '4月', '5月', '6月', '7月', '8月'],
                color: PomiColors.glowPink,
                minY: 68,
                maxY: 73,
                height: 150,
              ),
              SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  PomiPill(label: '已服用 23', color: PomiColors.success),
                  PomiPill(label: '主动漏服 2', color: PomiColors.warning),
                  PomiPill(label: '未记录 4', color: PomiColors.textMuted),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendLayer extends StatelessWidget {
  const _TrendLayer({required this.metric, required this.onSource, super.key});

  final _MetricData metric;
  final VoidCallback onSource;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _ReportHeader(title: '${metric.title} · 完整趋势'),
        const SizedBox(height: 14),
        PomiSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      metric.value,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  PomiPill(
                    label: metric.status,
                    color: metric.abnormal
                        ? const Color(0xFFC62828)
                        : PomiColors.success,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PomiLineChart(
                values: metric.values,
                labels: metric.labels,
                normalLow: metric.normalLow,
                normalHigh: metric.normalHigh,
                color: metric.abnormal
                    ? const Color(0xFFC62828)
                    : PomiColors.primary,
                height: 220,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '逐点数据'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: Column(
            children: [
              for (var index = 0; index < metric.values.length; index++)
                _ReportDataRow(
                  date: '2026-${metric.labels[index]}',
                  value: metric.values[index].toString(),
                  last: index == metric.values.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('view-report-source-button'),
          onPressed: onSource,
          icon: const Icon(Icons.manage_search_rounded),
          label: const Text('查看原始资料与认证'),
        ),
      ],
    );
  }
}

class _SourceLayer extends StatelessWidget {
  const _SourceLayer({required this.metric, super.key});

  final _MetricData metric;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _ReportHeader(title: '${metric.title} · 来源追溯'),
        const SizedBox(height: 14),
        PomiSectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Container(
                height: 190,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF5F0F9), Color(0xFFFFF8F5)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: PomiColors.primary,
                        size: 46,
                      ),
                      SizedBox(height: 8),
                      Text('原始化验单预览 · 模拟材料'),
                      Text(
                        '未渲染真实医疗文件',
                        style: TextStyle(
                          color: PomiColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _ReportDataRow(date: '材料名称', value: '检测单 6'),
                    _ReportDataRow(date: '采样日期', value: '2026-08-25'),
                    _ReportDataRow(date: '文件版本', value: 'V2'),
                    _ReportDataRow(
                      date: 'SHA-256',
                      value: '8c3d…f1a9',
                      last: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '原始材料与结构化数据仅供复诊沟通，不构成诊断或治疗建议。',
          textAlign: TextAlign.center,
          style: TextStyle(color: PomiColors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({this.title = 'PCOS 复诊准备报告'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            const DemoBadge(label: '快照 R-026'),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          '林晓晴 · 29 岁 · 数据范围 2026-03—2026-08',
          style: TextStyle(color: PomiColors.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 10),
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [PomiColors.primary, PomiColors.glowPink],
            ),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.onTap});

  final _MetricData metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PomiSectionCard(
      color: metric.abnormal ? const Color(0xFFFFF7F7) : Colors.white,
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metric.title, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            metric.status,
            style: TextStyle(
              color: metric.abnormal
                  ? const Color(0xFFC62828)
                  : PomiColors.success,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.index,
    required this.current,
    required this.label,
    required this.onTap,
  });

  final int index;
  final int current;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final selected = index == current;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? PomiColors.primary : const Color(0xFFEDEBF0),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : PomiColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow(this.label, this.value, this.ready, {this.last = false});

  final String label;
  final String value;
  final bool ready;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: ready ? PomiColors.success : const Color(0xFFB8860B),
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          Text(
            value,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ReportDataRow extends StatelessWidget {
  const _ReportDataRow({
    required this.date,
    required this.value,
    this.last = false,
  });

  final String date;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        children: [
          Text(date, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.title,
    required this.value,
    required this.status,
    required this.values,
    required this.labels,
    required this.normalLow,
    required this.normalHigh,
    this.abnormal = false,
  });

  final String title;
  final String value;
  final String status;
  final List<double> values;
  final List<String> labels;
  final double normalLow;
  final double normalHigh;
  final bool abnormal;
}
