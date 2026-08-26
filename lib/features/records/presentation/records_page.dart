import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  int _selectedFilter = 0;

  static const _filters = ['全部', '化验', '处方', '影像', '门诊'];
  static const _visits = [
    _VisitData(
      date: '2026-08-25',
      hospital: '模拟医院 B · 内分泌科',
      summary: '复诊化验与用药调整',
      materials: [
        _MaterialData('检测单 6', '化验', Icons.science_outlined, true),
        _MaterialData('门诊处方 3', '处方', Icons.medication_outlined, true),
      ],
    ),
    _VisitData(
      date: '2026-05-18',
      hospital: '模拟医院 A · 妇科',
      summary: '周期评估与超声复查',
      materials: [
        _MaterialData('超声文字报告', '影像', Icons.monitor_heart_outlined, false),
        _MaterialData('门诊病历 4', '门诊', Icons.description_outlined, true),
      ],
    ),
    _VisitData(
      date: '2026-02-09',
      hospital: '模拟医院 A · 内分泌科',
      summary: '血糖和激素指标复查',
      materials: [_MaterialData('检测单 5', '化验', Icons.biotech_outlined, false)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedFilter == 0
        ? _visits
        : _visits
              .where(
                (visit) => visit.materials.any(
                  (material) => material.type == _filters[_selectedFilter],
                ),
              )
              .toList();
    return ColoredBox(
      key: const Key('records-page'),
      color: PomiColors.surfaceMuted,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: PomiPageHeader(
              title: '就诊记录',
              subtitle: '所有材料都可追溯到原始文件与确认记录',
              trailing: DemoBadge(label: '3 次就诊'),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) => ChoiceChip(
                  label: Text(_filters[index]),
                  selected: index == _selectedFilter,
                  onSelected: (_) => setState(() => _selectedFilter = index),
                  selectedColor: PomiColors.primary,
                  labelStyle: TextStyle(
                    color: index == _selectedFilter
                        ? Colors.white
                        : PomiColors.textMuted,
                  ),
                ),
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemCount: _filters.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 126),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final visit = filtered[index];
                return PomiSectionCard(
                  key: Key('visit-card-$index'),
                  padding: EdgeInsets.zero,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _VisitDetailPage(visit: visit),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 12, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    visit.date,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    visit.hospital,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: PomiColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0x126A4C93)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              visit.summary,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final material in visit.materials)
                                  PomiPill(
                                    label: material.name,
                                    color: _typeColor(material.type),
                                    icon: material.icon,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Color _typeColor(String type) => switch (type) {
    '化验' => PomiColors.primary,
    '处方' => const Color(0xFF0E8A7A),
    '影像' => const Color(0xFF2A7BC8),
    _ => const Color(0xFFB8860B),
  };
}

class _VisitDetailPage extends StatelessWidget {
  const _VisitDetailPage({required this.visit});

  final _VisitData visit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('visit-detail-page'),
      appBar: AppBar(title: const Text('就诊详情')),
      backgroundColor: PomiColors.surfaceMuted,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          PomiSectionCard(
            color: PomiColors.primaryPale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visit.date, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  visit.hospital,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(visit.summary),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const PomiSectionTitle(title: '关联材料'),
          const SizedBox(height: 8),
          for (final material in visit.materials) ...[
            PomiSectionCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: PomiColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(material.icon, color: PomiColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          material.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '文件 V${material.certified ? '2' : '1'} · SHA-256 已生成',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PomiPill(
                    label: material.certified ? '已认证' : '待认证',
                    color: material.certified
                        ? PomiColors.success
                        : PomiColors.textMuted,
                    icon: material.certified
                        ? Icons.verified_outlined
                        : Icons.schedule_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          const PomiSectionTitle(title: '来源追溯'),
          const SizedBox(height: 8),
          const PomiSectionCard(
            child: Column(
              children: [
                _TraceRow('上传时间', '2026-08-26 10:24'),
                _TraceRow('用户确认', '2026-08-26 10:28'),
                _TraceRow('文件版本', 'V2 · V1 已保留'),
                _TraceRow('演示认证', '当前版本已完成', last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TraceRow extends StatelessWidget {
  const _TraceRow(this.label, this.value, {this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VisitData {
  const _VisitData({
    required this.date,
    required this.hospital,
    required this.summary,
    required this.materials,
  });

  final String date;
  final String hospital;
  final String summary;
  final List<_MaterialData> materials;
}

class _MaterialData {
  const _MaterialData(this.name, this.type, this.icon, this.certified);

  final String name;
  final String type;
  final IconData icon;
  final bool certified;
}
