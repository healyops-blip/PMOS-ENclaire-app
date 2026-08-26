import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/frosted_panel.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/cycle/presentation/cycle_page.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/presentation/medication_page.dart';
import 'package:pmos_enclaire/features/profile/presentation/profile_page.dart';
import 'package:pmos_enclaire/features/records/presentation/records_page.dart';
import 'package:pmos_enclaire/features/records/presentation/upload_flow.dart';
import 'package:pmos_enclaire/features/reports/presentation/report_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({required this.account, super.key});

  final DemoAccount account;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;
  late List<Medication> _medications = const [
    Medication(
      name: '二甲双胍',
      dose: '500 mg · 晚餐随餐',
      group: '多囊用药',
      status: MedicationStatus.taken,
      takenDays: 22,
      missedDays: 2,
    ),
    Medication(
      name: '优思明',
      dose: '1 片 · 每晚',
      group: '多囊用药',
      status: MedicationStatus.unrecorded,
      takenDays: 20,
      missedDays: 1,
    ),
    Medication(
      name: '维生素 D3',
      dose: '1000 IU · 早餐后',
      group: '日常补剂',
      status: MedicationStatus.taken,
      takenDays: 24,
      missedDays: 1,
    ),
  ];

  void _cycleMedicationStatus(int index) {
    final current = _medications[index];
    final next = switch (current.status) {
      MedicationStatus.unrecorded => MedicationStatus.taken,
      MedicationStatus.taken => MedicationStatus.missed,
      MedicationStatus.missed => MedicationStatus.unrecorded,
    };
    setState(() {
      _medications = [..._medications]
        ..[index] = current.copyWith(status: next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('dashboard-page'),
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _DashboardBody(
              account: widget.account,
              medications: _medications,
              onStatusTap: _cycleMedicationStatus,
              onMedicationManage: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      MedicationPage(initialMedications: _medications),
                ),
              ),
              onReport: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReportGeneratorPage(),
                ),
              ),
            ),
            const CyclePage(),
            const RecordsPage(),
            ProfilePage(account: widget.account),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('upload-button'),
        onPressed: () => showUploadFlow(context),
        backgroundColor: PomiColors.primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _PomiBottomNavigation(
        selectedIndex: _selectedTab,
        onSelected: (index) => setState(() => _selectedTab = index),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.account,
    required this.medications,
    required this.onStatusTap,
    required this.onMedicationManage,
    required this.onReport,
  });

  final DemoAccount account;
  final List<Medication> medications;
  final ValueChanged<int> onStatusTap;
  final VoidCallback onMedicationManage;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Hero(account: account)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 126),
          sliver: SliverList.list(
            children: [
              _SectionHeader(
                title: '今日用药',
                action: '用药管理 ›',
                onTap: onMedicationManage,
              ),
              const SizedBox(height: 8),
              _PomiCard(
                child: Column(
                  children: [
                    for (var index = 0; index < medications.length; index++)
                      _MedicationRow(
                        medication: medications[index],
                        index: index,
                        last: index == medications.length - 1,
                        onTap: () => onStatusTap(index),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(
                title: '本月用药统计',
                trailing: DemoBadge(label: '三状态 · 非依从率'),
              ),
              const SizedBox(height: 8),
              _PomiCard(child: _MedicationSummary(medications: medications)),
              const SizedBox(height: 16),
              _ReportCallToAction(onTap: onReport),
              const SizedBox(height: 12),
              const Text(
                '患者自述 · 仅供参考 · 不构成诊断 · 不进入正式病历 · 模拟数据',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8B7B6B), fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.account});

  final DemoAccount account;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(30),
        bottomRight: Radius.circular(30),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: PomiColors.heroGradient),
            ),
          ),
          const Positioned(
            right: -44,
            top: -26,
            child: GlowOrb(color: Color(0x77D250F7), size: 150, blur: 44),
          ),
          const Positioned(
            left: -48,
            bottom: -50,
            child: GlowOrb(color: Color(0x55F1E584), size: 145, blur: 48),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 42),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Pomi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    FrostedPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      tintOpacity: 0.12,
                      borderOpacity: 0.2,
                      blur: 12,
                      child: Text(
                        '模拟患者 · ${account.displayName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FrostedPanel(
                  padding: const EdgeInsets.all(16),
                  borderRadius: BorderRadius.circular(19),
                  tintOpacity: 0.13,
                  blur: 20,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '距下次复诊 · 2026-09-10',
                              style: TextStyle(
                                color: Color(0xBBFFFFFF),
                                fontSize: 11,
                              ),
                            ),
                            SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '15',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(left: 5, bottom: 3),
                                  child: Text(
                                    '天',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Text(
                              '周期阶段：卵泡期 · 第 20 天',
                              style: TextStyle(
                                color: Color(0xBBFFFFFF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: 0.85,
                              strokeWidth: 4,
                              color: Colors.white,
                              backgroundColor: Color(0x44FFFFFF),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '85%',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '完成率',
                                  style: TextStyle(
                                    color: Color(0xBBFFFFFF),
                                    fontSize: 8,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.action,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? action;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing != null)
          trailing!
        else if (action != null)
          TextButton(onPressed: onTap, child: Text(action!)),
      ],
    );
  }
}

class _PomiCard extends StatelessWidget {
  const _PomiCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0x146A4C93)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A4A2E6B),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({
    required this.medication,
    required this.index,
    required this.last,
    required this.onTap,
  });

  final Medication medication;
  final int index;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medication.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${medication.group} · ${medication.dose}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _StatusPill(
            key: Key('medication-status-$index'),
            status: medication.status,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.onTap, super.key});

  final MedicationStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      MedicationStatus.taken => (
        '已服用',
        Icons.check_rounded,
        PomiColors.success,
      ),
      MedicationStatus.missed => (
        '主动漏服',
        Icons.close_rounded,
        PomiColors.warning,
      ),
      MedicationStatus.unrecorded => (
        '未记录',
        Icons.remove_rounded,
        PomiColors.textMuted,
      ),
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicationSummary extends StatelessWidget {
  const _MedicationSummary({required this.medications});

  final List<Medication> medications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (final medication in medications)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      medication.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      children: List.generate(26, (index) {
                        final color = index < medication.takenDays
                            ? PomiColors.success
                            : index <
                                  medication.takenDays + medication.missedDays
                            ? PomiColors.warning
                            : const Color(0xFFD6D6DA);
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const SizedBox(width: 6, height: 6),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: PomiColors.success, label: '已服用'),
                SizedBox(width: 12),
                _LegendDot(color: PomiColors.warning, label: '主动漏服'),
                SizedBox(width: 12),
                _LegendDot(color: Color(0xFFD6D6DA), label: '未记录'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 7, height: 7),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: PomiColors.textMuted, fontSize: 9),
        ),
      ],
    );
  }
}

