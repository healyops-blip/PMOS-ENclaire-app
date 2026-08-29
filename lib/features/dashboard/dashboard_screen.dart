import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../medications/medication_catalog.dart';
import '../records/records_screen.dart' show recordsProvider;

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

/// 本月每种用药的 taken / missed / unrecorded 计数，键为 medication_id。
/// 由 /api/medication-daily 当月区间聚合，正式版和 Smoke 用同一套 UI。
final monthlyMedicationStatusProvider = FutureProvider.autoDispose<
  Map<String, ({int taken, int missed, int unrecorded})>
>((ref) async {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final value = await ref
      .read(apiClientProvider)
      .get(
        '/api/medication-daily',
        queryParameters: {
          'from': '${now.year}-${two(now.month)}-01',
          'to': '${now.year}-${two(now.month)}-${two(now.day)}',
        },
      );
  final items = (value as List?) ?? const [];
  final agg = <String, List<int>>{};
  for (final raw in items) {
    if (raw is! Map) continue;
    final id = raw['medication_id']?.toString();
    if (id == null || id.isEmpty) continue;
    final bucket = agg.putIfAbsent(id, () => <int>[0, 0, 0]);
    switch (raw['intake_status']?.toString()) {
      case 'taken':
        bucket[0]++;
      case 'missed':
        bucket[1]++;
      default:
        bucket[2]++;
    }
  }
  return {
    for (final entry in agg.entries)
      entry.key: (
        taken: entry.value[0],
        missed: entry.value[1],
        unrecorded: entry.value[2],
      ),
  };
});

final medicationCatalogProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final data = await ref
          .read(apiClientProvider)
          .get('/api/medication-catalog');
      final page = Map<String, dynamic>.from(data as Map);
      return List<Map<String, dynamic>>.from(
        (page['items'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
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

typedef _LatestVisit =
    ({String date, String hospital, String label, String tag});

const _materialTags = <String, String>{
  'lab_report': '化验/检测',
  'medical_order': '医嘱/处方',
  'imaging_text_report': '影像报告',
  'outpatient_record': '门诊病历',
};

/// recordsProvider 的 documents 里按 uploaded_at 取最新一份，映射成卡片文案。
_LatestVisit? _latestVisitOf(Map<String, dynamic> records) {
  final docs =
      ((records['documents'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort(
          (a, b) => (b['uploaded_at']?.toString() ?? '').compareTo(
            a['uploaded_at']?.toString() ?? '',
          ),
        );
  if (docs.isEmpty) return null;
  final doc = docs.first;
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = doc[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v.split('T').first;
    }
    return null;
  }

  final type = doc['document_type']?.toString() ?? '';
  return (
    date:
        pick(['visit_date', 'report_date', 'sample_date', 'uploaded_at']) ??
        '最新上传',
    hospital:
        (doc['hospital_name'] ?? doc['hospital'])?.toString() ??
        doc['original_file_name']?.toString() ??
        '医疗记录',
    label: doc['original_file_name']?.toString() ?? '医疗资料',
    tag: _materialTags[type] ?? '医疗资料',
  );
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
    final latestVisit = ref
        .watch(recordsProvider)
        .maybeWhen(data: _latestVisitOf, orElse: () => null);

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
                        '指标看板',
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
              if (latestVisit != null) ...[
                const SizedBox(height: 14),
                _LatestVisitStatusCard(
                  date: latestVisit.date,
                  hospital: latestVisit.hospital,
                  materialLabel: latestVisit.label,
                  materialTag: latestVisit.tag,
                  onTap: () => onOpenRecords(),
                ),
              ],
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
            onUpdated: () {
              ref.invalidate(dashboardProvider);
              ref.invalidate(monthlyMedicationStatusProvider);
            },
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

/// 首页「最近就诊」卡：取自 recordsProvider 里最新上传的一份材料。
class _LatestVisitStatusCard extends StatelessWidget {
  const _LatestVisitStatusCard({
    required this.date,
    required this.hospital,
    required this.materialLabel,
    required this.materialTag,
    required this.onTap,
  });

  final String date;
  final String hospital;
  final String materialLabel;
  final String materialTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PomiGlassCard(
    onTap: onTap,
    borderRadius: 20,
    backgroundOpacity: .36,
    padding: EdgeInsets.zero,
    child: Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hospital,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        const Align(
                          alignment: Alignment.center,
                          child: Text(
                            '区块链技术支持',
                            style: TextStyle(
                              color: pomiPurple,
                              fontSize: 10,
                              height: 14 / 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    children: [
                      Icon(
                        Icons.chevron_right_rounded,
                        color: pomiSecondaryText,
                      ),
                      SizedBox(height: 2),
                      Text(
                        '详情',
                        style: TextStyle(
                          color: pomiSecondaryText,
                          fontSize: 10,
                          height: 14 / 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: pomiLine),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      materialLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: pomiPurple.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      materialTag,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: pomiPurple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 28,
          top: 4,
          child: Opacity(
            opacity: .50,
            child: Transform.rotate(
              angle: -math.pi / 12,
              child: Image.asset(
                'assets/images/pomi_verified_stamp.png',
                width: 88,
                height: 88,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
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
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '添加用药',
            onPressed: () => _addMedication(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
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
          final inactive =
              items
                  .where((item) => item['current_status'] != 'active')
                  .toList();
          final reminders = [
            for (final item in active)
              _MedicationReminder(
                medicationId: item['id']?.toString() ?? '',
                name: _shortMedicationName(
                  medicationDisplayName(
                    item['drug_name'],
                    standardDrugId: item['standard_drug_id'],
                  ),
                ),
                doseCount: _dosesPerDay(item['frequency']?.toString()),
                frequencyLabel: item['frequency']?.toString(),
              ),
          ];
          final monthlyStatus = ref
              .watch(monthlyMedicationStatusProvider)
              .maybeWhen(
                data: (value) => value,
                orElse:
                    () =>
                        const <
                          String,
                          ({int taken, int missed, int unrecorded})
                        >{},
              );
          final monthlyRows = [
            for (final item in active)
              () {
                final id = item['id']?.toString();
                final counts =
                    (id == null ? null : monthlyStatus[id]) ??
                    (taken: 0, missed: 0, unrecorded: 0);
                return _MonthlyMedicationStatus(
                  medicationId: id,
                  name: _shortMedicationName(
                    medicationDisplayName(
                      item['drug_name'],
                      standardDrugId: item['standard_drug_id'],
                    ),
                  ),
                  taken: counts.taken,
                  missed: counts.missed,
                  unrecorded: counts.unrecorded,
                );
              }(),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              const _MedicationPageHeading('用药提醒'),
              const SizedBox(height: 16),
              if (reminders.isEmpty)
                const _MedicationEmptyCard(message: '还没有当前用药')
              else
                _ReminderCard(reminders: reminders),
              if (monthlyRows.isNotEmpty) ...[
                const SizedBox(height: 28),
                const _MedicationPageHeading('本月状态'),
                const SizedBox(height: 16),
                _MonthlyMedicationCard(
                  rows: monthlyRows,
                  onRowTap:
                      (status) =>
                          _showMonthlyMedicationDetails(context, ref, status),
                ),
              ],
              const SizedBox(height: 28),
              const _MedicationPageHeading('停换药历史'),
              const SizedBox(height: 16),
              _MedicationHistoryCard(
                items: inactive,
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
    final route = TextEditingController();
    Map<String, dynamic>? selectedCandidate;
    final catalogFuture = ref.read(medicationCatalogProvider.future);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: catalogFuture,
                    builder: (context, snapshot) {
                      final candidates = snapshot.data ?? const [];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '添加用药',
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '可从 Pomi 候选库选择，也可以完全自定义。候选库只用于识别和展示，不会自动生成提醒方案。',
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            const LinearProgressIndicator(),
                          if (candidates.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  selectedCandidate?['id']?.toString(),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Pomi 候选药品（可选）',
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('自定义药品'),
                                ),
                                ...candidates.map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item['id']?.toString(),
                                    child: Text(
                                      '${item['name']} · ${item['category']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (id) {
                                final candidate =
                                    candidates
                                        .where(
                                          (item) =>
                                              item['id']?.toString() == id,
                                        )
                                        .firstOrNull;
                                setSheetState(() {
                                  selectedCandidate = candidate;
                                  if (candidate != null) {
                                    name.text =
                                        candidate['name']?.toString() ?? '';
                                    route.text =
                                        candidate['route']?.toString() ?? '';
                                    final strengths =
                                        candidate['strength_candidates']
                                            as List?;
                                    if (strengths != null &&
                                        strengths.isNotEmpty) {
                                      dose.text = strengths.first.toString();
                                    }
                                  }
                                });
                              },
                            ),
                          ],
                          if (snapshot.hasError)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '候选库暂时不可用，仍可继续自定义添加。',
                                style:
                                    Theme.of(sheetContext).textTheme.bodySmall,
                              ),
                            ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: '药品名称',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: dose,
                            decoration: const InputDecoration(
                              labelText: '每次用量 / 规格',
                              hintText: '例如：500 mg、1 片',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: frequency,
                            decoration: const InputDecoration(
                              labelText: '每日用量 / 频次',
                              hintText: '例如：每日 2 次，早晚各 1 次',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: route,
                            decoration: const InputDecoration(
                              labelText: '给药途径（可选）',
                              hintText: '例如：口服、皮下注射',
                            ),
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
                                      'standard_drug_id':
                                          selectedCandidate?['id'],
                                      'source_category':
                                          _sourceCategoryForCandidate(
                                            selectedCandidate,
                                          ),
                                      'specification':
                                          dose.text.trim().isEmpty
                                              ? null
                                              : dose.text.trim(),
                                      'frequency':
                                          frequency.text.trim().isEmpty
                                              ? null
                                              : frequency.text.trim(),
                                      'route':
                                          route.text.trim().isEmpty
                                              ? null
                                              : route.text.trim(),
                                    },
                                  );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                            },
                            child: const Text('保存到我的用药'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
    );
    name.dispose();
    dose.dispose();
    frequency.dispose();
    route.dispose();
    if (saved == true) {
      ref.invalidate(medicationsProvider);
      ref.invalidate(dashboardProvider);
    }
  }
}

String _sourceCategoryForCandidate(Map<String, dynamic>? candidate) {
  if (candidate?['item_type']?.toString() == '补充剂') return 'supplement';
  if (candidate?['item_type']?.toString() == '处方药') return 'prescribed';
  return 'other_long_term';
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
  const _MedicationReminder({
    required this.medicationId,
    required this.name,
    required this.doseCount,
    this.frequencyLabel,
  });

  final String medicationId;
  final String name;

  /// 每天服用次数（由 frequency 解析，1–4）。
  final int doseCount;
  final String? frequencyLabel;
}

/// 由「每日两次」「每天3次」「BID/TID」等 frequency 文案推断每天服用次数。
int _dosesPerDay(String? frequency) {
  final raw = (frequency ?? '').toLowerCase().trim();
  if (raw.isEmpty) return 1;
  if (raw.contains('qid') || raw.contains('每日四') || raw.contains('每天四')) {
    return 4;
  }
  if (raw.contains('tid') ||
      raw.contains('三次') ||
      raw.contains('3次') ||
      raw.contains('每日三') ||
      raw.contains('每天三') ||
      raw.contains('每8小时') ||
      raw.contains('每八小时')) {
    return 3;
  }
  if (raw.contains('bid') ||
      raw.contains('两次') ||
      raw.contains('二次') ||
      raw.contains('2次') ||
      raw.contains('每日两') ||
      raw.contains('每天两') ||
      raw.contains('每12小时') ||
      raw.contains('早晚')) {
    return 2;
  }
  final match = RegExp(r'(\d+)\s*次').firstMatch(raw);
  if (match != null) {
    final n = int.tryParse(match.group(1)!) ?? 1;
    return n.clamp(1, 4);
  }
  return 1;
}

/// 每天 N 次的默认提醒时间。
List<TimeOfDay> _defaultReminderTimes(int count) => switch (count) {
  >= 4 => const [
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 12, minute: 0),
    TimeOfDay(hour: 16, minute: 0),
    TimeOfDay(hour: 20, minute: 0),
  ],
  3 => const [
    TimeOfDay(hour: 8, minute: 0),
    TimeOfDay(hour: 13, minute: 0),
    TimeOfDay(hour: 19, minute: 0),
  ],
  2 => const [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
  _ => const [TimeOfDay(hour: 8, minute: 0)],
};

String _formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 用药提醒的本地设置（后端无对应字段），按 medication_id + slot 序号存
/// SharedPreferences：`pomi_med_reminder_<id>_<i>` = "HH:mm" 或 "off"。
class _MedicationReminderStore {
  static String _key(String id, int slot) => 'pomi_med_reminder_${id}_$slot';

  static Future<List<_ReminderSlot>> load(
    String medicationId,
    int doseCount,
  ) async {
    final defaults = _defaultReminderTimes(doseCount);
    final fallback = [
      for (final t in defaults) _ReminderSlot(time: t, enabled: true),
    ];
    if (medicationId.isEmpty) return fallback;
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return fallback;
    }
    return [
      for (var i = 0; i < defaults.length; i++)
        () {
          final stored = prefs.getString(_key(medicationId, i));
          if (stored == 'off') {
            return _ReminderSlot(time: defaults[i], enabled: false);
          }
          final parts = stored?.split(':');
          if (parts != null && parts.length == 2) {
            final h = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            if (h != null && m != null) {
              return _ReminderSlot(
                time: TimeOfDay(hour: h, minute: m),
                enabled: true,
              );
            }
          }
          return _ReminderSlot(time: defaults[i], enabled: true);
        }(),
    ];
  }

  static Future<void> save(
    String medicationId,
    int slot,
    _ReminderSlot value,
  ) async {
    if (medicationId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(medicationId, slot),
      value.enabled ? _formatTimeOfDay(value.time) : 'off',
    );
  }
}

class _ReminderSlot {
  const _ReminderSlot({required this.time, required this.enabled});
  final TimeOfDay time;
  final bool enabled;

  _ReminderSlot copyWith({TimeOfDay? time, bool? enabled}) =>
      _ReminderSlot(time: time ?? this.time, enabled: enabled ?? this.enabled);
}

class _ReminderCard extends StatefulWidget {
  const _ReminderCard({required this.reminders});

  final List<_MedicationReminder> reminders;

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  /// medicationId -> 各次的提醒设置。
  final Map<String, List<_ReminderSlot>> _slots = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    for (final reminder in widget.reminders) {
      final slots = await _MedicationReminderStore.load(
        reminder.medicationId,
        reminder.doseCount,
      );
      if (!mounted) return;
      setState(() => _slots[reminder.medicationId] = slots);
    }
  }

  Future<void> _updateSlot(
    _MedicationReminder reminder,
    int index,
    _ReminderSlot value,
  ) async {
    setState(() {
      final list = List<_ReminderSlot>.from(
        _slots[reminder.medicationId] ??
            _defaultReminderTimes(
              reminder.doseCount,
            ).map((t) => _ReminderSlot(time: t, enabled: true)),
      );
      list[index] = value;
      _slots[reminder.medicationId] = list;
    });
    await _MedicationReminderStore.save(reminder.medicationId, index, value);
  }

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      borderRadius: 22,
      backgroundOpacity: .34,
      child: Column(
        children: [
          for (var index = 0; index < widget.reminders.length; index++) ...[
            _MedicationReminderTile(
              reminder: widget.reminders[index],
              slots:
                  _slots[widget.reminders[index].medicationId] ??
                  _defaultReminderTimes(
                    widget.reminders[index].doseCount,
                  ).map((t) => _ReminderSlot(time: t, enabled: true)).toList(),
              onSlotChanged:
                  (slotIndex, value) =>
                      _updateSlot(widget.reminders[index], slotIndex, value),
            ),
            if (index != widget.reminders.length - 1)
              const Divider(height: 1, color: pomiLine),
          ],
        ],
      ),
    );
  }
}

class _MedicationReminderTile extends StatelessWidget {
  const _MedicationReminderTile({
    required this.reminder,
    required this.slots,
    required this.onSlotChanged,
  });

  final _MedicationReminder reminder;
  final List<_ReminderSlot> slots;
  final void Function(int index, _ReminderSlot value) onSlotChanged;

  @override
  Widget build(BuildContext context) {
    final freqText =
        reminder.doseCount > 1
            ? '每日 ${reminder.doseCount} 次'
            : (reminder.frequencyLabel?.trim().isNotEmpty == true
                ? reminder.frequencyLabel!.trim()
                : '每日提醒');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
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
          Text(freqText, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          for (var i = 0; i < slots.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == slots.length - 1 ? 0 : 8),
              child: _ReminderRow(
                slot: slots[i],
                label: slots.length > 1 ? '第 ${i + 1} 次' : null,
                onTimeTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: slots[i].time,
                  );
                  if (picked != null) {
                    onSlotChanged(i, slots[i].copyWith(time: picked));
                  }
                },
                onEnabledChanged:
                    (v) => onSlotChanged(i, slots[i].copyWith(enabled: v)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.slot,
    required this.onTimeTap,
    required this.onEnabledChanged,
    this.label,
  });

  final _ReminderSlot slot;
  final String? label;
  final VoidCallback onTimeTap;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: onTimeTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 40,
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
                      _formatTimeOfDay(slot.time),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: slot.enabled ? pomiPurple : pomiSecondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.schedule,
                      color: slot.enabled ? pomiInk : pomiSecondaryText,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: slot.enabled,
          onChanged: onEnabledChanged,
          activeTrackColor: pomiMint,
          activeThumbColor: Colors.white,
        ),
      ],
    );
  }
}

class _MonthlyMedicationStatus {
  const _MonthlyMedicationStatus({
    this.medicationId,
    required this.name,
    required this.taken,
    required this.missed,
    required this.unrecorded,
  });

  final String? medicationId;
  final String name;
  final int taken;
  final int missed;
  final int unrecorded;
}

Future<void> _showMonthlyMedicationDetails(
  BuildContext context,
  WidgetRef ref,
  _MonthlyMedicationStatus summary,
) async {
  final medicationId = summary.medicationId;
  if (medicationId == null || medicationId.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('当前用药缺少记录编号，暂时无法查看本月明细')));
    return;
  }
  final today = DateUtils.dateOnly(DateTime.now());
  final from = DateTime(today.year, today.month);
  final future = ref
      .read(apiClientProvider)
      .get(
        '/api/medication-daily',
        queryParameters: {
          'from':
              '${from.year.toString().padLeft(4, '0')}-${from.month.toString().padLeft(2, '0')}-01',
          'to': today.toIso8601String().substring(0, 10),
          'medication_id': medicationId,
        },
      );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    builder:
        (_) => _MonthlyMedicationDetailsSheet(
          medicationName: summary.name,
          month: today,
          recordsFuture: future,
        ),
  );
}

class _MonthlyMedicationDetailsSheet extends StatelessWidget {
  const _MonthlyMedicationDetailsSheet({
    required this.medicationName,
    required this.month,
    required this.recordsFuture,
  });

  final String medicationName;
  final DateTime month;
  final Future<dynamic> recordsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: recordsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$medicationName · 本月用药',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text('暂时无法读取本月用药记录，请稍后重试。'),
              ],
            ),
          );
        }
        final records = (snapshot.data as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        return _MonthlyMedicationCalendar(
          medicationName: medicationName,
          month: month,
          records: records,
        );
      },
    );
  }
}

