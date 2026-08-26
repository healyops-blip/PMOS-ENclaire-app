import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';

class CertificationPage extends StatefulWidget {
  const CertificationPage({super.key});

  @override
  State<CertificationPage> createState() => _CertificationPageState();
}

class _CertificationPageState extends State<CertificationPage> {
  int _currentStep = 4;

  static const _steps = [
    ('认证申请已提交', '2026-08-26 10:30', Icons.send_outlined),
    ('陈医生已接收', '2026-08-26 10:42', Icons.person_outline_rounded),
    ('医生 KYC 已通过', '2026-08-26 10:45', Icons.badge_outlined),
    ('电子签字已完成', '2026-08-26 10:51', Icons.draw_outlined),
    ('测试链交易确认', '等待 12 个区块确认', Icons.link_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final confirmed = _currentStep >= _steps.length;
    return Scaffold(
      key: const Key('certification-page'),
      appBar: AppBar(title: const Text('电子病历认证')),
      backgroundColor: PomiColors.surfaceMuted,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const PomiSectionCard(
            color: PomiColors.primaryPale,
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: PomiColors.primary,
                  size: 34,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '认证编号 PM-20260826-0012',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '检测单 6 · 文件 V2 · 模拟医院 B',
                        style: TextStyle(
                          color: PomiColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const PomiSectionTitle(title: '认证进度'),
          const SizedBox(height: 8),
          PomiSectionCard(
            child: Column(
              children: [
                for (var index = 0; index < _steps.length; index++)
                  _TimelineStep(
                    title: _steps[index].$1,
                    subtitle: _steps[index].$2,
                    icon: _steps[index].$3,
                    complete: index < _currentStep,
                    active: index == _currentStep,
                    last: index == _steps.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const PomiSectionTitle(title: '医生与签字'),
          const SizedBox(height: 8),
          const PomiSectionCard(
            child: Column(
              children: [
                _InfoRow(label: '签字医生', value: '陈医生 · 内分泌科'),
                _InfoRow(label: 'KYC 状态', value: '已通过'),
                _InfoRow(label: '签字时间', value: '2026-08-26 10:51'),
                _InfoRow(label: '凭证摘要', value: 'sig_82b1…7d03', last: true),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const PomiSectionTitle(title: '测试链存证'),
          const SizedBox(height: 8),
          PomiSectionCard(
            child: Column(
              children: [
                _InfoRow(label: '网络', value: 'Pomi Demo Testnet'),
                _InfoRow(label: '状态', value: confirmed ? '已确认' : '确认中'),
                _InfoRow(
                  label: '交易哈希',
                  value: confirmed ? '0xa86c…19ef' : '等待生成',
                ),
                _InfoRow(
                  label: '确认数',
                  value: confirmed ? '12 / 12' : '7 / 12',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PomiColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Text(
              '链上只保存材料摘要、签字凭证摘要和必要状态，不写入患者身份、检验数值或原始文件。',
              style: TextStyle(
                color: Color(0xFF8B7B6B),
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!confirmed)
            FilledButton.icon(
              key: const Key('advance-certification-button'),
              onPressed: () => setState(() => _currentStep += 1),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('模拟测试链确认'),
            )
          else
            const Center(child: DemoBadge(label: '认证完成 · 测试链可查')),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.complete,
    required this.active,
    required this.last,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool complete;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = complete
        ? PomiColors.success
        : active
        ? PomiColors.primary
        : PomiColors.textMuted;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    complete ? Icons.check_rounded : icon,
                    color: color,
                    size: 16,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.last = false});

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
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
