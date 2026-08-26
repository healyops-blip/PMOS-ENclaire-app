import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';

enum MedicalMaterialType { laboratory, prescription, imagingText, outpatient }

extension MedicalMaterialTypeUi on MedicalMaterialType {
  String get label => switch (this) {
    MedicalMaterialType.laboratory => '化验／检测',
    MedicalMaterialType.prescription => '医嘱／处方',
    MedicalMaterialType.imagingText => '影像文字报告',
    MedicalMaterialType.outpatient => '门诊病历／就诊记录',
  };

  String get shortLabel => switch (this) {
    MedicalMaterialType.laboratory => '化验单',
    MedicalMaterialType.prescription => '医嘱',
    MedicalMaterialType.imagingText => '影像文字',
    MedicalMaterialType.outpatient => '门诊病历',
  };

  IconData get icon => switch (this) {
    MedicalMaterialType.laboratory => Icons.science_outlined,
    MedicalMaterialType.prescription => Icons.medication_outlined,
    MedicalMaterialType.imagingText => Icons.monitor_heart_outlined,
    MedicalMaterialType.outpatient => Icons.description_outlined,
  };
}

enum _UploadSource { camera, gallery, pdf, demo }

Future<void> showUploadFlow(BuildContext context) async {
  final type = await showModalBottomSheet<MedicalMaterialType>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _MaterialTypeSheet(),
  );
  if (type == null || !context.mounted) return;

  final source = await showModalBottomSheet<_UploadSource>(
    context: context,
    showDragHandle: true,
    builder: (_) => _UploadSourceSheet(type: type),
  );
  if (source == null || !context.mounted) return;

  final consented = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('外部识别服务提示'),
      content: const Text('材料将发送至外部 Qwen3-VL 服务进行文字识别。当前仅使用模拟材料，请确认后继续。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('confirm-external-ocr'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('同意并继续'),
        ),
      ],
    ),
  );
  if (consented != true || !context.mounted) return;

  final fileName = await _pickMaterial(source);
  if (fileName == null || !context.mounted) return;

  final recognized = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _OcrProgressSheet(
      type: type,
      fileName: fileName,
      fallback: source == _UploadSource.demo,
    ),
  );
  if (recognized != true || !context.mounted) return;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OcrDraftSheet(type: type),
  );
  if (confirmed != true || !context.mounted) return;

  if (type == MedicalMaterialType.prescription) {
    final reconciled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReconciliationSheet(),
    );
    if (reconciled != true || !context.mounted) return;
  }
  if (!context.mounted) return;
  final message = type == MedicalMaterialType.prescription
      ? '材料已确认，用药清单已更新'
      : '${type.shortLabel}已确认并进入就诊资料库';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> _pickMaterial(_UploadSource source) async {
  if (source == _UploadSource.demo) return 'pomi_demo_material_v2.png';
  try {
    if (source == _UploadSource.pdf) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: false,
      );
      return result?.files.single.name;
    }
    final picker = ImagePicker();
    final result = await picker.pickImage(
      source: source == _UploadSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 92,
    );
    return result?.name;
  } on Exception {
    return null;
  }
}

