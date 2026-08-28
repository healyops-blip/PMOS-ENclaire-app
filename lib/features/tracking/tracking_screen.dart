import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _cycleEditorExpanded = false;
  bool _savingCycle = false;
  DateTime _cycleStart = DateUtils.dateOnly(DateTime.now());
  DateTime? _cycleEnd;
  String _cycleFlow = 'medium';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingProvider);
    return Scaffold(
      appBar: AppBar(toolbarHeight: 12),
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
                _HorizontalCycleCalendar(
                  selectedDay: _focusedDay,
                  cycles: cycles,
                  weights: weights,
                  onSelected: (day) => setState(() => _focusedDay = day),
                  onAdd:
                      () => _addCycle(context, ref, initialStart: _focusedDay),
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '周期统计',
                  action: TextButton.icon(
                    onPressed:
                        () => setState(() {
                          _cycleEditorExpanded = !_cycleEditorExpanded;
                          if (_cycleEditorExpanded) {
                            _cycleStart = _focusedDay;
                            _cycleEnd = null;
                          }
                        }),
                    icon: Icon(
                      _cycleEditorExpanded ? Icons.remove : Icons.add,
                      size: 17,
                    ),
                    label: Text(_cycleEditorExpanded ? '收起' : '记录经期'),
                  ),
                  child: Column(
                    children: [
                      _CycleStats(cycles: cycles),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child:
                            _cycleEditorExpanded
                                ? _InlineCycleEditor(
                                  start: _cycleStart,
                                  end: _cycleEnd,
                                  flow: _cycleFlow,
                                  saving: _savingCycle,
                                  onStartTap: _selectInlineCycleStart,
                                  onEndTap: _selectInlineCycleEnd,
                                  onFlowChanged:
                                      (value) =>
                                          setState(() => _cycleFlow = value),
                                  onSave: _saveInlineCycle,
                                )
                                : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _WeightTrendCard(
                  weights: weights,
                  onViewMore: () => _showWeightHistory(context, ref, weights),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _selectInlineCycleStart() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _cycleStart,
    );
    if (value == null || !mounted) return;
    setState(() {
      _cycleStart = DateUtils.dateOnly(value);
      if (_cycleEnd?.isBefore(_cycleStart) == true) _cycleEnd = null;
    });
  }

  Future<void> _selectInlineCycleEnd() async {
    final value = await showDatePicker(
      context: context,
      firstDate: _cycleStart,
      lastDate: DateTime.now(),
      initialDate: _cycleEnd ?? _cycleStart,
    );
    if (value == null || !mounted) return;
    setState(() => _cycleEnd = DateUtils.dateOnly(value));
  }

  Future<void> _saveInlineCycle() async {
    if (_savingCycle) return;
    setState(() => _savingCycle = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/api/cycles',
            data: {
              'start_date': _cycleStart.toIso8601String().substring(0, 10),
              'end_date': _cycleEnd?.toIso8601String().substring(0, 10),
              'flow_level': _cycleFlow,
            },
          );
      ref.invalidate(trackingProvider);
      if (mounted) setState(() => _cycleEditorExpanded = false);
    } finally {
      if (mounted) setState(() => _savingCycle = false);
    }
  }

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
                          final today = DateUtils.dateOnly(DateTime.now());
                          if (start.isAfter(today) ||
                              (end != null && end!.isAfter(today))) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('只能记录今天及之前的经期')),
                            );
                            return;
                          }
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
                          if (date.isAfter(
                            DateUtils.dateOnly(DateTime.now()),
                          )) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('只能记录今天及之前的体重')),
                            );
                            return;
                          }
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

  Future<void> _showWeightHistory(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> weights,
  ) async {
    final ordered = [...weights]..sort(
      (a, b) =>
          a['record_date'].toString().compareTo(b['record_date'].toString()),
    );
    final addWeight = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: SizedBox(
                height: math.min(
                  MediaQuery.sizeOf(sheetContext).height * .68,
                  560,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '体重记录',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('记录体重'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (ordered.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            '还没有体重记录',
                            style: TextStyle(color: pomiSecondaryText),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: ordered.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (context, index) {
                            final item = ordered.reversed.elementAt(index);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.monitor_weight_outlined,
                                color: pomiPurple,
                              ),
                              title: Text(item['record_date'].toString()),
                              trailing: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: _formatWeight(item['weight_kg']),
                                      style: const TextStyle(
                                        color: pomiInk,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const TextSpan(
                                      text: ' kg',
                                      style: TextStyle(
                                        color: pomiSecondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
    if (addWeight == true && context.mounted) {
      await _addWeight(context, ref);
    }
  }
}

class _HorizontalCycleCalendar extends StatefulWidget {
  const _HorizontalCycleCalendar({
    required this.selectedDay,
    required this.cycles,
    required this.weights,
    required this.onSelected,
    required this.onAdd,
  });

  final DateTime selectedDay;
  final List<Map<String, dynamic>> cycles;
  final List<Map<String, dynamic>> weights;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onAdd;

  @override
  State<_HorizontalCycleCalendar> createState() =>
      _HorizontalCycleCalendarState();
}

class _HorizontalCycleCalendarState extends State<_HorizontalCycleCalendar> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(initialScrollOffset: 620);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = DateUtils.dateOnly(widget.selectedDay);
    final start = selected.subtract(const Duration(days: 14));
    final dates = List.generate(
      29,
      (index) => start.add(Duration(days: index)),
    );
    final weekday = const ['一', '二', '三', '四', '五', '六', '日'];

    return PomiGlassCard(
      borderRadius: 24,
      backgroundOpacity: .28,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selected.month}月${selected.day}日 星期${weekday[selected.weekday - 1]}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: pomiInk,
                        fontSize: 20,
                        height: 28 / 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '记录经期',
                    onPressed: widget.onAdd,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .48),
                      foregroundColor: pomiPurple,
                    ),
                    icon: const Icon(Icons.calendar_month_outlined, size: 21),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 116,
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: dates.length,
                separatorBuilder: (context, index) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final day = dates[index];
                  final isSelected = DateUtils.isSameDay(day, selected);
                  final isPeriod = _isPeriodDay(day);
                  final hasWeight = _hasWeight(day);
                  return _HorizontalCalendarDay(
                    day: day,
                    weekday: weekday[day.weekday - 1],
                    selected: isSelected,
                    period: isPeriod,
                    weighted: hasWeight,
                    onTap: () => widget.onSelected(day),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isPeriodDay(DateTime day) {
    final target = DateUtils.dateOnly(day);
    return widget.cycles.any((cycle) {
      final start = DateTime.tryParse(cycle['start_date'].toString());
      if (start == null) return false;
      final end =
          DateTime.tryParse(cycle['end_date']?.toString() ?? '') ?? start;
      return !target.isBefore(DateUtils.dateOnly(start)) &&
          !target.isAfter(DateUtils.dateOnly(end));
    });
  }

  bool _hasWeight(DateTime day) => widget.weights.any((weight) {
    final date = DateTime.tryParse(weight['record_date'].toString());
    return date != null && DateUtils.isSameDay(date.toLocal(), day);
  });
}

class _HorizontalCalendarDay extends StatelessWidget {
  const _HorizontalCalendarDay({
    required this.day,
    required this.weekday,
    required this.selected,
    required this.period,
    required this.weighted,
    required this.onTap,
  });

  final DateTime day;
  final String weekday;
  final bool selected;
  final bool period;
  final bool weighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            Text(
              weekday,
              style: TextStyle(
                color: selected ? pomiInk : pomiSecondaryText,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48,
              height: selected ? 76 : 68,
              decoration: BoxDecoration(
                color:
                    selected
                        ? pomiPurple.withValues(alpha: .13)
                        : const Color(0xFFF1EFF5),
                borderRadius: BorderRadius.circular(26),
                border:
                    selected
                        ? Border.all(color: pomiPurple.withValues(alpha: .22))
                        : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color:
                          period
                              ? pomiCoral.withValues(alpha: .88)
                              : Colors.white.withValues(alpha: .72),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: period ? Colors.white : pomiInk,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (weighted)
                    Positioned(
                      bottom: 7,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: pomiMint,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => PomiGlassCard(
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
        _DataRow(
          label: '经期持续',
          value: duration == null ? '—' : '$duration',
          unit: duration == null ? null : '天',
        ),
        _DataRow(label: '记录次数', value: '${cycles.length}', unit: '次'),
      ],
    );
  }
}

class _InlineCycleEditor extends StatelessWidget {
  const _InlineCycleEditor({
    required this.start,
    required this.end,
    required this.flow,
    required this.saving,
    required this.onStartTap,
    required this.onEndTap,
    required this.onFlowChanged,
    required this.onSave,
  });

  final DateTime start;
  final DateTime? end;
  final String flow;
  final bool saving;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  final ValueChanged<String> onFlowChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: pomiLine),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CycleDateField(
                  label: '开始日期',
                  value: _formatCycleDate(start),
                  onTap: onStartTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CycleDateField(
                  label: '结束日期',
                  value: end == null ? '进行中' : _formatCycleDate(end!),
                  onTap: onEndTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'light', label: Text('少')),
              ButtonSegment(value: 'medium', label: Text('中')),
              ButtonSegment(value: 'heavy', label: Text('多')),
            ],
            selected: {flow},
            onSelectionChanged: (values) => onFlowChanged(values.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving ? null : onSave,
            child:
                saving
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('保存经期记录'),
          ),
        ],
      ),
    );
  }

  static String _formatCycleDate(DateTime value) =>
      '${value.month}月${value.day}日';
}

class _CycleDateField extends StatelessWidget {
  const _CycleDateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .26),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pomiPurple.withValues(alpha: .12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 3),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _WeightTrendCard extends StatelessWidget {
  const _WeightTrendCard({required this.weights, required this.onViewMore});

  final List<Map<String, dynamic>> weights;
  final VoidCallback onViewMore;

  @override
  Widget build(BuildContext context) {
    final ordered = [...weights]..sort(
      (a, b) =>
          a['record_date'].toString().compareTo(b['record_date'].toString()),
    );
    final visible =
        ordered.length > 8 ? ordered.sublist(ordered.length - 8) : ordered;
    final values =
        visible.map((item) => (item['weight_kg'] as num).toDouble()).toList();
    final spots = List.generate(
      values.length,
      (index) => FlSpot(index.toDouble(), values[index]),
    );
    final minimum = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maximum = values.isEmpty ? 0.0 : values.reduce(math.max);
    final span = math.max(maximum - minimum, 1);
    final latest = ordered.isEmpty ? null : ordered.last['weight_kg'];

    return PomiGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: Icon(
                  Icons.monitor_weight_outlined,
                  size: 36,
                  color: pomiPurple,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '体重',
                  style: TextStyle(
                    color: pomiInk,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '今天',
                style: TextStyle(
                  color: pomiSecondaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 128,
            child:
                values.isEmpty
                    ? Center(
                      child: Text(
                        '暂无体重记录',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                    : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: math.max(1, spots.length - 1).toDouble(),
                        minY: minimum - span * .35,
                        maxY: maximum + span * .35,
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: .35,
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFD868C8), Color(0xFF7A42D8)],
                            ),
                            barWidth: 6,
                            isStrokeCapRound: true,
                            isStrokeJoinRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: false),
                          ),
                        ],
                      ),
                    ),
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: latest == null ? '—' : _formatWeight(latest),
                        style: const TextStyle(
                          color: pomiInk,
                          fontSize: 64,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(
                        text: ' kg',
                        style: TextStyle(
                          color: pomiSecondaryText,
                          fontSize: 24,
                          height: 1,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '查看体重历史',
                onPressed: onViewMore,
                color: pomiInk,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 24),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatWeight(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null) return '—';
  return number == number.roundToDouble()
      ? number.toStringAsFixed(0)
      : number.toStringAsFixed(1);
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: pomiMuted))),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: pomiInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(color: pomiSecondaryText),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
