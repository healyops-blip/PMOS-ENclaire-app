import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_line_chart.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/weight/application/weight_controller.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_input_validator.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_record.dart';
import 'package:table_calendar/table_calendar.dart';

class CyclePage extends StatefulWidget {
  const CyclePage({required this.weightController, super.key});

  final WeightController weightController;

  @override
  State<CyclePage> createState() => _CyclePageState();
}

class _CyclePageState extends State<CyclePage> {
  DateTime _focusedDay = DateTime(2026, 8, 27);
  DateTime _selectedDay = DateTime(2026, 8, 27);
  final Set<DateTime> _periodDays = {
    for (var day = 6; day <= 10; day++) DateTime(2026, 8, day),
  };

  @override
  void initState() {
    super.initState();
    widget.weightController.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant CyclePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weightController != widget.weightController) {
      oldWidget.weightController.removeListener(_refresh);
      widget.weightController.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.weightController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

  WeightRecord? _recordFor(DateTime day) {
    final target = _dateOnly(day);
    for (final record in widget.weightController.records) {
      if (_dateOnly(record.recordDate) == target) return record;
    }
    return null;
  }

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
    final existing = _recordFor(_selectedDay);
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _WeightEntryDialog(
        recordDate: _selectedDay,
        initialWeight: existing?.weightKg,
      ),
    );
    if (result == null || !mounted) return;

    final saved = await widget.weightController.save(
      recordDate: _selectedDay,
      weightKg: result,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? '体重已保存'
              : widget.weightController.errorMessage ?? '保存失败，请稍后重试',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.weightController.records;
    return ColoredBox(
      key: const Key('cycle-page'),
      color: PomiColors.primaryPale,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: PomiPageHeader(
              title: '经期与体重',
              subtitle: '把身体变化放在同一条时间线上',
              trailing: DemoBadge(label: '经期为模拟数据'),
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
                    selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
                    eventLoader: (day) =>
                        _recordFor(day) == null ? const [] : const ['weight'],
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
                        onPressed: widget.weightController.isLoading
                            ? null
                            : _recordWeight,
                        icon: const Icon(Icons.monitor_weight_outlined),
                        label: Text(
                          _recordFor(_selectedDay) == null ? '记录体重' : '修改体重',
                        ),
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
                _WeightTrendCard(
                  records: records,
                  loading: widget.weightController.isLoading,
                  errorMessage: widget.weightController.errorMessage,
                  onRetry: widget.weightController.load,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightEntryDialog extends StatefulWidget {
  const _WeightEntryDialog({required this.recordDate, this.initialWeight});

  final DateTime recordDate;
  final double? initialWeight;

  @override
  State<_WeightEntryDialog> createState() => _WeightEntryDialogState();
}

class _WeightEntryDialogState extends State<_WeightEntryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialWeight?.toStringAsFixed(1) ?? '',
  );
  String? _validationMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final message = validateWeightInput(_controller.text);
    if (message != null) {
      setState(() => _validationMessage = message);
      return;
    }
    Navigator.pop(context, double.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialWeight == null ? '记录体重' : '修改体重'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.recordDate.year} 年 ${widget.recordDate.month} 月 ${widget.recordDate.day} 日',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('weight-input'),
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: 'kg',
              hintText: '20.0–300.0',
              errorText: _validationMessage,
            ),
            autofocus: true,
            onChanged: (_) {
              if (_validationMessage != null) {
                setState(() => _validationMessage = null);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('save-weight-button'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _WeightTrendCard extends StatelessWidget {
  const _WeightTrendCard({
    required this.records,
    required this.loading,
    required this.errorMessage,
    required this.onRetry,
  });

  final List<WeightRecord> records;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && records.isEmpty) {
      return const PomiSectionCard(
        child: Center(
          child: CircularProgressIndicator(key: Key('weight-loading')),
        ),
      );
    }
    if (records.isEmpty) {
      return PomiSectionCard(
        child: Center(
          child: Padding(
            key: const Key('weight-empty-state'),
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Column(
              children: [
                const Icon(
                  Icons.monitor_weight_outlined,
                  color: PomiColors.primary,
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(errorMessage ?? '还没有体重记录'),
                const SizedBox(height: 4),
                Text(
                  errorMessage == null ? '选择上方日期，记录第一条体重' : '检查网络后重新加载',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (errorMessage != null)
                  TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }

    final latest = records.last;
    final change = latest.weightKg - records.first.weightKg;
    final changeLabel = records.length == 1
        ? '第一条体重记录'
        : '较首条${change > 0 ? '上升' : '下降'} ${change.abs().toStringAsFixed(1)} kg';
    return PomiSectionCard(
      key: const Key('weight-trend-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${latest.weightKg.toStringAsFixed(1)} kg',
                key: const Key('weight-latest-value'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              Text(
                '${latest.recordDate.year}-${latest.recordDate.month.toString().padLeft(2, '0')}-${latest.recordDate.day.toString().padLeft(2, '0')}',
                key: const Key('weight-latest-date'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Text(
            changeLabel,
            style: TextStyle(
              color: change <= 0 ? PomiColors.success : PomiColors.warning,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          PomiLineChart(
            values: [for (final record in records) record.weightKg],
            labels: [
              for (final record in records)
                '${record.recordDate.month}/${record.recordDate.day}',
            ],
            color: PomiColors.glowPink,
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
