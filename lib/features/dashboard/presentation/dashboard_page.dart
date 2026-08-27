import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/frosted_panel.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/cycle/data/cycle_repository.dart';
import 'package:pmos_enclaire/features/cycle/presentation/cycle_page.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/dashboard/application/dashboard_controller.dart';
import 'package:pmos_enclaire/features/dashboard/data/dashboard_repository.dart';
import 'package:pmos_enclaire/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:pmos_enclaire/features/medications/application/medication_status_controller.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';
import 'package:pmos_enclaire/features/medications/presentation/medication_page.dart';
import 'package:pmos_enclaire/features/profile/presentation/profile_page.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';
import 'package:pmos_enclaire/features/records/presentation/records_page.dart';
import 'package:pmos_enclaire/features/records/presentation/upload_flow.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/reports/presentation/report_page.dart';
import 'package:pmos_enclaire/features/reports/data/patient_note_repository.dart';
import 'package:pmos_enclaire/features/weight/application/weight_controller.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.account,
    required this.profileRepository,
    required this.patientNoteRepository,
    required this.documentRepository,
    required this.weightRepository,
    this.dashboardRepository,
    this.onLogout,
    this.now,
    this.cycleRepository,
    this.medicationRepository,
    super.key,
  });

  final DemoAccount account;
  final PatientProfileRepository profileRepository;
  final PatientNoteRepository patientNoteRepository;
  final DocumentRepository documentRepository;
  final WeightRepository weightRepository;
  final DashboardRepository? dashboardRepository;
  final Future<void> Function()? onLogout;
  final DateTime Function()? now;
  final CycleRepository? cycleRepository;
  final MedicationRepository? medicationRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;
  int _recordsVersion = 0;
  late final WeightController _weightController;
  late final DashboardController _dashboardController;
  List<Medication> _medications = const [];
  late final MedicationRepository _medicationRepository;
  late final MedicationStatusController _medicationStatusController;

  @override
  void initState() {
    super.initState();
    _dashboardController = DashboardController(
      repository: widget.dashboardRepository ?? const DemoDashboardRepository(),
      uid: widget.account.uid,
      onUnauthorized: widget.onLogout,
    )..addListener(_syncDashboard);
    _dashboardController.load();
    _weightController = WeightController(widget.weightRepository)
      ..addListener(_onWeightChanged);
    _weightController.load();
    _medicationRepository =
        widget.medicationRepository ?? DemoMedicationRepository(_medications);
    _medicationStatusController = MedicationStatusController(
      gateway: _medicationRepository,
      medications: _medications,
    )..addListener(_syncMedicationStatus);
  }

  void _syncMedicationStatus() {
    if (!mounted) return;
    setState(() => _medications = _medicationStatusController.medications);
  }

  void _syncDashboard() {
    if (!mounted) return;
    final remote = _dashboardController.snapshot?.todayMedications;
    if (remote?.status != DashboardSectionStatus.error &&
        remote?.data != null) {
      _medicationStatusController.replaceMedications(remote!.data!);
    } else {
      setState(() {});
    }
  }

  void _onWeightChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setMedicationStatus(int index, MedicationStatus status) async {
    if (_dashboardController.offline) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('离线状态仅支持查看，联网后才能修改用药')));
      return;
    }
    try {
      await _medicationStatusController.setStatus(index, status);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('状态保存失败，已恢复原状态：$error')));
    }
  }

  void _toggleTaken(int index) {
    final current = _medications[index].status;
    _setMedicationStatus(
      index,
      current == MedicationStatus.taken
          ? MedicationStatus.unrecorded
          : MedicationStatus.taken,
    );
  }

  Future<void> _showStatusActions(int index) async {
    final selected = await showModalBottomSheet<MedicationStatus>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_rounded),
              title: const Text('标记已服用'),
              onTap: () => Navigator.pop(context, MedicationStatus.taken),
            ),
            ListTile(
              key: const Key('mark-medication-missed'),
              leading: const Icon(Icons.close_rounded),
              title: const Text('标记主动漏服'),
              onTap: () => Navigator.pop(context, MedicationStatus.missed),
            ),
            ListTile(
              leading: const Icon(Icons.undo_rounded),
              title: const Text('取消当天记录'),
              onTap: () => Navigator.pop(context, MedicationStatus.unrecorded),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await _setMedicationStatus(index, selected);
  }

  Future<void> _openMedicationManager() async {
    if (_dashboardController.offline) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('离线状态不能修改用药')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MedicationPage(
          initialMedications: _medications,
          repository: _medicationRepository,
        ),
      ),
    );
    if (mounted) await _dashboardController.load();
  }

  @override
  void dispose() {
    _dashboardController
      ..removeListener(_syncDashboard)
      ..dispose();
    _weightController
      ..removeListener(_onWeightChanged)
      ..dispose();
    _medicationStatusController
      ..removeListener(_syncMedicationStatus)
      ..dispose();
    super.dispose();
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
              controller: _dashboardController,
              weightController: _weightController,
              onStatusTap: _toggleTaken,
              onStatusLongPress: _showStatusActions,
              onMedicationManage: _openMedicationManager,
              onReport: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportGeneratorPage(
                    repository: widget.patientNoteRepository,
                  ),
                ),
              ),
            ),
            CyclePage(
              repository: widget.cycleRepository,
              weightController: _weightController,
              now: widget.now,
              writesEnabled: !_dashboardController.offline,
            ),
            RecordsPage(
              key: ValueKey(_recordsVersion),
              repository: widget.documentRepository,
            ),
            ProfilePage(
              account: widget.account,
              repository: widget.profileRepository,
              onLogout: widget.onLogout,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('upload-button'),
        onPressed: () => showUploadFlow(
          context,
          repository: widget.documentRepository,
          onUploaded: () => setState(() => _recordsVersion++),
        ),
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
    required this.controller,
    required this.weightController,
    required this.onStatusTap,
    required this.onStatusLongPress,
    required this.onMedicationManage,
    required this.onReport,
  });

  final DemoAccount account;
  final List<Medication> medications;
  final DashboardController controller;
  final WeightController weightController;
  final ValueChanged<int> onStatusTap;
  final ValueChanged<int> onStatusLongPress;
  final VoidCallback onMedicationManage;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    return RefreshIndicator(
      onRefresh: controller.load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _Hero(
              account: account,
              followUp: snapshot?.followUp,
              summary: snapshot?.monthSummary.data,
              businessDate: snapshot?.businessDate,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 126),
            sliver: SliverList.list(
              children: [
                if (controller.offline)
                  _DashboardNotice(
                    key: const Key('dashboard-offline-banner'),
                    icon: Icons.cloud_off_rounded,
                    message:
                        '离线数据，更新于 ${controller.updatedAt?.toLocal().toString().substring(0, 16) ?? '--'}',
                  ),
                if (controller.error != null && snapshot == null)
                  _DashboardNotice(
                    key: const Key('dashboard-load-error'),
                    icon: Icons.error_outline_rounded,
                    message: '首页加载失败，请重试',
                    onRetry: controller.load,
                  ),
                if (controller.error != null && snapshot != null)
                  _DashboardNotice(
                    key: const Key('dashboard-stale-error'),
                    icon: Icons.sync_problem_rounded,
                    message: '刷新失败，当前为上次数据',
                    onRetry: controller.load,
                  ),
                if (snapshot != null)
                  for (final entry in <String, DashboardSection<Object?>>{
                    '复诊安排': snapshot.followUp,
                    '今日用药': snapshot.todayMedications,
                    '本月统计': snapshot.monthSummary,
                    '复诊报告': snapshot.latestReport,
                  }.entries)
                    if (entry.value.status == DashboardSectionStatus.error)
                      _DashboardNotice(
                        key: Key('dashboard-section-error-${entry.key}'),
                        icon: Icons.sync_problem_rounded,
                        message: '${entry.key}暂时不可用',
                        onRetry: controller.load,
                      ),
                _FollowUpPanel(section: snapshot?.followUp),
                _SectionHeader(
                  title: '今日用药',
                  action: '用药管理 ›',
                  onTap: controller.offline ? null : onMedicationManage,
                ),
                const SizedBox(height: 8),
                if (medications.isEmpty)
                  const _PomiCard(
                    child: PomiEmptyState(
                      icon: Icons.medication_outlined,
                      title: '今天没有待记录用药',
                      description: '已暂停、停用或尚未开始的用药不会显示在这里。',
                    ),
                  )
                else
                  _PomiCard(
                    child: Column(
                      children: [
                        for (var index = 0; index < medications.length; index++)
                          _MedicationRow(
                            medication: medications[index],
                            index: index,
                            last: index == medications.length - 1,
                            onTap: () => onStatusTap(index),
                            onLongPress: () => onStatusLongPress(index),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                const _SectionHeader(
                  title: '本月用药统计',
                  trailing: DemoBadge(label: '三状态统计'),
                ),
                const SizedBox(height: 8),
                _PomiCard(
                  child: _MedicationSummary(
                    medications: medications,
                    summary: snapshot?.monthSummary.data,
                  ),
                ),
                const SizedBox(height: 16),
                if (snapshot?.latestReport.status != DashboardSectionStatus.ok)
                  const _DashboardNotice(
                    key: Key('dashboard-report-empty'),
                    icon: Icons.description_outlined,
                    message: '暂无复诊报告 · 准备复诊材料',
                  )
                else
                  _DashboardNotice(
                    key: const Key('dashboard-report-latest'),
                    icon: Icons.description_rounded,
                    message:
                        '最新报告已生成 · ${_displayTimestamp(snapshot!.latestReport.data!.generatedAt)}',
                  ),
                _ReportCallToAction(
                  onTap: onReport,
                  hasReport:
                      snapshot?.latestReport.status ==
                      DashboardSectionStatus.ok,
                ),
                const SizedBox(height: 20),
                const _SectionHeader(title: '最新体重'),
                const SizedBox(height: 8),
                _DashboardWeightSummary(controller: weightController),
                const SizedBox(height: 12),
                const Text(
                  '患者自述 · 仅供参考 · 不构成诊断 · 不进入正式病历',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8B7B6B), fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _displayTimestamp(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _DashboardNotice extends StatelessWidget {
  const _DashboardNotice({
    required this.icon,
    required this.message,
    this.onRetry,
    super.key,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _PomiCard(
        child: Row(
          children: [
            Icon(icon, color: PomiColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _FollowUpPanel extends StatelessWidget {
  const _FollowUpPanel({required this.section});

  final DashboardSection<FollowUpSummary>? section;

  @override
  Widget build(BuildContext context) {
    final value = section?.data;
    final title = switch (value?.state) {
      'due' => '今天是复诊日',
      'overdue' => '复诊日期已到',
      'upcoming' => '距下次复诊 ${value!.daysRemaining} 天',
      _ => '尚未设置复诊日期',
    };
    final subtitle = value == null
        ? '可在个人资料中设置复诊安排'
        : '${value.nextVisitDate.year}-${value.nextVisitDate.month.toString().padLeft(2, '0')}-${value.nextVisitDate.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _PomiCard(
        child: ListTile(
          key: const Key('dashboard-follow-up'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.event_available_outlined,
            color: PomiColors.primary,
          ),
          title: Text(title),
          subtitle: Text(subtitle),
        ),
      ),
    );
  }
}

class _SummaryCount extends StatelessWidget {
  const _SummaryCount({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.account,
    required this.followUp,
    required this.summary,
    required this.businessDate,
  });

  final DemoAccount account;
  final DashboardSection<FollowUpSummary>? followUp;
  final MedicationMonthSummary? summary;
  final DateTime? businessDate;

  @override
  Widget build(BuildContext context) {
    final visit = followUp?.data;
    final visitDate = visit == null
        ? null
        : '${visit.nextVisitDate.year}-${visit.nextVisitDate.month.toString().padLeft(2, '0')}-${visit.nextVisitDate.day.toString().padLeft(2, '0')}';
    final visitTitle = switch (followUp?.status) {
      DashboardSectionStatus.error => '复诊安排暂不可用',
      _ when visit?.state == 'upcoming' => '距下次复诊 · $visitDate',
      _ when visit?.state == 'due' => '今天是复诊日 · $visitDate',
      _ when visit?.state == 'overdue' => '复诊日期已到 · $visitDate',
      _ => '尚未设置复诊日期',
    };
    final dateLabel = businessDate == null
        ? '数据加载中'
        : '数据日期 ${businessDate!.year}-${businessDate!.month.toString().padLeft(2, '0')}-${businessDate!.day.toString().padLeft(2, '0')}';
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
                        '患者 · ${account.displayName}',
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              visitTitle,
                              key: const Key('dashboard-hero-follow-up'),
                              style: const TextStyle(
                                color: Color(0xBBFFFFFF),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  visit?.daysRemaining.toString() ?? '--',
                                  key: const Key('dashboard-hero-days'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 38,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const Padding(
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
                            const SizedBox(height: 6),
                            Text(
                              dateLabel,
                              style: const TextStyle(
                                color: Color(0xBBFFFFFF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: Column(
                          children: [
                            _HeroState(
                              label: '已服用',
                              value: summary?.taken.toString() ?? '--',
                            ),
                            const SizedBox(height: 5),
                            _HeroState(
                              label: '主动漏服',
                              value: summary?.missed.toString() ?? '--',
                            ),
                            const SizedBox(height: 5),
                            _HeroState(
                              label: '未记录',
                              value: summary?.unrecorded.toString() ?? '--',
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

class _HeroState extends StatelessWidget {
  const _HeroState({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xCFFFFFFF), fontSize: 9),
          ),
        ),
        Container(
          width: 25,
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
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
    required this.onLongPress,
  });

  final Medication medication;
  final int index;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
            onLongPress: onLongPress,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final MedicationStatus status;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
        onLongPress: onLongPress,
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
  const _MedicationSummary({required this.medications, this.summary});

  final List<Medication> medications;
  final MedicationMonthSummary? summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (summary != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryCount(label: '已服用', value: summary!.taken),
                  _SummaryCount(label: '主动漏服', value: summary!.missed),
                  _SummaryCount(label: '未记录', value: summary!.unrecorded),
                ],
              ),
            ),
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

class _DashboardWeightSummary extends StatelessWidget {
  const _DashboardWeightSummary({required this.controller});

  final WeightController controller;

  @override
  Widget build(BuildContext context) {
    final latest = controller.latest;
    if (controller.isLoading && latest == null) {
      return const _PomiCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (latest == null) {
      return _PomiCard(
        child: Padding(
          key: const Key('dashboard-weight-empty'),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.monitor_weight_outlined,
                color: PomiColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(controller.errorMessage ?? '还没有体重记录，前往“经期”页添加'),
              ),
              if (controller.errorMessage != null)
                TextButton(onPressed: controller.load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final month = latest.recordDate.month.toString().padLeft(2, '0');
    final day = latest.recordDate.day.toString().padLeft(2, '0');
    return _PomiCard(
      child: Padding(
        key: const Key('dashboard-weight-summary'),
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.errorMessage != null) ...[
              Row(
                key: const Key('dashboard-weight-stale-warning'),
                children: [
                  const Icon(Icons.sync_problem_rounded, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('同步失败，当前为上次数据')),
                  TextButton(
                    onPressed: controller.load,
                    child: const Text('重试'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: PomiColors.glowPink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.monitor_weight_outlined,
                    color: PomiColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${latest.weightKg.toStringAsFixed(1)} kg',
                        key: const Key('dashboard-weight-value'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${latest.recordDate.year}-$month-$day 记录',
                        key: const Key('dashboard-weight-date'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (controller.isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
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
  const _ReportCallToAction({required this.onTap, required this.hasReport});

  final VoidCallback onTap;
  final bool hasReport;

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasReport ? '进入复诊报告' : '生成复诊报告',
                      style: const TextStyle(
                        color: PomiColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '汇总化验 · 用药 · 经期 · 体重',
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
                child: Text(
                  hasReport ? '查看' : '生成',
                  style: const TextStyle(
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