class _ReportCallToAction extends StatelessWidget {
  const _ReportCallToAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PomiColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        key: const Key('report-cta'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '生成复诊报告',
                      style: TextStyle(
                        color: PomiColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '一键汇总化验 · 用药 · 经期 · 体重',
                      style: TextStyle(
                        color: PomiColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: PomiColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '生成',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PomiBottomNavigation extends StatelessWidget {
  const _PomiBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, '首页'),
      (Icons.calendar_month_rounded, '经期'),
      (Icons.assignment_rounded, '记录'),
      (Icons.person_rounded, '我的'),
    ];
    return BottomAppBar(
      height: 72,
      padding: EdgeInsets.zero,
      notchMargin: 8,
      shape: const CircularNotchedRectangle(),
      color: Colors.white,
      elevation: 12,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index == 2) const SizedBox(width: 66),
            Expanded(
              child: InkResponse(
                key: Key('nav-${items[index].$2}'),
                onTap: () => onSelected(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      items[index].$1,
                      color: selectedIndex == index
                          ? PomiColors.primary
                          : PomiColors.textMuted,
                      size: 23,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items[index].$2,
                      style: TextStyle(
                        color: selectedIndex == index
                            ? PomiColors.primary
                            : PomiColors.textMuted,
                        fontSize: 10,
                        fontWeight: selectedIndex == index
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
