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

  /// 正在编辑的已有经期记录；为空表示新建。
  Map<String, dynamic>? _editingCycle;

  /// 最近一次 build 拿到的经期列表，供保存时做本地校验。
  List<Map<String, dynamic>> _cycles = const [];

  /// 把后端的 flow_level（可能是 unknown / null / 其它）收敛到分段按钮支持的值。
  static String _normalizeFlow(Object? value) {
    final flow = value?.toString();
    return (flow == 'light' || flow == 'medium' || flow == 'heavy')
        ? flow!
        : 'medium';
  }

  /// 找出包含 [day] 的已有经期记录（用于点日历时编辑而不是重复新建）。
  Map<String, dynamic>? _cycleContaining(
    DateTime day,
    List<Map<String, dynamic>> cycles,
  ) {
    final target = DateUtils.dateOnly(day);
    for (final cycle in cycles) {
      final start = DateTime.tryParse(cycle['start_date']?.toString() ?? '');
      if (start == null) continue;
      // 无结束日期 = 进行中，后端按「无限延伸」处理，这里也一样：start 及之后都算。
      final end = DateTime.tryParse(cycle['end_date']?.toString() ?? '');
      final inRange =
          !target.isBefore(DateUtils.dateOnly(start)) &&
          (end == null || !target.isAfter(DateUtils.dateOnly(end)));
      if (inRange) return cycle;
    }
    return null;
  }

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
          _cycles = cycles;
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
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
              children: [
                _HorizontalCycleCalendar(
                  selectedDay: _focusedDay,
                  cycles: cycles,
                  weights: weights,
                  onSelected: (day) {
                    final selected = DateUtils.dateOnly(day);
                    final today = DateUtils.dateOnly(DateTime.now());
                    if (selected.isAfter(today)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('只能记录今天及之前的经期')),
                      );
                      return;
                    }
                    final existing = _cycleContaining(selected, cycles);
                    setState(() {
                      _focusedDay = selected;
                      _cycleEditorExpanded = true;
                      if (existing != null) {
                        // 点到已有经期内的某天 → 打开这条记录编辑。
                        _editingCycle = existing;
                        _cycleStart =
                            DateTime.tryParse(
                              existing['start_date']?.toString() ?? '',
                            ) ??
                            selected;
                        _cycleEnd = DateTime.tryParse(
                          existing['end_date']?.toString() ?? '',
                        );
                        _cycleFlow = _normalizeFlow(existing['flow_level']);
                      } else {
                        _editingCycle = null;
                        _cycleStart = selected;
                        _cycleEnd = null;
                      }
                    });
                  },
                  onAdd:
                      () => _addCycle(context, ref, initialStart: _focusedDay),
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '周期统计',
                  icon: Icons.water_drop_outlined,
                  action: IconButton(
                    tooltip: _cycleEditorExpanded ? '收起经期记录' : '记录经期',
                    onPressed:
                        () => setState(() {
                          _cycleEditorExpanded = !_cycleEditorExpanded;
                          if (_cycleEditorExpanded) {
                            _editingCycle = null;
                            _cycleStart = _focusedDay;
                            _cycleEnd = null;
                          }
                        }),
                    icon: Icon(
                      _cycleEditorExpanded ? Icons.remove : Icons.add,
                      size: 18,
                    ),
                    color: pomiInk,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
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
                                  isEditing: _editingCycle != null,
                                  onStartTap: _selectInlineCycleStart,
                                  onEndTap: _selectInlineCycleEnd,
                                  onFlowChanged:
                                      (value) =>
                                          setState(() => _cycleFlow = value),
                                  onSave: _saveInlineCycle,
                                  onDelete:
                                      _editingCycle == null
                                          ? null
                                          : _deleteInlineCycle,
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
    // 新建一条早于「进行中」经期的历史记录时，必须有结束日期，否则两条都会
    // 被后端当成开放区间而判定重叠。
    if (_editingCycle == null && _cycleEnd == null) {
      final hasLater = _cycles.any((c) {
        final s = DateTime.tryParse(c['start_date']?.toString() ?? '');
        return s != null &&
            DateUtils.dateOnly(s).isAfter(DateUtils.dateOnly(_cycleStart));
      });
      if (hasLater) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('这段经期在更近的记录之前，请先选择结束日期')));
        return;
      }
    }
    setState(() => _savingCycle = true);
    try {
      final api = ref.read(apiClientProvider);
      final body = {
        'start_date': _cycleStart.toIso8601String().substring(0, 10),
        'end_date': _cycleEnd?.toIso8601String().substring(0, 10),
        'flow_level': _cycleFlow,
      };
      final editing = _editingCycle;
      if (editing != null) {
        await api.put(
          '/api/cycles/${editing['id']}',
          data: {
            ...body,
            if (editing['updated_at'] != null)
              'updated_at': editing['updated_at'],
          },
        );
      } else {
        await api.post('/api/cycles', data: body);
      }
      ref.invalidate(trackingProvider);
      if (mounted) {
        setState(() {
          _cycleEditorExpanded = false;
          _editingCycle = null;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _savingCycle = false);
    }
  }

  Future<void> _deleteInlineCycle() async {
    final editing = _editingCycle;
    if (editing == null || _savingCycle) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除这条经期记录？'),
            content: const Text('删除后不可恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _savingCycle = true);
    try {
      await ref.read(apiClientProvider).delete('/api/cycles/${editing['id']}');
      ref.invalidate(trackingProvider);
      if (mounted) {
        setState(() {
          _cycleEditorExpanded = false;
          _editingCycle = null;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
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
                          fontSize: 18,
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
                          try {
                            await ref
                                .read(apiClientProvider)
                                .post(
                                  '/api/cycles',
                                  data: {
                                    'start_date': start
                                        .toIso8601String()
                                        .substring(0, 10),
                                    'end_date': end
                                        ?.toIso8601String()
                                        .substring(0, 10),
                                    'flow_level': flow,
                                  },
                                );
                          } on ApiFailure catch (error) {
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            }
                            return;
                          }
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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => _AddWeightSheet(
            onSave: (date, value) async {
              await ref
                  .read(apiClientProvider)
                  .post(
                    '/api/weights',
                    data: {
                      'record_date': date.toIso8601String().substring(0, 10),
                      'weight_kg': value,
                    },
                  );
            },
          ),
    );
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
                              fontSize: 18,
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

class _AddWeightSheet extends StatefulWidget {
  const _AddWeightSheet({required this.onSave});

  final Future<void> Function(DateTime date, double value) onSave;

  @override
  State<_AddWeightSheet> createState() => _AddWeightSheetState();
}

class _AddWeightSheetState extends State<_AddWeightSheet> {
  final TextEditingController _controller = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDate: _date,
    );
    if (value != null && mounted) {
      setState(() => _date = DateUtils.dateOnly(value));
    }
  }

  Future<void> _save() async {
    final value = double.tryParse(_controller.text);
    if (value == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效体重')));
      return;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    if (_date.isAfter(today)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('只能记录今天及之前的体重')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(_date, value);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '记录体重',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('日期'),
            trailing: Text(
              _date.toIso8601String().substring(0, 10),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onTap: _saving ? null : _selectDate,
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '体重',
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child:
                _saving
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('保存'),
          ),
        ],
      ),
    ),
  );
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
  final ScrollController _controller = ScrollController();

  // 每个日期格宽 48 + 间隔 7。
  static const double _itemExtent = 55;
  DateTime? _centeredOn;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 把选中日滚到可视区中间（首帧 + 选中日变化时各做一次，不干扰手动滑动）。
  void _centerSelected(DateTime start, DateTime selected) {
    if (_centeredOn == selected || !_controller.hasClients) return;
    final index = selected.difference(start).inDays;
    if (index < 0) return;
    final viewport = _controller.position.viewportDimension;
    final target = (index * _itemExtent + _itemExtent / 2 - viewport / 2).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _centeredOn = selected;
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final selected = DateUtils.dateOnly(widget.selectedDay);
    final today = DateUtils.dateOnly(DateTime.now());
    final selectedIsPeriod = _isPeriodDay(selected);
    final start = today.subtract(const Duration(days: 14));
    final dates = List.generate(
      29,
      (index) => start.add(Duration(days: index)),
    );
    final weekday = const ['一', '二', '三', '四', '五', '六', '日'];
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerSelected(start, selected),
    );

    return PomiGlassCard(
      borderRadius: 24,
      backgroundOpacity: .28,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(
                    '${selected.month}月${selected.day}日 星期${weekday[selected.weekday - 1]}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: pomiInk,
                      fontSize: 18,
                      height: 26 / 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (selectedIsPeriod) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: pomiCoral,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          '经期中',
                          style: TextStyle(
                            color: pomiCoral,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
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
    final today = DateUtils.dateOnly(DateTime.now());
    return widget.cycles.any((cycle) {
      final start = DateTime.tryParse(cycle['start_date'].toString());
      if (start == null) return false;
      // 无结束日期（进行中）：标记到今天为止。
      final end =
          DateTime.tryParse(cycle['end_date']?.toString() ?? '') ?? today;
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
              height: 72,
              decoration: BoxDecoration(
                color:
                    selected
                        ? pomiPurple.withValues(alpha: .13)
                        : const Color(0xFFF1EFF5),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color:
                      selected
                          ? pomiPurple.withValues(alpha: .35)
                          : Colors.transparent,
                  width: 1.5,
                ),
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
                        fontSize: 13,
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
    required this.icon,
    required this.child,
    required this.action,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget action;
  @override
  Widget build(BuildContext context) => PomiGlassCard(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Icon(icon, size: 15, color: pomiPurple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                action,
              ],
            ),
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
    this.isEditing = false,
    this.onDelete,
  });

  final DateTime start;
  final DateTime? end;
  final String flow;
  final bool saving;
  final bool isEditing;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;
  final ValueChanged<String> onFlowChanged;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

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
                    : Text(isEditing ? '更新经期记录' : '保存经期记录'),
          ),
          if (isEditing && onDelete != null) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: saving ? null : onDelete,
              style: TextButton.styleFrom(foregroundColor: pomiCoral),
              child: const Text('删除这条记录'),
            ),
          ],
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 44,
            child: Row(
              children: [
                Icon(
                  Icons.monitor_weight_outlined,
                  size: 15,
                  color: pomiPurple,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '体重',
                    style: TextStyle(
                      color: pomiInk,
                      fontSize: 15,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '今天',
                  style: TextStyle(
                    color: pomiSecondaryText,
                    fontSize: 12,
                    height: 15 / 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
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
          const SizedBox(height: 12),
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
                          fontSize: 36,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(
                        text: ' kg',
                        style: TextStyle(
                          color: pomiSecondaryText,
                          fontSize: 14,
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
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: pomiMuted,
              fontSize: 12,
              height: 15 / 12,
            ),
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: pomiInk,
                  fontSize: 12,
                  height: 15 / 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    color: pomiSecondaryText,
                    fontSize: 12,
                    height: 15 / 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
