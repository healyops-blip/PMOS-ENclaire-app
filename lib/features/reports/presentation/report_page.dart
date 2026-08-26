import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_line_chart.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/certification/presentation/certification_page.dart';

class ReportGeneratorPage extends StatefulWidget {
  const ReportGeneratorPage({super.key});

  @override
  State<ReportGeneratorPage> createState() => _ReportGeneratorPageState();
}

class _ReportGeneratorPageState extends State<ReportGeneratorPage> {
  final _noteController = TextEditingController(
    text: '最近两个月经期仍不规律，体重略有下降。二甲双胍偶尔因胃部不适漏服，希望复诊时讨论剂量。',
  );

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
                  controller: _noteController,
                  minLines: 5,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: '描述近期症状、用药感受和希望与医生讨论的问题',
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  '自述原文将按当前内容进入报告，不经过模型改写。',
                  style: Theme.of(context).textTheme.bodySmall,
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
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const ReportPage()),
            ),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('生成报告快照'),
          ),
          const SizedBox(height: 10),
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

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('report-page'),
      appBar: AppBar(
        title: const Text('复诊报告'),
        actions: [
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('PDF 导出将在后端接入后启用'))),
            icon: const Icon(Icons.ios_share_outlined),
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
            '近 6 个月体重缓慢下降，血糖与 HbA1c 保持稳定；总睾酮本次轻度超出参考上限。当前用药完成率 85%，建议复诊时重点讨论二甲双胍胃部不适与剂量。',
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
                  PomiPill(label: '完成率 85%', color: PomiColors.success),
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
        const SizedBox(height: 18),
        const PomiSectionTitle(title: '签字与测试链'),
        const SizedBox(height: 8),
        PomiSectionCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CertificationPage()),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: PomiColors.success,
                size: 32,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '陈医生签字 · KYC 已通过',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '测试链确认中 · 查看完整流转记录',
                      style: TextStyle(
                        color: PomiColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded),
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
