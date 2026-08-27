import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';
import 'package:pmos_enclaire/features/medications/data/medication_repository.dart';

class MedicationPage extends StatefulWidget {
  const MedicationPage({
    required this.initialMedications,
    this.repository,
    super.key,
  });

  final List<Medication> initialMedications;
  final MedicationRepository? repository;

  @override
  State<MedicationPage> createState() => _MedicationPageState();
}

class _MedicationPageState extends State<MedicationPage> {
  late final MedicationRepository _repository =
      widget.repository ?? DemoMedicationRepository(widget.initialMedications);
  late List<Medication> _medications = [...widget.initialMedications];
  List<MedicationEvent> _events = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final records = await _repository.listMedications();
      if (mounted) setState(() => _medications = records);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _addMedication() async {
    final draft = await showModalBottomSheet<_MedicationDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _MedicationForm(),
    );
    if (draft == null) return;
    await _runMutation(() async {
      final created = await _repository.createMedication(
        name: draft.name,
        sourceCategory: draft.sourceCategory,
        startDate: DateTime.now(),
        dosageValue: draft.dosageValue,
        dosageUnit: draft.dosageUnit,
        frequency: draft.frequency,
      );
      _medications = [..._medications, created];
    });
  }

  Future<void> _openActions(int index) async {
    final medication = _medications[index];
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('查看事件时间线'),
              onTap: () => Navigator.pop(context, 'history'),
            ),
            if (medication.lifecycle != MedicationLifecycle.stopped)
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('调整剂量或频率'),
                onTap: () => Navigator.pop(context, 'adjusted'),
              ),
            if (medication.lifecycle == MedicationLifecycle.active)
              ListTile(
                leading: const Icon(Icons.pause_rounded),
                title: const Text('暂停用药'),
                onTap: () => Navigator.pop(context, 'paused'),
              ),
            if (medication.lifecycle == MedicationLifecycle.paused)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('恢复用药'),
                onTap: () => Navigator.pop(context, 'resumed'),
              ),
            if (medication.lifecycle != MedicationLifecycle.stopped)
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('停用药物'),
                onTap: () => Navigator.pop(context, 'stopped'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'history') {
      await _loadHistory(medication);
    } else if (action == 'adjusted') {
      await _adjust(index, medication);
    } else {
      await _changeLifecycle(index, medication, action);
    }
  }

  Future<void> _adjust(int index, Medication medication) async {
    final draft = await showModalBottomSheet<_MedicationDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MedicationForm(medication: medication),
    );
    if (draft == null) return;
    await _runMutation(() async {
      final replacement = await _repository.updateMedication(
        medication,
        eventType: 'adjusted',
        dosageValue: draft.dosageValue,
        dosageUnit: draft.dosageUnit,
        frequency: draft.frequency,
      );
      _medications = [..._medications]..[index] = replacement;
    });
  }

  Future<void> _changeLifecycle(
    int index,
    Medication medication,
    String eventType,
  ) async {
    await _runMutation(() async {
      final updated = await _repository.updateMedication(
        medication,
        eventType: eventType,
        stopSource: eventType == 'stopped' ? 'patient_self' : null,
      );
      _medications = [..._medications]..[index] = updated;
    });
  }

  Future<void> _loadHistory(Medication medication) async {
    try {
      final events = await _repository.listEvents(medication.id);
      if (mounted) setState(() => _events = events);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _runMutation(Future<void> Function() mutation) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await mutation();
      if (mounted) setState(() {});
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作失败：$error')));
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MapEntry<int, Medication>>>{};
    for (var index = 0; index < _medications.length; index++) {
      final medication = _medications[index];
      groups
          .putIfAbsent(medication.group, () => [])
          .add(MapEntry(index, medication));
    }
    return Scaffold(
      key: const Key('medication-page'),
      appBar: AppBar(
        title: const Text('用药管理'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      backgroundColor: PomiColors.surfaceMuted,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          PomiSectionTitle(
            title: '当前用药',
            action: '+ 手动添加',
            onAction: _addMedication,
          ),
          const SizedBox(height: 8),
          for (final group in groups.entries) ...[
            PomiSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PomiPill(label: group.key, color: PomiColors.primary),
                  const SizedBox(height: 8),
                  for (var row = 0; row < group.value.length; row++)
                    _MedicationRow(
                      medication: group.value[row].value,
                      last: row == group.value.length - 1,
                      onAction: () => _openActions(group.value[row].key),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          const PomiSectionTitle(title: '事件时间线'),
          const SizedBox(height: 8),
          PomiSectionCard(
            child: _events.isEmpty
                ? const Text('从药物菜单打开时间线；历史事件只读且不会被覆盖。')
                : Column(
                    children: [
                      for (var index = 0; index < _events.length; index++)
                        _HistoryEvent(
                          event: _events[index],
                          last: index == _events.length - 1,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MedicationDraft {
  const _MedicationDraft({
    required this.name,
    required this.sourceCategory,
    this.dosageValue,
    this.dosageUnit,
    this.frequency,
  });

  final String name;
  final String sourceCategory;
  final num? dosageValue;
  final String? dosageUnit;
  final String? frequency;
}

class _MedicationForm extends StatefulWidget {
  const _MedicationForm({this.medication});

  final Medication? medication;

  @override
  State<_MedicationForm> createState() => _MedicationFormState();
}

class _MedicationFormState extends State<_MedicationForm> {
  late final _name = TextEditingController(text: widget.medication?.name);
  late final _dosage = TextEditingController(
    text: widget.medication?.dosageValue?.toString(),
  );
  late final _unit = TextEditingController(text: widget.medication?.dosageUnit);
  late final _frequency = TextEditingController(
    text: widget.medication?.frequency,
  );
  late String _source = widget.medication?.sourceCategory ?? 'prescribed';

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _unit.dispose();
    _frequency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.medication != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? '调整用药' : '添加用药',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('medication-name-field'),
              controller: _name,
              enabled: !editing,
              decoration: const InputDecoration(labelText: '药品名称'),
            ),
            const SizedBox(height: 10),
            if (!editing)
              DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(labelText: '用药来源'),
                items: const [
                  DropdownMenuItem(value: 'prescribed', child: Text('按医嘱用药')),
                  DropdownMenuItem(value: 'supplement', child: Text('自行补充')),
                  DropdownMenuItem(
                    value: 'other_long_term',
                    child: Text('其他长期用药'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _source = value ?? _source),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dosage,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '剂量'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: '单位'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _frequency,
              decoration: const InputDecoration(labelText: '频率'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('save-medication-button'),
                onPressed: () {
                  if (_name.text.trim().isEmpty) return;
                  Navigator.pop(
                    context,
                    _MedicationDraft(
                      name: _name.text.trim(),
                      sourceCategory: _source,
                      dosageValue: num.tryParse(_dosage.text.trim()),
                      dosageUnit: _unit.text.trim().isEmpty
                          ? null
                          : _unit.text.trim(),
                      frequency: _frequency.text.trim().isEmpty
                          ? null
                          : _frequency.text.trim(),
                    ),
                  );
                },
                child: Text(editing ? '保存为新版本' : '添加到用药清单'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({
    required this.medication,
    required this.last,
    required this.onAction,
  });

  final Medication medication;
  final bool last;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final lifecycle = switch (medication.lifecycle) {
      MedicationLifecycle.active => '使用中',
      MedicationLifecycle.paused => '已暂停',
      MedicationLifecycle.stopped => '已停用',
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medication.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${medication.dose} · $lifecycle',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAction,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
    );
  }
}

class _HistoryEvent extends StatelessWidget {
  const _HistoryEvent({required this.event, required this.last});

  final MedicationEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final labels = {
      'created': '开始用药',
      'adjusted': '调整用药（新版本）',
      'paused': '暂停用药',
      'resumed': '恢复用药',
      'stopped': '停用药物',
    };
    final date =
        '${event.date.year.toString().padLeft(4, '0')}-'
        '${event.date.month.toString().padLeft(2, '0')}-'
        '${event.date.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(date, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labels[event.type] ?? event.type,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (event.note != null)
                  Text(
                    event.note!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