class _MonthlyMedicationCalendar extends StatelessWidget {
  const _MonthlyMedicationCalendar({
    required this.medicationName,
    required this.month,
    required this.records,
  });

  final String medicationName;
  final DateTime month;
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final statusByDate = <String, String>{};
    for (final record in records) {
      final rawDate = record['record_date']?.toString() ?? '';
      if (rawDate.length < 10) continue;
      statusByDate[rawDate.substring(0, 10)] =
          record['intake_status']?.toString() ?? 'unrecorded';
    }
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final cells = <int?>[
      ...List<int?>.filled(firstWeekday, null),
      for (var day = 1; day <= daysInMonth; day++) day,
    ];
    final missedDates = _datesWithStatus(statusByDate, 'missed');
    final unrecordedDates = _datesWithStatus(statusByDate, 'unrecorded');
    final takenCount = _datesWithStatus(statusByDate, 'taken').length;
    final today = DateUtils.dateOnly(DateTime.now());
    final monthLabel = '${month.year}年${month.month}月';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$medicationName · $monthLabel',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '已服用 $takenCount 天 · 主动漏服 ${missedDates.length} 天 · 未记录 ${unrecordedDates.length} 天',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                _MonthWeekdayLabel('日'),
                _MonthWeekdayLabel('一'),
                _MonthWeekdayLabel('二'),
                _MonthWeekdayLabel('三'),
                _MonthWeekdayLabel('四'),
                _MonthWeekdayLabel('五'),
                _MonthWeekdayLabel('六'),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final day = cells[index];
                if (day == null) return const SizedBox.shrink();
                final date = DateTime(month.year, month.month, day);
                final key = date.toIso8601String().substring(0, 10);
                final recorded = statusByDate[key];
                final String status;
                if (recorded != null) {
                  status = recorded;
                } else if (date.isAfter(today)) {
                  status = 'future';
                } else {
                  status = 'none';
                }
                return _MonthStatusCell(day: day, status: status);
              },
            ),
            const SizedBox(height: 18),
            _DateListSection(
              title: '主动漏服日期',
              dates: missedDates,
              color: pomiCoral,
              emptyLabel: '本月没有主动漏服记录',
            ),
            const SizedBox(height: 10),
            _DateListSection(
              title: '未记录日期',
              dates: unrecordedDates,
              color: pomiSecondaryText,
              emptyLabel: '本月每天都有状态记录',
            ),
            const SizedBox(height: 14),
            Text(
              '灰色日期表示尚未记录，不等同于漏服。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  List<String> _datesWithStatus(Map<String, String> statuses, String status) =>
      statuses.entries
          .where((entry) => entry.value == status)
          .map((entry) => entry.key)
          .toList()
        ..sort();
}