class _MaterialTypeSheet extends StatelessWidget {
  const _MaterialTypeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择材料类型', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '先确定材料类型，再选择拍照、相册或单页 PDF',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final type in MedicalMaterialType.values)
              _UploadOption(
                key: Key('material-type-${type.name}'),
                icon: type.icon,
                title: type.label,
                subtitle: switch (type) {
                  MedicalMaterialType.laboratory => '项目、数值、单位与参考范围',
                  MedicalMaterialType.prescription => '药名、剂量、频率与疗程',
                  MedicalMaterialType.imagingText => '所见和结论原文，不分析影像本体',
                  MedicalMaterialType.outpatient => '医院、科室、主诉、诊断与处理意见',
                },
                onTap: () => Navigator.pop(context, type),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _UploadSourceSheet extends StatelessWidget {
  const _UploadSourceSheet({required this.type});

  final MedicalMaterialType type;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '上传${type.shortLabel}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'JPG、JPEG、PNG 或单页 PDF · 最大 20MB / 25MP',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            _UploadOption(
              key: const Key('upload-camera-option'),
              icon: Icons.photo_camera_outlined,
              title: '拍照',
              subtitle: '仅在点击后申请摄像头权限',
              onTap: () => Navigator.pop(context, _UploadSource.camera),
            ),
            _UploadOption(
              key: const Key('upload-gallery-option'),
              icon: Icons.photo_library_outlined,
              title: '从相册选择',
              subtitle: '拒绝相机权限后仍可使用',
              onTap: () => Navigator.pop(context, _UploadSource.gallery),
            ),
            _UploadOption(
              key: const Key('upload-pdf-option'),
              icon: Icons.picture_as_pdf_outlined,
              title: '选择单页 PDF',
              subtitle: '通过系统文件选择器读取',
              onTap: () => Navigator.pop(context, _UploadSource.pdf),
            ),
            _UploadOption(
              key: const Key('upload-demo-option'),
              icon: Icons.science_outlined,
              title: '使用预置模拟材料',
              subtitle: '仅用于路演，固定结果将持续标记为兜底',
              onTap: () => Navigator.pop(context, _UploadSource.demo),
            ),
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

class _OcrProgressSheet extends StatefulWidget {
  const _OcrProgressSheet({
    required this.type,
    required this.fileName,
    required this.fallback,
  });

  final MedicalMaterialType type;
  final String fileName;
  final bool fallback;

  @override
  State<_OcrProgressSheet> createState() => _OcrProgressSheetState();
}

class _OcrProgressSheetState extends State<_OcrProgressSheet> {
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _complete = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: SingleChildScrollView(
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
              Text(
                _complete ? '识别完成' : '识别处理中…',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                '${widget.type.shortLabel} · ${widget.fileName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              const _ProgressRow(label: '文件版本与 SHA-256 已生成', complete: true),
              _ProgressRow(label: 'Qwen3-VL 文字识别', complete: _complete),
              _ProgressRow(label: '词库匹配与结构化提取', complete: _complete),
              if (widget.fallback)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PomiColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '演示兜底：文件哈希已匹配预置材料，本次不是实时模型结果。',
                    style: TextStyle(color: Color(0xFFC05B2E), fontSize: 10),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton(
                key: const Key('ocr-review-button'),
                onPressed: _complete
                    ? () => Navigator.pop(context, true)
                    : null,
                child: const Text('查看待确认草稿'),
              ),
              const SizedBox(height: 6),
              TextButton(
                key: const Key('cancel-ocr-button'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消本次识别'),
              ),
            ],
          ),
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
  const _OcrDraftSheet({required this.type});

  final MedicalMaterialType type;

  @override
  State<_OcrDraftSheet> createState() => _OcrDraftSheetState();
}

class _OcrDraftSheetState extends State<_OcrDraftSheet> {
  bool _corrected = false;
  final Set<String> _confirmedItems = {};

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
                '待确认草稿 · ${widget.type.shortLabel}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'OCR 结果经用户确认后才进入趋势和报告',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              PomiSectionCard(
                color: PomiColors.primaryPale,
                child: Row(
                  children: [
                    Icon(widget.type.icon, color: PomiColors.primary, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.type.shortLabel} · 模拟医院 B',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Text(
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
              ..._draftFields(context),
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
                onPressed:
                    widget.type == MedicalMaterialType.prescription &&
                        _confirmedItems.length < 2
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(
                  widget.type == MedicalMaterialType.prescription
                      ? '逐项确认，进入用药对账'
                      : '确认并进入资料库',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _draftFields(BuildContext context) {
    return switch (widget.type) {
      MedicalMaterialType.laboratory => [
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
      ],
      MedicalMaterialType.prescription => [
        _DraftTextBlock(
          title: '盐酸二甲双胍缓释片',
          lines: const ['规格：0.5g / 片', '单次剂量：850mg', '频率：每日 1 次', '疗程：持续使用'],
          source: '原文：二甲双胍缓释片调整为 850mg qd',
          confirmed: _confirmedItems.contains('二甲双胍'),
          onConfirmed: (value) => setState(() {
            value
                ? _confirmedItems.add('二甲双胍')
                : _confirmedItems.remove('二甲双胍');
          }),
        ),
        _DraftTextBlock(
          title: '肌醇',
          lines: const ['规格：2g / 袋', '单次剂量：2g', '频率：每日 1 次', '疗程：3 个月'],
          source: '原文：加用肌醇 2g 每日一次，共三个月',
          confirmed: _confirmedItems.contains('肌醇'),
          onConfirmed: (value) => setState(() {
            value ? _confirmedItems.add('肌醇') : _confirmedItems.remove('肌醇');
          }),
        ),
      ],
      MedicalMaterialType.imagingText => const [
        _DraftTextBlock(
          title: '检查信息',
          lines: ['检查名称：盆腔超声', '部位：盆腔', '方式：经腹超声', '日期：2026-08-25'],
        ),
        _DraftTextBlock(
          title: '所见原文',
          lines: ['双侧卵巢内见多个小卵泡回声，排列于周边。'],
          warning: true,
        ),
        _DraftTextBlock(title: '结论原文', lines: ['双侧卵巢多囊样改变，请结合临床。']),
      ],
      MedicalMaterialType.outpatient => const [
        _DraftTextBlock(
          title: '就诊信息',
          lines: ['医院：模拟医院 B', '科室：生殖内分泌科', '日期：2026-08-26'],
        ),
        _DraftTextBlock(
          title: '主诉与诊断摘要',
          lines: ['主诉：月经周期不规律', '诊断摘要：PCOS 随访（原文摘录）'],
        ),
        _DraftTextBlock(
          title: '处理意见原文',
          lines: ['继续记录月经周期，按书面医嘱用药，三个月后复诊。'],
          warning: true,
        ),
      ],
    };
  }
}

class _DraftTextBlock extends StatelessWidget {
  const _DraftTextBlock({
    required this.title,
    required this.lines,
    this.source,
    this.warning = false,
    this.confirmed,
    this.onConfirmed,
  });

  final String title;
  final List<String> lines;
  final String? source;
  final bool warning;
  final bool? confirmed;
  final ValueChanged<bool>? onConfirmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: warning
            ? PomiColors.glowYellow.withValues(alpha: 0.15)
            : PomiColors.surfaceMuted,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: warning ? const Color(0x66EFAA17) : const Color(0x106A4C93),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(
                Icons.edit_outlined,
                size: 17,
                color: PomiColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                style: const TextStyle(fontSize: 11, height: 1.4),
              ),
            ),
          if (source != null) ...[
            const Divider(height: 16),
            Text(
              source!,
              style: const TextStyle(color: PomiColors.textMuted, fontSize: 10),
            ),
          ],
          if (confirmed != null && onConfirmed != null) ...[
            const Divider(height: 16),
            InkWell(
              key: Key('confirm-draft-$title'),
              onTap: () => onConfirmed!(!confirmed!),
              child: Row(
                children: [
                  Checkbox(
                    value: confirmed,
                    onChanged: (value) => onConfirmed!(value ?? false),
                  ),
                  const Text(
                    '我已逐项核对并确认',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
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
