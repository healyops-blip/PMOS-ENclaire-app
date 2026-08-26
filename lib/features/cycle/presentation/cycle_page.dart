import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_line_chart.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:table_calendar/table_calendar.dart';

class CyclePage extends StatefulWidget {
  const CyclePage({super.key});

  @override
  State<CyclePage> createState() => _CyclePageState();
}

class _CyclePageState extends State<CyclePage> {
  DateTime _focusedDay = DateTime(2026, 8, 26);
  DateTime _selectedDay = DateTime(2026, 8, 26);
  final Set<DateTime> _periodDays = {
    for (var day = 6; day <= 10; day++) DateTime(2026, 8, day),
  };
  final Map<DateTime, double> _weights = {
    DateTime(2026, 8, 3): 70.8,
    DateTime(2026, 8, 10): 70.2,
    DateTime(2026, 8, 17): 69.9,
    DateTime(2026, 8, 24): 69.6,
  };

  DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

  void _togglePeriod() {
    final day = _dateOnly(_selectedDay);
    setState(() {
      if (_periodDays.contains(day)) {
        _periodDays.remove(day);
      } else {
        _periodDays.add(day);
      }
    });
  }

  Future<void> _recordWeight() async {
    final controller = TextEditingController(
      text: _weights[_dateOnly(_selectedDay)]?.toString() ?? '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录体重'),
        content: TextField(
          key: const Key('weight-input'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: 'kg',
            hintText: '例如 69.5',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result < 30 || result > 250) return;
    setState(() => _weights[_dateOnly(_selectedDay)] = result);
  }

  @override
  Widget build(BuildContext context) {
    final sortedWeights = _weights.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ColoredBox(
      key: const Key('cycle-page'),
      color: PomiColors.primaryPale,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: PomiPageHeader(
              title: '经期与体重',
              subtitle: '把身体变化放在同一条时间线上',
              trailing: DemoBadge(label: '模拟数据'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 126),
            sliver: SliverList.list(
              children: [
                PomiSectionCard(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                  child: TableCalendar<String>(
                    firstDay: DateTime(2025),
                    lastDay: DateTime(2027, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) =>
                        _periodDays.contains(_dateOnly(day)),
                    eventLoader: (day) => _weights.containsKey(_dateOnly(day))
                        ? const ['weight']
                        : const [],
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDay = _dateOnly(selected);
                        _focusedDay = focused;
                      });
                    },
                    onPageChanged: (focused) => _focusedDay = focused,
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextFormatter: (date, _) =>
                          '${date.year} 年 ${date.month} 月',
                      titleTextStyle: const TextStyle(
                        color: PomiColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      leftChevronIcon: const Icon(
                        Icons.chevron_left_rounded,
                        color: PomiColors.primary,
                      ),
                      rightChevronIcon: const Icon(
                        Icons.chevron_right_rounded,
                        color: PomiColors.primary,
                      ),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        color: PomiColors.textMuted,
                        fontSize: 11,
                      ),
                      weekendStyle: TextStyle(
                        color: PomiColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      todayDecoration: BoxDecoration(
                        border: Border.all(
                          color: PomiColors.primary,
                          width: 1.5,
                        ),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: const TextStyle(
                        color: PomiColors.primary,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: PomiColors.primary,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: const BoxDecoration(
                        color: PomiColors.accent,
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('toggle-period-button'),
                        onPressed: _togglePeriod,
                        icon: const Icon(Icons.water_drop_outlined),
                        label: Text(
                          _periodDays.contains(_dateOnly(_selectedDay))
                              ? '取消经期标记'
                              : '标记为经期',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('record-weight-button'),
                        onPressed: _recordWeight,
                        icon: const Icon(Icons.monitor_weight_outlined),
                        label: const Text('记录体重'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const PomiSectionTitle(title: '本周期概览'),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Expanded(
                      child: _CycleMetric(label: '当前周期', value: '第 20 天'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _CycleMetric(label: '平均周期', value: '39 天'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _CycleMetric(label: '经期时长', value: '5 天'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const PomiSectionTitle(title: '周期趋势'),
                const SizedBox(height: 8),
                const PomiSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '近 6 个周期',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 12),
                      PomiLineChart(
                        values: [42, 38, 44, 36, 40, 39],
                        labels: ['3月', '4月', '5月', '6月', '7月', '8月'],
                        color: PomiColors.primary,
                        minY: 30,
                        maxY: 48,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const PomiSectionTitle(title: '体重趋势'),
                const SizedBox(height: 8),
                PomiSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sortedWeights.last.value.toStringAsFixed(1)} kg',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const Text(
                        '较月初下降 1.2 kg',
                        style: TextStyle(
                          color: PomiColors.success,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PomiLineChart(
                        values: [for (final item in sortedWeights) item.value],
                        labels: [
                          for (final item in sortedWeights)
                            '${item.key.month}/${item.key.day}',
                        ],
                        color: PomiColors.glowPink,
                        minY: 68.5,
                        maxY: 71.5,
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

class _CycleMetric extends StatelessWidget {
  const _CycleMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return PomiSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: PomiColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
