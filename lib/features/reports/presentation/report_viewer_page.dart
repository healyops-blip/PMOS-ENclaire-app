import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_pdf_repository.dart';
import 'package:pmos_enclaire/features/reports/data/report_repository.dart';
import 'package:pmos_enclaire/features/reports/presentation/report_pdf_panel.dart';
import 'package:printing/printing.dart';

class ReportViewerPage extends StatefulWidget {
  ReportViewerPage({
    required this.report,
    required this.repository,
    required this.documentRepository,
    required this.certificationRepository,
    ReportPdfRepository? pdfRepository,
    ReportPdfCache? pdfCache,
    ReportPdfSystemActions? pdfSystemActions,
    this.pdfPollingInterval = const Duration(milliseconds: 800),
    this.pdfMaxPolls = 45,
    super.key,
  }) : pdfRepository = pdfRepository ?? DemoReportPdfRepository(),
       pdfCache = pdfCache ?? ReportPdfCache(),
       pdfSystemActions =
           pdfSystemActions ?? const AndroidReportPdfSystemActions();

  final ReportSnapshotItem report;
  final ReportRepository repository;
  final DocumentRepository documentRepository;
  final CertificationRepository certificationRepository;
  final ReportPdfRepository pdfRepository;
  final ReportPdfCache pdfCache;
  final ReportPdfSystemActions pdfSystemActions;
  final Duration pdfPollingInterval;
  final int pdfMaxPolls;

