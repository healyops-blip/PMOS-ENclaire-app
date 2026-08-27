import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/pomi_line_chart.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/cycle/data/cycle_repository.dart';
import 'package:pmos_enclaire/features/cycle/domain/menstrual_cycle.dart';
import 'package:table_calendar/table_calendar.dart';

class CyclePage extends StatefulWidget {
  const CyclePage({this.repository, super.key});

  final CycleRepository? repository;

  @override
  State<CyclePage> createState() => _CyclePageState();
}

class _CyclePageState extends State<CyclePage> {
  late CycleRepository _repository;
  List<MenstrualCycle>? _cycles;
  Object? _loadError;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DemoCycleRepository();
    _load();
  }

  @override
  void didUpdateWidget(CyclePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository &&
        widget.repository != null) {
      _repository = widget.repository!;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _cycles = null;
      _loadError = null;
    });
    try {
      final cycles = await _repository.list();
      if (!mounted) return;
      setState(() => _cycles = cycles);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _openEditor([MenstrualCycle? cycle]) async {
    final draft = await showDialog<CycleDraft>(
      context: context,
      builder: (_) => _CycleEditorDialog(initial: cycle),
    );
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (cycle == null) {
        await _repository.create(draft);
      } else {
        await _repository.update(cycle.id, draft);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cycle == null ? '经期记录已添加' : '经期记录已更新')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(MenstrualCycle cycle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条经期记录？'),
        content: const Text('删除后不会出现在历史记录中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-delete-cycle'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repository.delete(cycle.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('经期记录已删除')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('cycle-page'),
      color: PomiColors.primaryPale,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PomiPageHeader(
              title: '经期记录',
              subtitle: '记录真实发生的经期，回顾周期变化',
              trailing: FilledButton.icon(
                key: const Key('add-cycle-button'),
                onPressed: _saving ? null : () => _openEditor(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新增'),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 126),
            sliver: SliverToBoxAdapter(child: _content()),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loadError != null) {
      return PomiSectionCard(
        key: const Key('cycle-error-state'),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: PomiColors.primary,
              size: 42,
            ),
            const SizedBox(height: 10),
            const Text('经期记录加载失败'),
            const SizedBox(height: 4),
            Text(
              _loadError.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('retry-cycle-button'),
              onPressed: _load,
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    final cycles = _cycles;
    if (cycles == null) {
      return const Padding(
        key: Key('cycle-loading-state'),
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (cycles.isEmpty) {
      return PomiSectionCard(
        key: const Key('cycle-empty-state'),
        child: Column(
          children: [
            const PomiEmptyState(
              icon: Icons.calendar_month_outlined,
              title: '还没有经期记录',
              description: '从最近一次经期开始日期记起，结束日期可以稍后补录。',
            ),
            FilledButton.icon(
              key: const Key('empty-add-cycle-button'),
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加第一条记录'),
            ),
          ],
        ),
      );
    }
    final lengths = cycles
        .where((cycle) => cycle.cycleLengthDays != null)
        .map((cycle) => cycle.cycleLengthDays!)
        .toList()
        .reversed
        .toList();
    final ongoing = cycles.where((cycle) => cycle.endDate == null).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _calendar(cycles),
        const SizedBox(height: 16),
        if (ongoing != null) ...[
          PomiSectionCard(
            key: const Key('ongoing-cycle-card'),
            color: PomiColors.primary.withValues(alpha: 0.08),
            child: Row(
              children: [
                const Icon(Icons.water_drop_rounded, color: PomiColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '本次经期开始于 ${_displayDate(ongoing.startDate)}，结束日期待补录',
                  ),
                ),
                TextButton(
                  key: const Key('complete-cycle-button'),
                  onPressed: () => _openEditor(ongoing),
                  child: const Text('补录'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const PomiSectionTitle(title: '周期长度变化'),
        const SizedBox(height: 8),
        if (lengths.isEmpty)
          const PomiSectionCard(
            key: Key('cycle-trend-empty'),
            child: Text('至少记录两次开始日期后，才能查看周期长度变化。'),
          )
        else
          PomiSectionCard(
            key: const Key('cycle-trend-success'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最近 ${lengths.length} 次周期',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                PomiLineChart(
                  values: lengths.map((value) => value.toDouble()).toList(),
                  labels: [
                    for (var index = 0; index < lengths.length; index++)
                      '${index + 1}',
                  ],
                  color: PomiColors.primary,
                  height: 150,
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        const PomiSectionTitle(title: '历史记录'),
        const SizedBox(height: 8),
        for (final cycle in cycles) ...[
          _historyCard(cycle),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _calendar(List<MenstrualCycle> cycles) {
    bool isPeriodDay(DateTime day) =>
        cycles.any((cycle) => cycle.contains(day));
    return PomiSectionCard(
      key: const Key('cycle-calendar'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: TableCalendar<void>(
        firstDay: DateTime(2000),
        lastDay: DateTime.now(),
        focusedDay: _focusedDay.isAfter(DateTime.now())
            ? DateTime.now()
            : _focusedDay,
        selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
        onDaySelected: (selected, focused) {
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
        },
        onPageChanged: (focused) => _focusedDay = focused,
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: false,
          selectedDecoration: BoxDecoration(
            color: PomiColors.primary,
            shape: BoxShape.circle,
          ),
          todayTextStyle: TextStyle(color: PomiColors.primary),
          todayDecoration: BoxDecoration(shape: BoxShape.circle),
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, day, _) {
            if (!isPeriodDay(day)) return null;
            return Center(
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PomiColors.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${day.day}',
                  style: const TextStyle(color: PomiColors.primary),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _historyCard(MenstrualCycle cycle) {
    final endText = cycle.endDate == null
        ? '进行中'
        : _displayDate(cycle.endDate!);
    return PomiSectionCard(
      key: Key('cycle-record-${cycle.id}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PomiColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.water_drop_outlined,
              color: PomiColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_displayDate(cycle.startDate)} — $endText',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (cycle.durationDays != null)
                      '经期 ${cycle.durationDays} 天',
                    if (cycle.cycleLengthDays != null)
                      '周期 ${cycle.cycleLengthDays} 天',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('edit-cycle-${cycle.id}'),
            tooltip: '编辑',
            onPressed: _saving ? null : () => _openEditor(cycle),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: Key('delete-cycle-${cycle.id}'),
            tooltip: '删除',
            onPressed: _saving ? null : () => _delete(cycle),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  static String _displayDate(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';
}

class _CycleEditorDialog extends StatefulWidget {
  const _CycleEditorDialog({this.initial});

  final MenstrualCycle? initial;

  @override
  State<_CycleEditorDialog> createState() => _CycleEditorDialogState();
}

class _CycleEditorDialogState extends State<_CycleEditorDialog> {
  late DateTime _startDate = widget.initial?.startDate ?? DateTime.now();
  late DateTime? _endDate = widget.initial?.endDate;
  late String? _flowLevel = widget.initial?.flowLevel;
  late final TextEditingController _note = TextEditingController(
    text: widget.initial?.note,
  );
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择开始日期',
      cancelText: '取消选择',
      confirmText: '选择日期',
    );
    if (value != null) setState(() => _startDate = value);
  }

  Future<void> _pickEnd() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择结束日期',
      cancelText: '取消选择',
      confirmText: '选择日期',
    );
    if (value != null) setState(() => _endDate = value);
  }

  void _save() {
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      setState(() => _error = '开始日期不能晚于结束日期');
      return;
    }
    Navigator.pop(
      context,
      CycleDraft(
        startDate: _startDate,
        endDate: _endDate,
        flowLevel: _flowLevel,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        updatedAt: widget.initial?.updatedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('cycle-editor-dialog'),
      title: Text(widget.initial == null ? '新增经期记录' : '编辑经期记录'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: const Key('cycle-start-date-button'),
              onPressed: _pickStart,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('开始：${DateFormat('yyyy-MM-dd').format(_startDate)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('cycle-end-date-button'),
              onPressed: _pickEnd,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(
                _endDate == null
                    ? '结束：暂不填写'
                    : '结束：${DateFormat('yyyy-MM-dd').format(_endDate!)}',
              ),
            ),
            if (_endDate != null)
              TextButton(
                key: const Key('clear-cycle-end-date'),
                onPressed: () => setState(() => _endDate = null),
                child: const Text('设为尚未结束'),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              key: const Key('cycle-flow-field'),
              initialValue: _flowLevel,
              decoration: const InputDecoration(labelText: '经量（选填）'),
              items: const [
                DropdownMenuItem(value: null, child: Text('不记录')),
                DropdownMenuItem(value: 'light', child: Text('较少')),
                DropdownMenuItem(value: 'medium', child: Text('适中')),
                DropdownMenuItem(value: 'heavy', child: Text('较多')),
                DropdownMenuItem(value: 'unknown', child: Text('不确定')),
              ],
              onChanged: (value) => setState(() => _flowLevel = value),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cycle-note-field'),
              controller: _note,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注（选填）'),
            ),
            if (_error != null)
              Text(
                _error!,
                key: const Key('cycle-editor-error'),
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('save-cycle-button'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
