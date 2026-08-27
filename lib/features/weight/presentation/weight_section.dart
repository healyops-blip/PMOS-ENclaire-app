import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/pomi_line_chart.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/weight/application/weight_controller.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_input_validator.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_record.dart';

class WeightSection extends StatefulWidget {
  const WeightSection({required this.controller, this.now, super.key});

  final WeightController controller;
  final DateTime Function()? now;

  @override
  State<WeightSection> createState() => _WeightSectionState();
}

class _WeightSectionState extends State<WeightSection> {
  late final DateTime _today;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _today = _dateOnly((widget.now ?? DateTime.now)());
    _selectedDate = _today;
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(WeightSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  WeightRecord? _recordFor(DateTime day) {
    final target = _dateOnly(day);
    for (final record in widget.controller.records) {
      if (_dateOnly(record.recordDate) == target) return record;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: _today,
      helpText: '选择体重记录日期',
    );
    if (value != null) setState(() => _selectedDate = _dateOnly(value));
  }

  Future<void> _recordWeight() async {
    final existing = _recordFor(_selectedDate);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WeightEntryDialog(
        recordDate: _selectedDate,
        initialWeight: existing?.weightKg,
        onSave: (weightKg) async {
          final success = await widget.controller.save(
            recordDate: _selectedDate,
            weightKg: weightKg,
          );
          return success
              ? null
              : widget.controller.errorMessage ?? '保存失败，请稍后重试';
        },
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('体重已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.controller.records;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const PomiSectionTitle(title: '体重记录'),
        const SizedBox(height: 8),
        PomiSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_selectedDate.year} 年 ${_selectedDate.month} 月',
                key: const Key('weight-selected-month'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('weight-date-button'),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('record-weight-button'),
                      onPressed: widget.controller.isLoading
                          ? null
                          : _recordWeight,
                      icon: const Icon(Icons.monitor_weight_outlined),
                      label: Text(
                        _recordFor(_selectedDate) == null ? '记录体重' : '修改体重',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const PomiSectionTitle(title: '体重趋势'),
        const SizedBox(height: 8),
        _WeightTrendCard(
          records: records,
          loading: widget.controller.isLoading,
          errorMessage: widget.controller.errorMessage,
          onRetry: widget.controller.load,
        ),
      ],
    );
  }
}

class _WeightEntryDialog extends StatefulWidget {
  const _WeightEntryDialog({
    required this.recordDate,
    required this.onSave,
    this.initialWeight,
  });

  final DateTime recordDate;
  final double? initialWeight;
  final Future<String?> Function(double weightKg) onSave;

  @override
  State<_WeightEntryDialog> createState() => _WeightEntryDialogState();
}

class _WeightEntryDialogState extends State<_WeightEntryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialWeight?.toStringAsFixed(1) ?? '',
  );
  String? _validationMessage;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = validateWeightInput(_controller.text);
    if (message != null) {
      setState(() => _validationMessage = message);
      return;
    }
    setState(() {
      _saving = true;
      _validationMessage = null;
    });
    final saveError = await widget.onSave(
      double.parse(_controller.text.trim()),
    );
    if (!mounted) return;
    if (saveError == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _saving = false;
      _validationMessage = saveError;
    });
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('save-weight-button'),
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? '保存中…' : '保存'),
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
          if (errorMessage != null) ...[
            Row(
              key: const Key('weight-stale-warning'),
              children: [
                const Icon(Icons.sync_problem_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('当前显示上次同步的数据：$errorMessage')),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
            const SizedBox(height: 8),
          ],
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