class _MonthWeekdayLabel extends StatelessWidget {
  const _MonthWeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Center(
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

class _MonthStatusCell extends StatelessWidget {
  const _MonthStatusCell({required this.day, required this.status});

  final int day;
  final String status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      'taken' => (pomiSuccess.withValues(alpha: .14), pomiSuccess),
      'missed' => (pomiCoral.withValues(alpha: .30), const Color(0xFFB85E4D)),
      'unrecorded' => (pomiLine.withValues(alpha: .72), pomiSecondaryText),
      'future' => (
        Colors.transparent,
        pomiSecondaryText.withValues(alpha: .35),
      ),
      // 'none'：本月内、非应服药日或无记录 —— 只显示浅底日期。
      _ => (const Color(0xFFF3F1F6), pomiSecondaryText.withValues(alpha: .8)),
    };
    return Tooltip(
      message: switch (status) {
        'taken' => '已服用',
        'missed' => '主动漏服',
        'unrecorded' => '未记录',
        _ => '$day 日',
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                status == 'future'
                    ? Colors.transparent
                    : foreground.withValues(alpha: .14),
          ),
        ),
        child: Text(
          '$day',
          style: TextStyle(
            color: foreground,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DateListSection extends StatelessWidget {
  const _DateListSection({
    required this.title,
    required this.dates,
    required this.color,
    required this.emptyLabel,
  });

  final String title;
  final List<String> dates;
  final Color color;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final labels = dates.map(
      (date) =>
          '${int.parse(date.substring(5, 7))}月${int.parse(date.substring(8, 10))}日',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (dates.isEmpty)
          Text(emptyLabel, style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                labels
                    .map(
                      (label) => Chip(
                        label: Text(label),
                        labelStyle: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                        backgroundColor: color.withValues(alpha: .12),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
          ),
      ],
    );
  }
}

class _MonthlyMedicationCard extends StatelessWidget {
  const _MonthlyMedicationCard({required this.rows, required this.onRowTap});

  final List<_MonthlyMedicationStatus> rows;
  final ValueChanged<_MonthlyMedicationStatus> onRowTap;

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      borderRadius: 22,
      backgroundOpacity: .34,
      child: Column(
        children: [
          for (final row in rows) ...[
            _MonthlyMedicationRow(status: row, onTap: () => onRowTap(row)),
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
  const _MonthlyMedicationRow({required this.status, required this.onTap});

  final _MonthlyMedicationStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看${status.name}本月用药记录',
      onTap: onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 105,
                  child: Text(
                    status.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 17, color: pomiMuted),
              ],
            ),
          ),
        ),
      ),
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
  const _MedicationHistoryCard({required this.items, required this.onRejoin});

  final List<Map<String, dynamic>>? items;
  final VoidCallback onRejoin;

  @override
  Widget build(BuildContext context) {
    final records = items;
    if (records != null && records.isEmpty) {
      return const _MedicationEmptyCard(message: '暂无停换药历史');
    }
    return PomiGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      borderRadius: 22,
      backgroundOpacity: .34,
      child: Column(
        children:
            records == null
                ? [
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
                ]
                : [
                  for (var index = 0; index < records.length; index++) ...[
                    _MedicationHistoryRow(
                      name: medicationDisplayName(
                        records[index]['drug_name'],
                        standardDrugId: records[index]['standard_drug_id'],
                      ),
                      detail: _medicationHistoryDetail(records[index]),
                      onRejoin: onRejoin,
                    ),
                    if (index != records.length - 1)
                      const Divider(height: 1, color: pomiLine),
                  ],
                ],
      ),
    );
  }

  static String _medicationHistoryDetail(Map<String, dynamic> item) {
    final start = item['start_date']?.toString();
    final end = item['end_date']?.toString();
    final dates = [
      if (start != null && start.isNotEmpty) start,
      if (end != null && end.isNotEmpty) end,
    ].join(' ~ ');
    final status = switch (item['current_status']?.toString()) {
      'paused' => '已暂停',
      'stopped' => '已停用',
      _ => '历史用药',
    };
    return [if (dates.isNotEmpty) dates, status].join(' · ');
  }
}

class _MedicationEmptyCard extends StatelessWidget {
  const _MedicationEmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PomiGlassCard(
    borderRadius: 22,
    backgroundOpacity: .34,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
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

    return SizedBox(
      width: double.infinity,
      child: PomiGlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
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
                  child: const Icon(
                    Icons.chevron_right,
                    color: pomiInk,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (medicines.isEmpty)
              Align(
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
            else
              ...medicines.indexed.map(
                (entry) => _MedicationProgressRow(
                  medicine: entry.$2,
                  index: entry.$1,
                  onUpdated: onUpdated,
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
    final dosage = medicine['dosage_text']?.toString().trim() ?? '';
    final dailyAmount = medicine['frequency']?.toString().trim() ?? '';
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
                  medicationDisplayName(
                    medicine['drug_name'],
                    standardDrugId: medicine['standard_drug_id'],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPending ? pomiInk : pomiSecondaryText,
                    fontSize: 15,
                    height: 21 / 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (dosage.isNotEmpty)
                  Text(
                    '每次用量：$dosage',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: pomiSecondaryText,
                      fontSize: 12,
                      height: 17 / 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                if (dailyAmount.isNotEmpty)
                  Text(
                    '每日用量：$dailyAmount',
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
