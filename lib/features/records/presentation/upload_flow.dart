import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';

Future<void> showUploadFlow(BuildContext context) async {
  final type = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _UploadOptionsSheet(),
  );
  if (type == null || !context.mounted) return;

  final recognized = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _OcrProgressSheet(type: type),
  );
  if (recognized != true || !context.mounted) return;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _OcrDraftSheet(),
  );
  if (confirmed != true || !context.mounted) return;

  final reconciled = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ReconciliationSheet(),
  );
  if (reconciled == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('材料已确认，用药清单已更新')));
  }
}

class _UploadOptionsSheet extends StatelessWidget {
  const _UploadOptionsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('上传就诊记录', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '支持四类材料，上传后生成文件哈希并进入待确认草稿',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _UploadOption(
              key: const Key('upload-camera-option'),
              icon: Icons.photo_camera_outlined,
              title: '拍照 OCR',
              subtitle: '化验单 · 检查报告 · 病历 · 处方',
              onTap: () => Navigator.pop(context, '拍照材料'),
            ),
            _UploadOption(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF 上传',
              subtitle: '医院电子病历 · 影像文字报告',
              onTap: () => Navigator.pop(context, 'PDF 文件'),
            ),
            _UploadOption(
              icon: Icons.edit_note_rounded,
              title: '手动录入',
              subtitle: '补充体格数据或就诊记录',
              onTap: () => Navigator.pop(context, '手动记录'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _UploadOption extends StatelessWidget {
  const _UploadOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: PomiColors.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: PomiColors.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _OcrProgressSheet extends StatelessWidget {
  const _OcrProgressSheet({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: PomiColors.heroGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.document_scanner_outlined,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text('识别完成', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 5),
            Text(
              '$type · 模拟医院 B',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            const _ProgressRow(label: '文件版本与 SHA-256 已生成', complete: true),
            const _ProgressRow(label: 'Qwen3-VL 文字识别', complete: true),
            const _ProgressRow(label: '词库匹配与结构化提取', complete: true),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('ocr-review-button'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('查看待确认草稿'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.complete});

  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            complete ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: complete ? PomiColors.success : PomiColors.primary,
            size: 19,
          ),
          const SizedBox(width: 9),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _OcrDraftSheet extends StatefulWidget {
  const _OcrDraftSheet();

  @override
  State<_OcrDraftSheet> createState() => _OcrDraftSheetState();
}

class _OcrDraftSheetState extends State<_OcrDraftSheet> {
  bool _corrected = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
                '待确认草稿 · 化验单',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'OCR 结果经用户确认后才进入趋势和报告',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              const PomiSectionCard(
                color: PomiColors.primaryPale,
                child: Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      color: PomiColors.primary,
                      size: 32,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '检测单 6 · 模拟医院 B',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '采样 2026-08-25 · 文件 V1 · 哈希已生成',
                            style: TextStyle(
                              fontSize: 10,
                              color: PomiColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _DraftField(
                name: '空腹血糖',
                value: '5.6 mmol/L',
                reference: '3.9–6.1',
                confidence: '98%',
              ),
              const _DraftField(
                name: 'HbA1c',
                value: '5.5 %',
                reference: '4.0–6.0',
                confidence: '96%',
              ),
              _DraftField(
                name: '总睾酮',
                value: _corrected ? '0.9 ng/mL ↑' : '0.6 ng/mL',
                reference: '0.2–0.8',
                confidence: _corrected ? '已修正' : '64%',
                warning: true,
                onEdit: () => setState(() => _corrected = true),
              ),
              const _DraftField(
                name: '甘油三酯',
                value: '1.4 mmol/L',
                reference: '0.45–1.70',
                confidence: '88%',
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: PomiColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '低置信度字段已高亮，请对照原始材料重点核对。',
                  style: TextStyle(color: Color(0xFFC05B2E), fontSize: 11),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('confirm-ocr-button'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('全部确认，进入资料库'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftField extends StatelessWidget {
  const _DraftField({
    required this.name,
    required this.value,
    required this.reference,
    required this.confidence,
    this.warning = false,
    this.onEdit,
  });

  final String name;
  final String value;
  final String reference;
  final String confidence;
  final bool warning;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning
            ? PomiColors.glowYellow.withValues(alpha: 0.18)
            : PomiColors.surfaceMuted,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: warning ? const Color(0x66EFAA17) : const Color(0x106A4C93),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '参考 $reference',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                confidence,
                style: TextStyle(
                  fontSize: 10,
                  color: warning ? const Color(0xFFB8860B) : PomiColors.success,
                ),
              ),
            ],
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReconciliationSheet extends StatefulWidget {
  const _ReconciliationSheet();

  @override
  State<_ReconciliationSheet> createState() => _ReconciliationSheetState();
}

class _ReconciliationSheetState extends State<_ReconciliationSheet> {
  final Map<String, String> _choices = {
    '二甲双胍': '调整剂量',
    '维生素 D3': '继续使用',
    '肌醇': '新增用药',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('用药对账', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '新旧用药必须逐项确认，系统不会自动停药',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _ReconcileItem(
                name: '二甲双胍',
                oldValue: '500 mg · 每日 1 次',
                newValue: '850 mg · 每日 1 次',
                choices: const ['调整剂量', '继续原剂量', '无法判断'],
                selected: _choices['二甲双胍']!,
                onChanged: (value) => setState(() => _choices['二甲双胍'] = value),
              ),
              _ReconcileItem(
                name: '维生素 D3',
                oldValue: '1000 IU · 每日',
                newValue: '本次医嘱未列出',
                choices: const ['继续使用', '暂停使用', '无法判断'],
                selected: _choices['维生素 D3']!,
                onChanged: (value) =>
                    setState(() => _choices['维生素 D3'] = value),
              ),
              _ReconcileItem(
                name: '肌醇',
                oldValue: '旧清单无此药',
                newValue: '2 g · 每日 1 次',
                choices: const ['新增用药', '暂不导入', '无法判断'],
                selected: _choices['肌醇']!,
                onChanged: (value) => setState(() => _choices['肌醇'] = value),
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('confirm-reconciliation-button'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认并更新用药清单'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReconcileItem extends StatelessWidget {
  const _ReconcileItem({
    required this.name,
    required this.oldValue,
    required this.newValue,
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  final String name;
  final String oldValue;
  final String newValue;
  final List<String> choices;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PomiSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('旧：$oldValue', style: Theme.of(context).textTheme.bodySmall),
            Text(
              '新：$newValue',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final choice in choices)
                  ChoiceChip(
                    label: Text(choice),
                    selected: choice == selected,
                    onSelected: (_) => onChanged(choice),
                    selectedColor: PomiColors.primary,
                    labelStyle: TextStyle(
                      color: choice == selected
                          ? Colors.white
                          : PomiColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
