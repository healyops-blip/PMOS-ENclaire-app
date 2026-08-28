import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final values = await Future.wait([
    ref.read(apiClientProvider).get('/api/dashboard'),
    ref.read(apiClientProvider).get('/api/patient/profile'),
  ]);
  final data = Map<String, dynamic>.from(values[0] as Map);
  dynamic section(String key) => (data[key] as Map?)?['data'];
  final medications = (section('today_medications') as List? ?? const [])
      .whereType<Map>()
      .map(
        (item) => {
          ...Map<String, dynamic>.from(item),
          'id': item['medication_id'],
          'today_status': item['intake_status'],
        },
      )
      .toList(growable: false);
  final tracking = section('tracking_summary') as Map?;
  return {
    ...data,
    'profile': values[1],
    'medications': medications,
    'documents': section('document_summary') ?? <String, dynamic>{},
    'latest_weight': tracking?['latest_weight'],
    'latest_cycle': tracking?['latest_cycle'],
  };
});

final medicationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final data = await ref.read(apiClientProvider).get('/api/medications');
      final page = Map<String, dynamic>.from(data as Map);
      return List<Map<String, dynamic>>.from(
        (page['items'] as List).map((item) {
          final value = Map<String, dynamic>.from(item as Map);
          final dosageValue = value['dosage_value'];
          final dosageUnit = value['dosage_unit']?.toString() ?? '';
          value['dosage_text'] =
              dosageValue == null
                  ? value['specification']
                  : '$dosageValue$dosageUnit';
          return value;
        }),
      );
    });

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    required this.onOpenTab,
    required this.onOpenRecords,
    super.key,
  });

  final ValueChanged<int> onOpenTab;
  final void Function({bool reports}) onOpenRecords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    return Scaffold(
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stack) => _ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
        data:
            (data) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(dashboardProvider);
                await ref.read(dashboardProvider.future);
              },
              child: _DashboardBody(
                data: data,
                onOpenTab: onOpenTab,
                onOpenRecords: onOpenRecords,
              ),
            ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.data,
    required this.onOpenTab,
    required this.onOpenRecords,
  });

  final Map<String, dynamic> data;
  final ValueChanged<int> onOpenTab;
  final void Function({bool reports}) onOpenRecords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? {});
    final medicines = List<Map<String, dynamic>>.from(
      (data['medications'] as List? ?? []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final nextVisit = profile['next_visit_date']?.toString();
    final days = _daysUntil(nextVisit);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + 12,
            16,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Transform.translate(
                offset: const Offset(0, -6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Semantics(
                      label: 'Pomie 动效图标',
                      image: true,
                      child: Image.asset(
                        'assets/images/pomie_questioning.gif',
                        width: 76,
                        height: 76,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Hi, Pomie!',
                        style: TextStyle(
                          color: pomiMuted,
                          fontSize: 22,
                          height: 28 / 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: pomiInk,
                      fontSize: 32,
                      height: 40 / 32,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      const TextSpan(text: '距下次就诊还有'),
                      TextSpan(
                        text: days?.toString() ?? '—',
                        style: const TextStyle(color: pomiPurple),
                      ),
                      const TextSpan(text: '天'),
                    ],
                  ),
                  maxLines: 1,
                  semanticsLabel:
                      days == null ? '距下次就诊尚未设置' : '距下次就诊还有 $days 天',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _HomeActionButton(
                      icon: Icons.upload_outlined,
                      label: '上传资料',
                      onTap: () => onOpenTab(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 7,
                    child: FilledButton.icon(
                      onPressed: () => onOpenRecords(reports: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: pomiPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(Icons.article_outlined, size: 20),
                      label: const Text(
                        '生成就诊报告',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _LatestVisitStatusCard(onTap: () => onOpenRecords()),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _MedicationProgressCard(
            medicines: medicines,
            onManage:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const MedicationManagementScreen(),
                  ),
                ),
            onUpdated: () => ref.invalidate(dashboardProvider),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  int? _daysUntil(String? value) {
    if (value == null || value.isEmpty) return null;
    final date = DateTime.tryParse(value);
    if (date == null) return null;
    return math.max(
      0,
      DateUtils.dateOnly(
        date,
      ).difference(DateUtils.dateOnly(DateTime.now())).inDays,
    );
  }
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PomiGlassCard(
    onTap: onTap,
    borderRadius: 20,
    child: SizedBox(
      height: 54,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: pomiPurple, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: pomiInk,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// TODO(product): Bind this preview copy to the latest visit document and
/// signature workflow after the API fields are confirmed.
class _LatestVisitStatusCard extends StatelessWidget {
  const _LatestVisitStatusCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PomiGlassCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: pomiPurple.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.description_outlined,
            color: pomiPurple,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '激素六项化验单',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: pomiInk,
                  fontSize: 15,
                  height: 21 / 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 3),
              Text(
                '仁和医院 · 2026-08-25',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: pomiSecondaryText,
                  fontSize: 11,
                  height: 16 / 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x143B86C8),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x333B86C8)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    color: Color(0xFF337EBB),
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '签署申请中',
                    style: TextStyle(
                      color: Color(0xFF337EBB),
                      fontSize: 11,
                      height: 16 / 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class MedicationManagementScreen extends ConsumerWidget {
  const MedicationManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(medicationsProvider);
    return Scaffold(
      appBar: AppBar(),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stack) => _ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(medicationsProvider),
            ),
        data: (items) {
          final active =
              items
                  .where((item) => item['current_status'] == 'active')
                  .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              const _MedicationPageHeading('用药提醒'),
              const SizedBox(height: 16),
              _ReminderCard(
                reminders: const [
                  _MedicationReminder(name: '二甲双胍', time: '18:30'),
                  _MedicationReminder(name: '维生素 D3', time: '08:00'),
                ],
              ),
              const SizedBox(height: 28),
              const _MedicationPageHeading('本月状态'),
              const SizedBox(height: 16),
              _MonthlyMedicationCard(
                rows: [
                  _MonthlyMedicationStatus(
                    name:
                        active.isNotEmpty
                            ? _shortMedicationName(
                              active[0]['drug_name']?.toString(),
                            )
                            : '盐酸二甲双胍...',
                    taken: 22,
                    missed: 2,
                    unrecorded: 2,
                  ),
                  _MonthlyMedicationStatus(
                    name:
                        active.length > 1
                            ? _shortMedicationName(
                              active[1]['drug_name']?.toString(),
                            )
                            : '叶酸',
                    taken: 24,
                    missed: 1,
                    unrecorded: 1,
                  ),
                  _MonthlyMedicationStatus(
                    name:
                        active.length > 2
                            ? _shortMedicationName(
                              active[2]['drug_name']?.toString(),
                            )
                            : '维生素 D3',
                    taken: 25,
                    missed: 1,
                    unrecorded: 0,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const _MedicationPageHeading('停换药历史'),
              const SizedBox(height: 16),
              _MedicationHistoryCard(
                onRejoin: () => _addMedication(context, ref),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addMedication(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final dose = TextEditingController();
    final frequency = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '手动添加用药',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  '适用于自行购买的药品或补剂，不替代上传医嘱。',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '药品名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dose,
                  decoration: const InputDecoration(labelText: '剂量 / 规格'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: frequency,
                  decoration: const InputDecoration(labelText: '频次'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    if (name.text.trim().isEmpty) return;
                    await ref
                        .read(apiClientProvider)
                        .post(
                          '/api/medications',
                          headers: {
                            'Idempotency-Key':
                                'manual-${DateTime.now().microsecondsSinceEpoch}',
                          },
                          data: {
                            'drug_name': name.text.trim(),
                            'source_category': 'other_long_term',
                            'specification':
                                dose.text.trim().isEmpty
                                    ? null
                                    : dose.text.trim(),
                            'frequency':
                                frequency.text.trim().isEmpty
                                    ? null
                                    : frequency.text.trim(),
                          },
                        );
                    if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                  },
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
    );
    name.dispose();
    dose.dispose();
    frequency.dispose();
    if (saved == true) {
      ref.invalidate(medicationsProvider);
      ref.invalidate(dashboardProvider);
    }
  }
}

String _shortMedicationName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return '未命名药品';
  if (name.length <= 7) return name;
  return '${name.substring(0, 6)}...';
}

class _MedicationPageHeading extends StatelessWidget {
  const _MedicationPageHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _MedicationReminder {
  const _MedicationReminder({required this.name, required this.time});

  final String name;
  final String time;
}

class _ReminderCard extends StatefulWidget {
  const _ReminderCard({required this.reminders});

  final List<_MedicationReminder> reminders;

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  late final List<bool> _enabled = List<bool>.filled(
    widget.reminders.length,
    true,
  );

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      borderRadius: 22,
      backgroundOpacity: .34,
      child: Column(
        children: [
          for (var index = 0; index < widget.reminders.length; index++) ...[
            _ReminderRow(
              reminder: widget.reminders[index],
              enabled: _enabled[index],
              onChanged: (value) => setState(() => _enabled[index] = value),
            ),
            if (index != widget.reminders.length - 1)
              const Divider(height: 1, color: pomiLine),
          ],
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.enabled,
    required this.onChanged,
  });

  final _MedicationReminder reminder;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text('每日提醒', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .34),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pomiPurple.withValues(alpha: .20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reminder.time,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: pomiPurple,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.schedule, color: pomiInk, size: 19),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeTrackColor: pomiMint,
            activeThumbColor: Colors.white,
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {},
            style: IconButton.styleFrom(
              backgroundColor: pomiLavender.withValues(alpha: .85),
              foregroundColor: pomiPurple,
              minimumSize: const Size(42, 42),
            ),
            icon: const Icon(Icons.settings_outlined, size: 21),
          ),
        ],
      ),
    );
  }
}

class _MonthlyMedicationStatus {
  const _MonthlyMedicationStatus({
    required this.name,
    required this.taken,
    required this.missed,
    required this.unrecorded,
  });

  final String name;
  final int taken;
  final int missed;
  final int unrecorded;
}

class _MonthlyMedicationCard extends StatelessWidget {
  const _MonthlyMedicationCard({required this.rows});

  final List<_MonthlyMedicationStatus> rows;

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      borderRadius: 22,
      backgroundOpacity: .34,
      child: Column(
        children: [
          for (final row in rows) ...[
            _MonthlyMedicationRow(status: row),
            if (row != rows.last) const SizedBox(height: 14),
          ],
          const SizedBox(height: 18),
          const Row(
            children: [
              _StatusLegend(color: pomiSuccess, label: '已服用'),
              SizedBox(width: 22),
              _StatusLegend(color: pomiCoral, label: '主动漏服'),
              SizedBox(width: 22),
              _StatusLegend(color: Color(0xFFD9D4DE), label: '未记录'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyMedicationRow extends StatelessWidget {
  const _MonthlyMedicationRow({required this.status});

  final _MonthlyMedicationStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 105,
          child: Text(
            status.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          width: 78,
          child: Row(
            children: List.generate(
              8,
              (index) => Expanded(
                child: Container(
                  height: 9,
                  margin: EdgeInsets.only(right: index == 7 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: pomiSuccess,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '已服用 ${status.taken} · 漏服 ${status.missed} · 未记录 ${status.unrecorded}',
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _MedicationHistoryCard extends StatelessWidget {
  const _MedicationHistoryCard({required this.onRejoin});

  final VoidCallback onRejoin;

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      borderRadius: 22,
      backgroundOpacity: .34,
      child: Column(
        children: [
          _MedicationHistoryRow(
            name: '优思明（炔雌醇屈螺酮片）',
            detail: '2025-11 ~ 2026-06 · 已停用 · 医生书面医嘱',
            onRejoin: onRejoin,
          ),
          const Divider(height: 1, color: pomiLine),
          _MedicationHistoryRow(
            name: '布洛芬缓释胶囊',
            detail: '2025-03 · 短期 · 非 PCOS 用药 · 已停用',
            onRejoin: onRejoin,
          ),
        ],
      ),
    );
  }
}

class _MedicationHistoryRow extends StatelessWidget {
  const _MedicationHistoryRow({
    required this.name,
    required this.detail,
    required this.onRejoin,
  });

  final String name;
  final String detail;
  final VoidCallback onRejoin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onRejoin,
            style: OutlinedButton.styleFrom(
              foregroundColor: pomiPurple,
              side: BorderSide(color: pomiPurple.withValues(alpha: .24)),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              shape: const StadiumBorder(),
            ),
            child: Text(
              '加入用药管理',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationProgressCard extends StatelessWidget {
  const _MedicationProgressCard({
    required this.medicines,
    required this.onManage,
    required this.onUpdated,
  });

  final List<Map<String, dynamic>> medicines;
  final VoidCallback onManage;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    final recorded =
        medicines
            .where(
              (item) =>
                  item['today_status'] == 'taken' ||
                  item['today_status'] == 'missed',
            )
            .length;
    final visibleMedicines = medicines.take(3).toList(growable: false);

    return SizedBox(
      width: double.infinity,
      height: 320,
      child: PomiGlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '今日用药',
                  maxLines: 1,
                  style: TextStyle(
                    color: pomiInk,
                    fontSize: 18,
                    height: 26 / 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (medicines.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: pomiPurple.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: pomiPurple.withValues(alpha: .14),
                      ),
                    ),
                    child: Text(
                      '已记录 $recorded/${medicines.length}',
                      style: const TextStyle(
                        color: pomiSecondaryText,
                        fontSize: 11,
                        height: 16 / 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                TextButton(
                  onPressed: onManage,
                  style: TextButton.styleFrom(
                    foregroundColor: pomiInk,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '用药管理',
                        style: TextStyle(
                          color: pomiInk,
                          fontSize: 12,
                          height: 17 / 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, color: pomiInk, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  visibleMedicines.isEmpty
                      ? Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: OutlinedButton.icon(
                            onPressed: onManage,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加当前用药'),
                          ),
                        ),
                      )
                      : ListView(
                        padding: EdgeInsets.zero,
                        children: visibleMedicines.indexed
                            .map(
                              (entry) => _MedicationProgressRow(
                                medicine: entry.$2,
                                index: entry.$1,
                                onUpdated: onUpdated,
                              ),
                            )
                            .toList(growable: false),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicationProgressRow extends ConsumerWidget {
  const _MedicationProgressRow({
    required this.medicine,
    required this.index,
    required this.onUpdated,
  });

  final Map<String, dynamic> medicine;
  final int index;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = medicine['today_status']?.toString() ?? 'unrecorded';
    final isPending = status == 'unrecorded';
    final details = [medicine['dosage_text'], medicine['frequency']]
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .join(' · ');
    final time =
        medicine['scheduled_time']?.toString().trim().isNotEmpty == true
            ? medicine['scheduled_time'].toString()
            : isPending
            ? '20:00'
            : '08:00';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color:
            isPending ? pomiPurple.withValues(alpha: .07) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border:
            isPending
                ? Border.all(color: pomiPurple.withValues(alpha: .13))
                : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              time,
              style: const TextStyle(
                color: pomiSecondaryText,
                fontSize: 13,
                height: 18 / 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine['drug_name'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPending ? pomiInk : pomiSecondaryText,
                    fontSize: 15,
                    height: 21 / 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: pomiSecondaryText,
                      fontSize: 12,
                      height: 17 / 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: '记录今日状态',
            initialValue: status,
            onSelected: (value) async {
              try {
                await ref
                    .read(apiClientProvider)
                    .put(
                      '/api/medications/${medicine['id']}/daily-status',
                      data: {
                        'record_date': DateTime.now()
                            .toIso8601String()
                            .substring(0, 10),
                        'intake_status': value,
                      },
                    );
                onUpdated();
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(value: 'taken', child: Text('✓ 已服用')),
                  PopupMenuItem(value: 'missed', child: Text('– 主动漏服')),
                  PopupMenuItem(value: 'unrecorded', child: Text('○ 未记录')),
                ],
            child:
                isPending
                    ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: pomiPurple,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '去记录',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                    : _StatusPill(status: status),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'taken' => ('已服用', pomiSuccess),
      'missed' => ('主动漏服', pomiCoral),
      _ => ('未记录', pomiMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: pomiSecondaryText,
          fontSize: 12,
          height: 17 / 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40, color: pomiPurple),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}
