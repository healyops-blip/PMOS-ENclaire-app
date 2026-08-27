import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/dashboard/domain/medication.dart';

class MedicationPage extends StatefulWidget {
  const MedicationPage({required this.initialMedications, super.key});

  final List<Medication> initialMedications;

  @override
  State<MedicationPage> createState() => _MedicationPageState();
}

class _MedicationPageState extends State<MedicationPage> {
  late final List<Medication> _medications = [...widget.initialMedications];
  final Map<String, bool> _reminders = {
    '二甲双胍': true,
    '优思明': true,
    '维生素 D3': false,
  };

  Future<void> _addMedication() async {
    final nameController = TextEditingController();
    final doseController = TextEditingController();
    final result = await showModalBottomSheet<Medication>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('添加用药', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '药品名称'),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: doseController,
              decoration: const InputDecoration(labelText: '剂量与频次'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  Medication(
                    name: nameController.text.trim(),
                    dose: doseController.text.trim().isEmpty
                        ? '剂量待确认'
                        : doseController.text.trim(),
                    group: '其他药物',
                    status: MedicationStatus.unrecorded,
                    takenDays: 0,
                    missedDays: 0,
                  ),
                );
              },
              child: const Text('添加到用药清单'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    doseController.dispose();
    if (result == null) return;
    setState(() {
      _medications.add(result);
      _reminders[result.name] = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Medication>>{};
    for (final medication in _medications) {
      groups.putIfAbsent(medication.group, () => []).add(medication);
    }
    return Scaffold(
      key: const Key('medication-page'),
      appBar: AppBar(
        title: const Text('用药管理'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: DemoBadge(label: '模拟数据')),
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
          for (final entry in groups.entries) ...[
            PomiSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PomiPill(label: entry.key, color: PomiColors.primary),
                  const SizedBox(height: 8),
                  for (var index = 0; index < entry.value.length; index++)
                    _MedicationManageRow(
                      medication: entry.value[index],
                      last: index == entry.value.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          const PomiSectionTitle(title: '用药提醒'),
          const SizedBox(height: 8),
          PomiSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < _medications.length; index++)
                  SwitchListTile(
                    title: Text(
                      _medications[index].name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(index.isEven ? '每日 18:30' : '每日 08:00'),
                    value: _reminders[_medications[index].name] ?? false,
                    onChanged: (value) => setState(
                      () => _reminders[_medications[index].name] = value,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const PomiSectionTitle(title: '历史事件'),
          const SizedBox(height: 8),
          const PomiSectionCard(
            child: Column(
              children: [
                _HistoryEvent(
                  date: '2026-08-25',
                  title: '二甲双胍调整剂量',
                  detail: '500 mg → 850 mg · 用户确认',
                ),
                _HistoryEvent(
                  date: '2026-05-18',
                  title: '优思明开始使用',
                  detail: '1 片 · 每晚',
                ),
                _HistoryEvent(
                  date: '2026-02-09',
                  title: '叶酸停用',
                  detail: '医生建议 · 历史记录保留',
                  last: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationManageRow extends StatelessWidget {
  const _MedicationManageRow({required this.medication, required this.last});

  final Medication medication;
  final bool last;

  @override
  Widget build(BuildContext context) {
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
                  medication.dose,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
    );
  }
}

class _HistoryEvent extends StatelessWidget {
  const _HistoryEvent({
    required this.date,
    required this.title,
    required this.detail,
    this.last = false,
  });

  final String date;
  final String title;
  final String detail;
  final bool last;

  @override
  Widget build(BuildContext context) {
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
            width: 76,
            child: Text(date, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