  @override
  State<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<ReportViewerPage>
    with RestorationMixin {
  final _layer = RestorableInt(0);
  final _metricId = RestorableString('');
  final _sourceId = RestorableString('');
  final _summaryOffset = RestorableDouble(0);
  final _trendOffset = RestorableDouble(0);
  final _sourceOffset = RestorableDouble(0);
  final _summaryScroll = ScrollController();
  final _trendScroll = ScrollController();
  final _sourceScroll = ScrollController();
  final _chartTransform = TransformationController();
  ReportDetail? _detail;
  Object? _error;
  bool _loading = true;
  bool _showArchived = false;

  @override
  String? get restorationId => 'report-viewer-${widget.report.reportId}';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_layer, 'layer');
    registerForRestoration(_metricId, 'metric');
    registerForRestoration(_sourceId, 'source');
    registerForRestoration(_summaryOffset, 'summary-offset');
    registerForRestoration(_trendOffset, 'trend-offset');
    registerForRestoration(_sourceOffset, 'source-offset');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreOffset(_summaryScroll, _summaryOffset.value);
      _restoreOffset(_trendScroll, _trendOffset.value);
      _restoreOffset(_sourceScroll, _sourceOffset.value);
    });
  }

  @override
  void initState() {
    super.initState();
    _summaryScroll.addListener(
      () => _summaryOffset.value = _summaryScroll.offset,
    );
    _trendScroll.addListener(() => _trendOffset.value = _trendScroll.offset);
    _sourceScroll.addListener(() => _sourceOffset.value = _sourceScroll.offset);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.get(widget.report.reportId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        if (_metricId.value.isEmpty && detail.trends.labs.isNotEmpty) {
          _metricId.value = detail.trends.labs.first.metricId;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreOffsets());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _restoreOffset(ScrollController controller, double offset) {
    if (controller.hasClients) {
      controller.jumpTo(offset.clamp(0, controller.position.maxScrollExtent));
    }
  }

  void _restoreOffsets() {
    if (!mounted) return;
    _restoreOffset(_summaryScroll, _summaryOffset.value);
    _restoreOffset(_trendScroll, _trendOffset.value);
    _restoreOffset(_sourceScroll, _sourceOffset.value);
  }

  ReportTrend? get _selectedTrend {
    final trends = _detail?.trends.labs ?? const [];
    return trends
            .where((trend) => trend.metricId == _metricId.value)
            .firstOrNull ??
        trends.firstOrNull;
  }

  ReportSource? get _selectedSource {
    final detail = _detail;
    if (detail == null) return null;
    return detail.sourceFor(_sourceId.value);
  }

  void _openTrend(String metricId) {
    setState(() {
      _metricId.value = metricId;
      _sourceId.value = '';
      _layer.value = 1;
      _showArchived = false;
      _chartTransform.value = Matrix4.identity();
    });
  }

  void _openSource(String nodeId) {
    setState(() {
      _sourceId.value = nodeId;
      _layer.value = 2;
    });
  }

  void _backLayer() {
    if (_layer.value == 2) {
      setState(() => _layer.value = 1);
    } else if (_layer.value == 1) {
      setState(() => _layer.value = 0);
    }
  }

  @override
  void dispose() {
    _layer.dispose();
    _metricId.dispose();
    _sourceId.dispose();
    _summaryOffset.dispose();
    _trendOffset.dispose();
    _sourceOffset.dispose();
    _summaryScroll.dispose();
    _trendScroll.dispose();
    _sourceScroll.dispose();
    _chartTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _layer.value == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backLayer();
      },
      child: Scaffold(
        key: const Key('report-page'),
        backgroundColor: PomiColors.surfaceMuted,
        appBar: AppBar(
          title: Text(_layer.value == 0 ? '复诊报告' : '报告详情'),
          leading: _layer.value == 0
              ? null
              : IconButton(
                  key: const Key('report-layer-back'),
                  onPressed: _backLayer,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
          actions: [
            ReportPdfPanel(
              reportId: widget.report.reportId,
              repository: widget.pdfRepository,
              cache: widget.pdfCache,
              systemActions: widget.pdfSystemActions,
              pollingInterval: widget.pdfPollingInterval,
              maxPolls: widget.pdfMaxPolls,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: DemoBadge(
                  label:
                      '只读 ${widget.report.reportId.substring(0, widget.report.reportId.length.clamp(0, 8))}',
                ),
              ),
            ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _detail == null) {
      return _LoadError(error: _error, onRetry: _load);
    }
    final detail = _detail!;
    return Column(
      children: [
        _LayerRail(layer: _layer.value),
        if (detail.item.hasUpdates)
          const _UpdateBanner(key: Key('report-update-banner')),
        Expanded(
          child: IndexedStack(
            index: _layer.value,
            children: [
              _SummaryLayer(
                detail: detail,
                controller: _summaryScroll,
                onMetric: _openTrend,
              ),
              _TrendLayer(
                detail: detail,
                trend: _selectedTrend,
                controller: _trendScroll,
                transformController: _chartTransform,
                showArchived: _showArchived,
                onShowArchived: () => setState(() => _showArchived = true),
                onMetric: _openTrend,
                onSource: _openSource,
              ),
              _SourceLayer(
                source: _selectedSource,
                controller: _sourceScroll,
                documentRepository: widget.documentRepository,
                certificationRepository: widget.certificationRepository,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayerRail extends StatelessWidget {
  const _LayerRail({required this.layer});

  final int layer;

  @override
  Widget build(BuildContext context) {
    const labels = ['1 · 摘要', '2 · 趋势', '3 · 来源'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: index == layer
                      ? PomiColors.primary
                      : index < layer
                      ? PomiColors.primaryPale
                      : const Color(0xFFEDEBF0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: index == layer ? Colors.white : PomiColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (index < labels.length - 1) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xFFFFF4D8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: const Row(
      children: [
        Icon(Icons.update_rounded, size: 17, color: Color(0xFF8A6200)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '该报告生成后有新数据，可重新生成；当前版本内容不会改变。',
            style: TextStyle(fontSize: 11, color: Color(0xFF684B00)),
          ),
        ),
      ],
    ),
  );
}

class _SummaryLayer extends StatelessWidget {
  const _SummaryLayer({
    required this.detail,
    required this.controller,
    required this.onMetric,
  });

  final ReportDetail detail;
  final ScrollController controller;
  final ValueChanged<String> onMetric;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final nickname = summary.profile['nickname']?.toString() ?? '未填写姓名';
    final condition = summary.profile['primary_condition']?.toString();
    return ListView(
      key: const Key('report-summary-scroll'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        _SnapshotHeader(detail: detail),
        const SizedBox(height: 14),
        PomiSectionCard(
          color: PomiColors.primaryPale,
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(nickname.characters.firstOrNull ?? 'P'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      [
                        ?condition,
                        if (summary.profile['birth_date'] != null)
                          '出生 ${summary.profile['birth_date']}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '患者自述原文'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: Text(
            summary.patientNoteText ??
                (summary.patientNoteEmptyState == 'explicitly_skipped'
                    ? '本次已明确跳过患者自述。'
                    : '本次报告快照中没有患者自述。'),
            key: const Key('report-patient-note'),
            style: const TextStyle(height: 1.6),
          ),
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '当前用药'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: summary.currentMedications.isEmpty
              ? const Text('本次快照中没有当前用药。')
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < summary.currentMedications.length;
                      index++
                    )
                      _MedicationRow(
                        value: summary.currentMedications[index],
                        last: index == summary.currentMedications.length - 1,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '最新检查指标'),
        const SizedBox(height: 8),
        if (detail.trends.labs.isEmpty)
          const PomiSectionCard(child: Text('本次快照中没有已确认化验指标。'))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.25,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: detail.trends.labs.length,
            itemBuilder: (context, index) => _MetricCard(
              trend: detail.trends.labs[index],
              onTap: () => onMetric(detail.trends.labs[index].metricId),
            ),
          ),
        const SizedBox(height: 18),
        _FreshnessNotice(summary: summary),
        const SizedBox(height: 14),
        for (final disclaimer in summary.disclaimers)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              '• $disclaimer',
              style: const TextStyle(fontSize: 10, color: PomiColors.textMuted),
            ),
          ),
      ],
    );
  }
}

class _TrendLayer extends StatelessWidget {
  const _TrendLayer({
    required this.detail,
    required this.trend,
    required this.controller,
    required this.transformController,
    required this.showArchived,
    required this.onShowArchived,
    required this.onMetric,
    required this.onSource,
  });

  final ReportDetail detail;
  final ReportTrend? trend;
  final ScrollController controller;
  final TransformationController transformController;
  final bool showArchived;
  final VoidCallback onShowArchived;
  final ValueChanged<String> onMetric;
  final ValueChanged<String> onSource;

  @override
  Widget build(BuildContext context) {
    final selected = trend;
    if (selected == null) {
      return const Center(child: Text('本次快照没有可查看的化验趋势。'));
    }
    final archived = selected.points
        .where((point) => point.defaultCollapsed)
        .toList();
    final visible = showArchived
        ? selected.points
        : selected.points.where((point) => !point.defaultCollapsed).toList();
    return ListView(
      key: const Key('report-trend-scroll'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        Text('完整趋势', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        SingleChildScrollView(
          key: const Key('report-metric-selector'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final value in detail.trends.labs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('report-metric-${value.metricId}'),
                    label: Text(value.metricName),
                    selected: value.metricId == selected.metricId,
                    onSelected: (_) => onMetric(value.metricId),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PomiSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selected.metricName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  PomiPill(
                    label: _displayMode(selected.displayMode),
                    color: PomiColors.primary,
                  ),
                ],
              ),
              if (selected.comparabilityReason != null) ...[
                const SizedBox(height: 7),
                Text(
                  '可比性提示：${_reason(selected.comparabilityReason!)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: PomiColors.warning,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              InteractiveViewer(
                key: const Key('report-trend-interactive'),
                transformationController: transformController,
                minScale: 1,
                maxScale: 2.4,
                panEnabled: visible.length > 4,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width - 64,
                  child: _TraceableChart(points: visible, onSource: onSource),
                ),
              ),
              if (archived.isNotEmpty && !showArchived) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('expand-archived-points'),
                  onPressed: onShowArchived,
                  icon: const Icon(Icons.history_rounded),
                  label: Text('展开 12 个月前数据（${archived.length}）'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '逐点数据'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: Column(
            children: [
              for (var index = 0; index < visible.length; index++)
                _PointRow(
                  point: visible[index],
                  unit: selected.unit,
                  last: index == visible.length - 1,
                  onTap: () => onSource(visible[index].nodeId),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _AdditionalTrends(detail: detail, onSource: onSource),
      ],
    );
  }
}

class _TraceableChart extends StatelessWidget {
  const _TraceableChart({required this.points, required this.onSource});

  final List<ReportTrendPoint> points;
  final ValueChanged<String> onSource;

  @override
  Widget build(BuildContext context) {
    final numeric = points
        .where((point) => point.normalizedValue != null)
        .toList();
    if (numeric.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: Text('没有可绘制的数值点')),
      );
    }
    final comparable = numeric.where((point) => point.isComparable).toList();
    final incomparable = numeric.where((point) => !point.isComparable).toList();
    final values = numeric
        .map((point) => point.normalizedValue!.toDouble())
        .toList();
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final spread = (maximum - minimum).abs();
    final barPoints = <List<ReportTrendPoint>>[
      if (comparable.isNotEmpty) comparable,
      for (final point in incomparable) [point],
    ];
    return SizedBox(
      height: 230,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (numeric.length - 1).clamp(1, 999).toDouble(),
          minY: minimum - (spread == 0 ? 1 : spread * .25),
          maxY: maximum + (spread == 0 ? 1 : spread * .25),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0x126A4C93)),
          ),
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 38),
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent ||
                  response?.lineBarSpots?.isEmpty != false) {
                return;
              }
              final spot = response!.lineBarSpots!.first;
              final group = barPoints[spot.barIndex];
              onSource(group[spot.spotIndex].nodeId);
            },
          ),
          lineBarsData: [
            if (comparable.isNotEmpty)
              LineChartBarData(
                spots: [
                  for (final point in comparable)
                    FlSpot(
                      numeric.indexOf(point).toDouble(),
                      point.normalizedValue!.toDouble(),
                    ),
                ],
                isCurved: comparable.length >= 3,
                barWidth: comparable.length >= 2 ? 3 : 0,
                color: PomiColors.primary,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: comparable.length >= 3,
                  color: PomiColors.primary.withValues(alpha: .1),
                ),
              ),
            for (final point in incomparable)
              LineChartBarData(
                spots: [
                  FlSpot(
                    numeric.indexOf(point).toDouble(),
                    point.normalizedValue!.toDouble(),
                  ),
                ],
                barWidth: 0,
                color: PomiColors.warning,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 6,
                    color: Colors.white,
                    strokeColor: PomiColors.warning,
                    strokeWidth: 3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdditionalTrends extends StatelessWidget {
  const _AdditionalTrends({required this.detail, required this.onSource});

  final ReportDetail detail;
  final ValueChanged<String> onSource;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PomiSectionTitle(title: '经期、体重与本月用药'),
      const SizedBox(height: 8),
      PomiSectionCard(
        child: Column(
          children: [
            _CompactTrendRow(
              key: const Key('cycle-history-row'),
              icon: Icons.water_drop_outlined,
              label: '经期历史',
              points: detail.trends.cycles,
              onSource: onSource,
            ),
            _CompactTrendRow(
              key: const Key('weight-trend-row'),
              icon: Icons.monitor_weight_outlined,
              label: '体重趋势',
              points: detail.trends.weights,
              onSource: onSource,
            ),
            _CompactTrendRow(
              key: const Key('medication-month-row'),
              icon: Icons.medication_outlined,
              label: '本月用药记录',
              points: detail.trends.medicationDaily,
              onSource: onSource,
              last: true,
            ),
          ],
        ),
      ),
    ],
  );
}

class _CompactTrendRow extends StatelessWidget {
  const _CompactTrendRow({
    required this.icon,
    required this.label,
    required this.points,
    required this.onSource,
    this.last = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final List<ReportTrendPoint> points;
  final ValueChanged<String> onSource;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
    ),
    child: Row(
      children: [
        Icon(icon, color: PomiColors.primary, size: 19),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
        if (points.isEmpty)
          const Text('无记录', style: TextStyle(color: PomiColors.textMuted))
        else
          TextButton(
            key: Key('trace-${points.last.nodeId}'),
            onPressed: () => onSource(points.last.nodeId),
            child: Text('${points.length} 条 · 查看来源'),
          ),
      ],
    ),
  );
}

class _SourceLayer extends StatefulWidget {
  const _SourceLayer({
    required this.source,
    required this.controller,
    required this.documentRepository,
    required this.certificationRepository,
  });

  final ReportSource? source;
  final ScrollController controller;
  final DocumentRepository documentRepository;
  final CertificationRepository certificationRepository;

  @override
  State<_SourceLayer> createState() => _SourceLayerState();
}

class _SourceLayerState extends State<_SourceLayer> {
  CertificationRecord? _certification;

  @override
  void initState() {
    super.initState();
    _readCertification();
  }

  @override
  void didUpdateWidget(covariant _SourceLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source?.nodeId != widget.source?.nodeId) _readCertification();
  }

  Future<void> _readCertification() async {
    final source = widget.source;
    if (source?.documentId == null || source?.documentRevisionId == null) {
      if (mounted) setState(() => _certification = null);
      return;
    }
    try {
      final record = await widget.certificationRepository.read(
        source!.documentId!,
        source.documentRevisionId!,
      );
      if (mounted && widget.source?.nodeId == source.nodeId) {
        setState(() => _certification = record);
      }
    } on Object {
      if (mounted && widget.source?.nodeId == source!.nodeId) {
        setState(() => _certification = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    if (source == null) {
      return const Center(child: Text('请先在趋势页选择一个数据点。'));
    }
    return ListView(
      key: const Key('report-source-scroll'),
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '来源 #${source.sourceNumber}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            PomiPill(
              label: source.isManual
                  ? '患者手工记录'
                  : _sourceType(source.sourceType),
              color: source.isManual ? PomiColors.warning : PomiColors.primary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        PomiSectionCard(
          color: source.isManual ? const Color(0xFFFFF8E8) : Colors.white,
          child: Column(
            children: [
              _SourceRow(
                '原始值',
                _valueWithUnit(source.originalValue, source.originalUnit),
              ),
              _SourceRow(
                '归一化值',
                _valueWithUnit(
                  source.normalizedValue?.toString(),
                  source.normalizedUnit,
                ),
              ),
              _SourceRow('参考范围', source.referenceRangeText ?? '快照未提供'),
              _SourceRow('材料日期', _date(source.materialDate)),
              _SourceRow('日期来源', _dateSource(source.dateSource)),
              _SourceRow('新鲜度', _freshness(source.freshness)),
              _SourceRow('可比性', _comparability(source.comparability)),
              if (source.exclusionReason != null)
                _SourceRow('不可比原因', _reason(source.exclusionReason!)),
              _SourceRow(
                '业务记录',
                '${_sourceType(source.sourceType)} · ${source.sourceRecordId}',
              ),
              _SourceRow('材料 ID', source.documentId ?? '无（手工记录）'),
              _SourceRow('明确修订', source.documentRevisionId ?? '不适用'),
              if (source.ruleExecutionId != null)
                _SourceRow('规则执行', source.ruleExecutionId!),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _OriginalFileCard(
          source: source,
          hasWatermark: _certification?.status == CertificationStatus.succeeded,
          onOpen: source.file?.isAvailable == true
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _OriginalFileViewer(
                      source: source,
                      repository: widget.documentRepository,
                      showWatermark:
                          _certification?.status ==
                          CertificationStatus.succeeded,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        const Text(
          '来源信息来自该报告的不可变快照。原件状态变化不会改写报告中的医疗内容。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: PomiColors.textMuted),
        ),
      ],
    );
  }
}

class _OriginalFileCard extends StatelessWidget {
  const _OriginalFileCard({
    required this.source,
    required this.hasWatermark,
    required this.onOpen,
  });

  final ReportSource source;
  final bool hasWatermark;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final file = source.file;
    if (source.isManual) {
      return const PomiSectionCard(
        child: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: PomiColors.warning),
            SizedBox(width: 10),
            Expanded(child: Text('患者手工记录没有医院原始文件。')),
          ],
        ),
      );
    }
    return PomiSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                key: const Key('report-original-area'),
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF2ECF8), Color(0xFFFFF8F3)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        file?.isAvailable == true
                            ? Icons.description_outlined
                            : Icons.cloud_off_outlined,
                        size: 42,
                        color: file?.isAvailable == true
                            ? PomiColors.primary
                            : PomiColors.warning,
                      ),
                      const SizedBox(height: 7),
                      Text(file?.fileName ?? '原始文件暂时不可用'),
                    ],
                  ),
                ),
              ),
              if (hasWatermark)
                const _DemoWatermark(key: Key('local-certification-watermark')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                if (file?.errorMessage != null)
                  Text(
                    file!.errorMessage!,
                    key: const Key('source-file-fallback'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: PomiColors.warning,
                    ),
                  ),
                if (hasWatermark)
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Text(
                      '本机医院认证交互演示已完成 · 不代表真实认证',
                      style: TextStyle(fontSize: 10, color: PomiColors.primary),
                    ),
                  ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('open-original-report'),
                    onPressed: onOpen,
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: Text(onOpen == null ? '原始报告不可用' : '查看原始报告'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalFileViewer extends StatefulWidget {
  const _OriginalFileViewer({
    required this.source,
    required this.repository,
    required this.showWatermark,
  });

  final ReportSource source;
  final DocumentRepository repository;
  final bool showWatermark;

  @override
  State<_OriginalFileViewer> createState() => _OriginalFileViewerState();
}

class _OriginalFileViewerState extends State<_OriginalFileViewer> {
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.repository.download(
        widget.source.documentId!,
        widget.source.documentRevisionId!,
      );
      if (bytes.isEmpty) throw const DocumentFailure('EMPTY_FILE', '原始文件为空');
      if (mounted) setState(() => _bytes = bytes);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('original-file-viewer'),
    backgroundColor: const Color(0xFF17151A),
    appBar: AppBar(
      backgroundColor: const Color(0xFF17151A),
      foregroundColor: Colors.white,
      title: Text(widget.source.file?.fileName ?? '原始报告'),
    ),
    body: _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '原始文件打开失败',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '返回后仍可查看来源 #${widget.source.sourceNumber} 与快照结构化原值。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          )
        : _bytes == null
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            fit: StackFit.expand,
            children: [
              if (widget.source.file?.mimeType == 'application/pdf')
                PdfPreview(
                  build: (_) async => _bytes!,
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                )
              else
                InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Image.memory(
                    _bytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Text(
                        '图片解码失败',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              if (widget.showWatermark)
                const Center(
                  child: _DemoWatermark(key: Key('fullscreen-local-watermark')),
                ),
            ],
          ),
  );
}

class _DemoWatermark extends StatelessWidget {
  const _DemoWatermark({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Transform.rotate(
      angle: -.26,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .78),
          border: Border.all(color: PomiColors.primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '本地认证演示 · 非真实认证',
          style: TextStyle(
            color: PomiColors.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: .6,
          ),
        ),
      ),
    ),
  );
}

class _SnapshotHeader extends StatelessWidget {
  const _SnapshotHeader({required this.detail});

  final ReportDetail detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('60 秒摘要', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 5),
      Text(
        '生成于 ${_dateTime(detail.item.generatedAt)} · 快照 ${detail.item.snapshotHash.substring(0, 8)}',
        style: const TextStyle(fontSize: 10, color: PomiColors.textMuted),
      ),
      const SizedBox(height: 9),
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

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({required this.value, required this.last});

  final Map<String, dynamic> value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.medication_outlined,
          size: 18,
          color: PomiColors.primary,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(value['drug_name']?.toString() ?? '未命名药物')),
        Text(
          _valueWithUnit(
            value['dosage_value']?.toString(),
            value['dosage_unit']?.toString(),
          ),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.trend, required this.onTap});

  final ReportTrend trend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest =
        trend.points.where((point) => point.date != null).lastOrNull ??
        trend.points.lastOrNull;
    final abnormal =
        latest?.abnormalStatus == 'high' || latest?.abnormalStatus == 'low';
    return PomiSectionCard(
      key: Key('report-summary-metric-${trend.metricId}'),
      onTap: onTap,
      color: abnormal ? const Color(0xFFFFF7F5) : Colors.white,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trend.metricName, maxLines: 2, overflow: TextOverflow.ellipsis),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _valueWithUnit(
                latest?.normalizedValue?.toString() ?? latest?.rawValue,
                latest?.normalizedUnit ?? trend.unit,
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            '${_abnormal(latest?.abnormalStatus)} · 来源 #${latest?.sourceNumber ?? '—'}',
            style: TextStyle(
              fontSize: 9,
              color: abnormal ? const Color(0xFFC43D33) : PomiColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreshnessNotice extends StatelessWidget {
  const _FreshnessNotice({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) => PomiSectionCard(
    color: const Color(0xFFFFFAEE),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: PomiColors.warning),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            summary.missingSections.isEmpty
                ? '资料新鲜度按每个来源点显示；超过 12 个月的记录会在趋势页默认折叠。'
                : '快照缺失：${summary.missingSections.join('、')}。其余来源仍可逐点追溯。',
            style: const TextStyle(fontSize: 11, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.point,
    required this.unit,
    required this.last,
    required this.onTap,
  });

  final ReportTrendPoint point;
  final String? unit;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('report-point-${point.nodeId}'),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        children: [
          Icon(
            point.isComparable ? Icons.circle : Icons.circle_outlined,
            color: point.isComparable ? PomiColors.primary : PomiColors.warning,
            size: 13,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _valueWithUnit(
                    point.normalizedValue?.toString() ?? point.rawValue,
                    point.normalizedUnit ?? unit,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${_date(point.date)} · ${_dateSource(point.dateSource)} · 来源 #${point.sourceNumber}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: PomiColors.textMuted,
                  ),
                ),
                if (point.exclusionReason != null)
                  Text(
                    '独立散点：${_reason(point.exclusionReason!)}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: PomiColors.warning,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: PomiColors.textMuted),
        ],
      ),
    ),
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: PomiColors.warning,
            size: 42,
          ),
          const SizedBox(height: 10),
          const Text('报告快照加载失败'),
          const SizedBox(height: 6),
          Text(error?.toString() ?? '未知错误', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

String _displayMode(String value) => switch (value) {
  'single_result' => '单次结果',
  'comparison' => '两次对比',
  'trend' => '趋势线',
  _ => value,
};

String _sourceType(String value) => switch (value) {
  'lab_observation' => '化验记录',
  'medical_order' => '医嘱',
  'imaging_report' => '影像文字报告',
  'outpatient_record' => '门诊记录',
  'menstrual_cycle' => '经期记录',
  'weight_record' => '体重记录',
  'medication_daily' => '用药打卡',
  'patient_note' => '患者自述',
  'rule_execution' => '规则执行',
  _ => value,
};

String _dateSource(String? value) => switch (value) {
  'sample_date' => '采样日期',
  'exam_date' => '检查日期',
  'report_date' => '报告日期',
  'visit_date' => '就诊日期',
  'order_date' => '医嘱日期',
  'record_date' => '记录日期',
  null => '未提供有效日期',
  _ => value,
};

String _freshness(String value) => switch (value) {
  'current' => '近期（≤ 3 个月）',
  'caution' => '需留意（3–6 个月）',
  'stale' => '较旧（6–12 个月）',
  'archived' => '历史（> 12 个月）',
  _ => '未知',
};

String _comparability(String value) => switch (value) {
  'comparable' => '可比',
  'caution' => '需结合上下文',
  'incomparable' => '不可比 · 独立散点',
  _ => '不适用',
};

String _reason(String value) => switch (value) {
  'metric_needs_manual_review' => '指标尚需人工确认',
  'missing_valid_date' => '缺少有效日期',
  'future_date' => '日期位于未来',
  'unsafe_unit_conversion' => '单位无法安全换算',
  'sample_context_mismatch' => '采样条件不一致',
  'hormone_context_incomplete' => '激素相关上下文不完整',
  _ => value,
};

String _abnormal(String? value) => switch (value) {
  'high' => '高于参考范围',
  'low' => '低于参考范围',
  'normal' => '参考范围内',
  _ => '参考状态未知',
};

String _valueWithUnit(String? value, String? unit) =>
    [value ?? '—', if (unit != null && unit.isNotEmpty) unit].join(' ');

String _date(DateTime? value) => value == null
    ? '日期未知'
    : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _dateTime(DateTime value) =>
    '${_date(value.toLocal())} ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
