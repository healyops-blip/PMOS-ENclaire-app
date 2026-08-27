import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final data = await ref.read(apiClientProvider).get('/api/dashboard');
  return Map<String, dynamic>.from(data as Map);
});

final medicationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final data = await ref.read(apiClientProvider).get('/api/medications');
      return List<Map<String, dynamic>>.from(
        (data as List).map((item) => Map<String, dynamic>.from(item as Map)),
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
    final documents = Map<String, dynamic>.from(
      data['documents'] as Map? ?? {},
    );
    final weight = data['latest_weight'] as Map?;
    final cycle = data['latest_cycle'] as Map?;
    final taken =
        medicines.where((item) => item['today_status'] == 'taken').length;
    final missed =
        medicines.where((item) => item['today_status'] == 'not_taken').length;
    final unrecorded = math.max(0, medicines.length - taken - missed);
    final completion = medicines.isEmpty ? 0.0 : taken / medicines.length;
    final nextVisit = profile['next_visit_date']?.toString();
    final days = _daysUntil(nextVisit);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + 18,
            16,
            4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: pomiLine),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '距下次就诊',
                            style: TextStyle(color: pomiMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            days == null ? '待设置' : '$days 天',
                            style: const TextStyle(
                              color: pomiPurple,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            nextVisit ?? '在“我的”中设置预计就诊日期',
                            style: const TextStyle(
                              color: pomiMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: completion,
                            strokeWidth: 8,
                            backgroundColor: pomiLavender,
                            color: pomiPurple,
                            strokeCap: StrokeCap.round,
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(completion * 100).round()}%',
                                style: const TextStyle(
                                  color: pomiPurple,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Text(
                                '今日完成率',
                                style: TextStyle(color: pomiMuted, fontSize: 9),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onOpenRecords(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: pomiLine),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_copy_outlined,
                        color: pomiPurple,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '就诊记录',
                              style: TextStyle(
                                color: pomiInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '已确认的材料才进入报告',
                              style: TextStyle(color: pomiMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      _HeroBadge(
                        text:
                            '${documents['confirmed'] ?? 0}/${documents['total'] ?? 0} 已确认',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _SectionHeader(
          title: '今日用药',
          action: '用药管理 ›',
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const MedicationManagementScreen(),
                ),
              ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child:
              medicines.isEmpty
                  ? const _EmptyBand(
                    icon: Icons.medication_outlined,
                    text: '还没有当前用药，进入用药管理添加',
                  )
                  : Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      child: Column(
                        children:
                            medicines
                                .map(
                                  (medicine) => _MedicationRow(
                                    medicine: medicine,
                                    onUpdated:
                                        () => ref.invalidate(dashboardProvider),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ),
        ),
        const _SectionHeader(title: '今日三状态'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StateCount(
                          label: '已服用',
                          count: taken,
                          color: pomiSuccess,
                        ),
                      ),
                      Expanded(
                        child: _StateCount(
                          label: '主动漏服',
                          count: missed,
                          color: pomiCoral,
                        ),
                      ),
                      Expanded(
                        child: _StateCount(
                          label: '未记录',
                          count: unrecorded,
                          color: pomiMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '“未记录”表示尚未操作，不等于漏服。',
                    style: TextStyle(color: pomiMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        const _SectionHeader(title: '最近记录'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.water_drop_outlined,
                  title: '最近经期',
                  value: cycle?['start_date']?.toString() ?? '未记录',
                  color: pomiCoral,
                  onTap: () => onOpenTab(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  icon: Icons.monitor_weight_outlined,
                  title: '最新体重',
                  value: weight == null ? '未记录' : '${weight['weight_kg']} kg',
                  color: pomiMint,
                  onTap: () => onOpenTab(1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onOpenRecords(reports: true),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF7F1FB), Color(0xFFEDE3F5)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD9CBE5)),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: pomiPurple,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.summarize_outlined),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '生成就诊报告',
                          style: TextStyle(
                            color: pomiPurple,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '汇总已确认的化验、用药、经期与体重',
                          style: TextStyle(color: pomiMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: pomiPurple),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Text(
            '本产品整理用户确认的数据，不构成诊断和医疗建议。',
            textAlign: TextAlign.center,
            style: TextStyle(color: pomiMuted, fontSize: 10),
          ),
        ),
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

class MedicationManagementScreen extends ConsumerWidget {
  const MedicationManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(medicationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('用药管理')),
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
          final history =
              items
                  .where((item) => item['current_status'] != 'active')
                  .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _SectionHeader(
                title: '当前用药 · ${active.length} 项',
                action: '+ 手动添加',
                onTap: () => _addMedication(context, ref),
              ),
              if (active.isEmpty)
                const _EmptyBand(
                  icon: Icons.medication_outlined,
                  text: '还没有当前用药',
                )
              else
                Card(
                  child: Column(
                    children:
                        active
                            .map(
                              (item) => ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: pomiLavender,
                                  foregroundColor: pomiPurple,
                                  child: Icon(Icons.medication_outlined),
                                ),
                                title: Text(
                                  item['drug_name'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  [item['dosage_text'], item['frequency']]
                                      .where(
                                        (value) =>
                                            value != null &&
                                            value.toString().isNotEmpty,
                                      )
                                      .join(' · '),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              const SizedBox(height: 18),
              const _SectionHeader(title: '用药提醒'),
              const _EmptyBand(
                icon: Icons.notifications_none_rounded,
                text: '提醒时间将在 Android 通知模块接入后开放',
              ),
              const SizedBox(height: 18),
              const _SectionHeader(title: '停换药历史'),
              if (history.isEmpty)
                const _EmptyBand(icon: Icons.history_rounded, text: '还没有停换药历史')
              else
                Card(
                  child: Column(
                    children:
                        history
                            .map(
                              (item) => ListTile(
                                title: Text(item['drug_name'].toString()),
                                subtitle: Text(
                                  item['current_status'].toString(),
                                ),
                              ),
                            )
                            .toList(),
                  ),
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
                const Text(
                  '手动添加用药',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                const Text(
                  '适用于自行购买的药品或补剂，不替代上传医嘱。',
                  style: TextStyle(color: pomiMuted, fontSize: 12),
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
                          data: {
                            'drug_name': name.text.trim(),
                            'dosage_text':
                                dose.text.trim().isEmpty
                                    ? null
                                    : dose.text.trim(),
                            'frequency':
                                frequency.text.trim().isEmpty
                                    ? null
                                    : frequency.text.trim(),
                            'current_status': 'active',
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

class _MedicationRow extends ConsumerWidget {
  const _MedicationRow({required this.medicine, required this.onUpdated});
  final Map<String, dynamic> medicine;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = medicine['today_status']?.toString() ?? 'not_recorded';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine['drug_name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [medicine['dosage_text'], medicine['frequency']]
                      .where(
                        (value) => value != null && value.toString().isNotEmpty,
                      )
                      .join(' · '),
                  style: const TextStyle(color: pomiMuted, fontSize: 11),
                ),
              ],
            ),
          ),
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
                  PopupMenuItem(value: 'not_taken', child: Text('– 主动漏服')),
                  PopupMenuItem(value: 'not_recorded', child: Text('○ 未记录')),
                ],
            child: _StatusPill(status: status),
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
      'taken' => ('✓ 已服用', pomiSuccess),
      'not_taken' => ('– 主动漏服', pomiCoral),
      _ => ('○ 未记录', pomiMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: pomiMint.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: pomiMint.withValues(alpha: .45)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF147E73),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Text(action!, style: const TextStyle(fontSize: 12)),
          ),
      ],
    ),
  );
}

class _StateCount extends StatelessWidget {
  const _StateCount({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(label, style: const TextStyle(color: pomiMuted, fontSize: 11)),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: pomiMuted, fontSize: 11)),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyBand extends StatelessWidget {
  const _EmptyBand({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: pomiLine),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon, color: pomiPurple),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
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
