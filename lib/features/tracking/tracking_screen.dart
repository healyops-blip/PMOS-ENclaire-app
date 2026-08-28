import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

final trackingProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final values = await Future.wait([
    ref.read(apiClientProvider).get('/api/cycles'),
    ref.read(apiClientProvider).get('/api/weights'),
  ]);
  return {'cycles': values[0], 'weights': values[1]};
});

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  DateTime _focusedDay = DateUtils.dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('经期与体重')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (data) {
          final cycles = List<Map<String, dynamic>>.from(
            (data['cycles'] as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );
          final weights = List<Map<String, dynamic>>.from(
            (data['weights'] as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(trackingProvider);
              await ref.read(trackingProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: TableCalendar<void>(
                      locale: 'zh_CN',
                      firstDay: DateTime(2020),
                      lastDay: DateTime(DateTime.now().year + 1, 12, 31),
                      focusedDay: _focusedDay,
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(color: pomiMuted, fontSize: 11),
                        weekendStyle: TextStyle(color: pomiMuted, fontSize: 11),
                      ),
                      calendarStyle: const CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: pomiPurpleSoft,
                          shape: BoxShape.circle,
                        ),
                        outsideTextStyle: TextStyle(color: Color(0xFFD0CBD3)),
                      ),
                      onPageChanged: (day) => _focusedDay = day,
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() => _focusedDay = focusedDay);
                        _addCycle(context, ref, initialStart: selectedDay);
                      },
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder:
                            (context, day, focusedDay) => _CalendarDay(
                              day: day,
                              period: _isPeriodDay(day, cycles),
                              weighted: _hasWeight(day, weights),
                            ),
                        todayBuilder:
                            (context, day, focusedDay) => _CalendarDay(
                              day: day,
                              period: _isPeriodDay(day, cycles),
                              weighted: _hasWeight(day, weights),
                              today: true,
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendDot(color: pomiPurple, label: '经期（点选日期记录）'),
                    SizedBox(width: 16),
                    _LegendDot(color: pomiMint, label: '体重记录日'),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '周期统计',
                  action: TextButton.icon(
                    onPressed: () => _addCycle(context, ref),
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('记录经期'),
                  ),
                  child: _CycleStats(cycles: cycles),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: '体重记录',
                  action: FilledButton.tonalIcon(
                    onPressed: () => _addWeight(context, ref),
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('记录'),
                  ),
                  child: _WeightPanel(weights: weights),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isPeriodDay(DateTime day, List<Map<String, dynamic>> cycles) {
    final target = DateUtils.dateOnly(day);
    return cycles.any((cycle) {
      final start = DateTime.tryParse(cycle['start_date'].toString());
      if (start == null) return false;
      final end =
          DateTime.tryParse(cycle['end_date']?.toString() ?? '') ?? start;
      return !target.isBefore(DateUtils.dateOnly(start)) &&
          !target.isAfter(DateUtils.dateOnly(end));
    });
  }

  bool _hasWeight(DateTime day, List<Map<String, dynamic>> weights) =>
      weights.any((weight) {
        final date = DateTime.tryParse(weight['record_date'].toString());
        return date != null && DateUtils.isSameDay(date.toLocal(), day);
      });

  Future<void> _addCycle(
    BuildContext context,
    WidgetRef ref, {
    DateTime? initialStart,
  }) async {
    DateTime start = DateUtils.dateOnly(initialStart ?? DateTime.now());
    DateTime? end;
    String flow = 'medium';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => Padding(
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
                        '记录经期',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '选择开始与结束日期；未结束时可以只保存开始日期。',
                        style: TextStyle(color: pomiMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('开始日期'),
                        trailing: Text(
                          start.toIso8601String().substring(0, 10),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            initialDate: start,
                          );
                          if (value != null) setSheetState(() => start = value);
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('结束日期'),
                        trailing: Text(
                          end?.toIso8601String().substring(0, 10) ?? '进行中',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: start,
                            lastDate: DateTime.now(),
                            initialDate: end ?? start,
                          );
                          if (value != null) setSheetState(() => end = value);
                        },
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: flow,
                        decoration: const InputDecoration(labelText: '经量'),
                        items: const [
                          DropdownMenuItem(value: 'light', child: Text('少')),
                          DropdownMenuItem(value: 'medium', child: Text('中')),
                          DropdownMenuItem(value: 'heavy', child: Text('多')),
                        ],
                        onChanged: (value) => flow = value ?? flow,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () async {
                          await ref
                              .read(apiClientProvider)
                              .post(
                                '/api/cycles',
                                data: {
                                  'start_date': start
                                      .toIso8601String()
                                      .substring(0, 10),
                                  'end_date': end?.toIso8601String().substring(
                                    0,
                                    10,
                                  ),
                                  'flow_level': flow,
                                },
                              );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
          ),
    );
    if (saved == true) ref.invalidate(trackingProvider);
  }

  Future<void> _addWeight(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    DateTime date = DateTime.now();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => Padding(
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
                        '记录体重',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('日期'),
                        trailing: Text(
                          date.toIso8601String().substring(0, 10),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            initialDate: date,
                          );
                          if (value != null) setSheetState(() => date = value);
                        },
                      ),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '体重',
                          suffixText: 'kg',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () async {
                          final value = double.tryParse(controller.text);
                          if (value == null) return;
                          await ref
                              .read(apiClientProvider)
                              .post(
                                '/api/weights',
                                data: {
                                  'record_date': date
                                      .toIso8601String()
                                      .substring(0, 10),
                                  'weight_kg': value,
                                },
                              );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
          ),
    );
    controller.dispose();
    if (saved == true) ref.invalidate(trackingProvider);
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.period,
    required this.weighted,
    this.today = false,
  });
  final DateTime day;
  final bool period;
  final bool weighted;
  final bool today;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color:
            period
                ? pomiPurple
                : (today
                    ? pomiPurpleSoft.withValues(alpha: .22)
                    : Colors.transparent),
        shape: BoxShape.circle,
        border: today && !period ? Border.all(color: pomiPurpleSoft) : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              color: period ? Colors.white : pomiInk,
              fontWeight: period || today ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          if (weighted)
            Positioned(
              bottom: 3,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: period ? Colors.white : pomiMint,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: pomiMuted, fontSize: 10)),
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    required this.action,
  });
  final String title;
  final Widget child;
  final Widget action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              action,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _CycleStats extends StatelessWidget {
  const _CycleStats({required this.cycles});
  final List<Map<String, dynamic>> cycles;
  @override
  Widget build(BuildContext context) {
    final latest = cycles.isEmpty ? null : cycles.first;
    final start = DateTime.tryParse(latest?['start_date']?.toString() ?? '');
    final end = DateTime.tryParse(latest?['end_date']?.toString() ?? '');
    final duration =
        start == null
            ? null
            : (end ?? DateTime.now()).difference(start).inDays + 1;
    return Column(
      children: [
        _DataRow(
          label: '最近一次开始',
          value: latest?['start_date']?.toString() ?? '未记录',
        ),
        _DataRow(label: '经期持续', value: duration == null ? '—' : '$duration 天'),
        _DataRow(label: '记录次数', value: '${cycles.length} 次'),
      ],
    );
  }
}

class _WeightPanel extends StatelessWidget {
  const _WeightPanel({required this.weights});
  final List<Map<String, dynamic>> weights;
  @override
  Widget build(BuildContext context) {
    if (weights.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '还没有体重记录',
          textAlign: TextAlign.center,
          style: TextStyle(color: pomiMuted),
        ),
      );
    }
    final ordered = weights.reversed.take(10).toList();
    final spots = List.generate(
      ordered.length,
      (index) => FlSpot(
        index.toDouble(),
        (ordered[index]['weight_kg'] as num).toDouble(),
      ),
    );
    return Column(
      children: [
        _DataRow(label: '最新体重', value: '${weights.first['weight_kg']} kg'),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 38),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: pomiPurple,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: pomiPurple.withValues(alpha: .08),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...weights
            .take(3)
            .map(
              (item) => _DataRow(
                label: item['record_date'].toString().substring(0, 10),
                value: '${item['weight_kg']} kg',
              ),
            ),
      ],
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: pomiMuted))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
