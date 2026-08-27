import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/presentation/ocr_task_page.dart';

enum MedicalMaterialType { laboratory, prescription, imagingText, outpatient }

extension MedicalMaterialTypeUi on MedicalMaterialType {
  String get apiValue => switch (this) {
    MedicalMaterialType.laboratory => 'lab_report',
    MedicalMaterialType.prescription => 'medical_order',
    MedicalMaterialType.imagingText => 'imaging_text_report',
    MedicalMaterialType.outpatient => 'outpatient_record',
  };
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

enum _UploadSource { camera, gallery, file, demo }

Future<void> showUploadFlow(
  BuildContext context, {
  required DocumentRepository repository,
  required OcrRepository ocrRepository,
  VoidCallback? onUploaded,
}) async {
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

  SelectedDocumentFile? file;
  try {
    file = await _pickMaterial(source, type);
    if (file == null) return;
    if (source != _UploadSource.demo) await validateSelectedDocument(file);
  } on DocumentFailure catch (error) {
    if (context.mounted) _showMessage(context, error.message);
    return;
  } on Exception {
    if (context.mounted) {
      _showMessage(
        context,
        source == _UploadSource.camera
            ? '无法使用相机。你仍可从相册或文件中选择材料。'
            : '无法读取所选文件，请重新选择。',
      );
    }
    return;
  }
  if (!context.mounted) return;
  final previewAccepted = await showDialog<bool>(
    context: context,
    builder: (_) => _DocumentPreviewDialog(file: file!),
  );
  if (previewAccepted != true || !context.mounted) return;
  final consented = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('外部识别服务提示'),
      content: const Text(
        '下一步文字识别会将这份材料发送给外部识别服务。确认记录包含提示版本和时间；不同意时不会上传或创建材料。',
      ),
      actions: [
        TextButton(
          key: const Key('decline-external-ocr'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('不同意'),
        ),
        FilledButton(
          key: const Key('confirm-external-ocr'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('同意并上传'),
        ),
      ],
    ),
  );
  if (consented != true || !context.mounted) return;
  final uploaded = await showDialog<MedicalDocument>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _UploadProgressDialog(repository: repository, file: file!, type: type),
  );
  if (uploaded == null || !context.mounted) return;
  onUploaded?.call();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${type.shortLabel}已安全保存，可在材料列表查看'),
      action: SnackBarAction(
        label: '开始识别',
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => OcrTaskPage(
              repository: ocrRepository,
              document: uploaded,
              documentRepository: repository,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<SelectedDocumentFile?> _pickMaterial(
  _UploadSource source,
  MedicalMaterialType type,
) async {
  if (source == _UploadSource.demo) {
    final data = await rootBundle.load('assets/demo/${type.apiValue}.png');
    return SelectedDocumentFile(
      name: 'pomi-demo-${type.apiValue}.png',
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
  if (source == _UploadSource.file) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      allowMultiple: false,
      withData: true,
    );
    final selected = result?.files.single;
    if (selected == null) return null;
    return SelectedDocumentFile(
      name: selected.name,
      bytes: selected.bytes ?? await selected.xFile.readAsBytes(),
    );
  }
  final selected = await ImagePicker().pickImage(
    source: source == _UploadSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    imageQuality: 96,
  );
  if (selected == null) return null;
  return SelectedDocumentFile(
    name: selected.name,
    bytes: await selected.readAsBytes(),
  );
}

Future<void> validateSelectedDocument(SelectedDocumentFile file) async {
  if (file.bytes.isEmpty) {
    throw const DocumentFailure('EMPTY_FILE', '文件为空，请重新选择。');
  }
  if (file.bytes.length > documentMaxBytes) {
    throw const DocumentFailure('FILE_TOO_LARGE', '文件不能超过 20MB。');
  }
  final lower = file.name.toLowerCase();
  if (lower.endsWith('.pdf')) {
    final text = latin1.decode(file.bytes, allowInvalid: true);
    if (RegExp(r'/Type\s*/Page(?!s)').allMatches(text).length != 1) {
      throw const DocumentFailure('MULTI_PAGE_PDF', '仅支持单页 PDF。');
    }
    return;
  }
  if (!lower.endsWith('.jpg') &&
      !lower.endsWith('.jpeg') &&
      !lower.endsWith('.png')) {
    throw const DocumentFailure(
      'UNSUPPORTED_FORMAT',
      '仅支持 JPG、JPEG、PNG 或单页 PDF。',
    );
  }
  try {
    final codec = await ui.instantiateImageCodec(file.bytes);
    final frame = await codec.getNextFrame();
    final pixels = frame.image.width * frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (pixels > documentMaxPixels) {
      throw const DocumentFailure('IMAGE_TOO_LARGE', '图片不能超过 25MP。');
    }
  } on DocumentFailure {
    rethrow;
  } on Exception {
    throw const DocumentFailure('UNSUPPORTED_FORMAT', '图片内容无效，请重新选择。');
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _DocumentPreviewDialog extends StatelessWidget {
  const _DocumentPreviewDialog({required this.file});
  final SelectedDocumentFile file;

  @override
  Widget build(BuildContext context) {
    final pdf = file.name.toLowerCase().endsWith('.pdf');
    return AlertDialog(
      title: const Text('确认材料预览'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 220,
              child: pdf
                  ? const Center(child: Icon(Icons.picture_as_pdf, size: 72))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(file.bytes, fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(height: 10),
            Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              '${(file.bytes.length / 1024).toStringAsFixed(1)} KB',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('重新选择'),
        ),
        FilledButton(
          key: const Key('confirm-document-preview'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('使用此文件'),
        ),
      ],
    );
  }
}

class _UploadProgressDialog extends StatefulWidget {
  const _UploadProgressDialog({
    required this.repository,
    required this.file,
    required this.type,
  });
  final DocumentRepository repository;
  final SelectedDocumentFile file;
  final MedicalMaterialType type;

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  late final String _idempotencyKey = newDocumentIdempotencyKey();
  double _progress = 0;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _upload();
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final document = await widget.repository.upload(
        file: widget.file,
        documentType: widget.type.apiValue,
        consentVersion: documentProcessingNoticeVersion,
        idempotencyKey: _idempotencyKey,
        onProgress: (sent, total) {
          if (mounted && total > 0) setState(() => _progress = sent / total);
        },
      );
      if (mounted) Navigator.pop(context, document);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('document-upload-progress'),
      title: Text(_error == null ? '正在安全上传' : '上传未完成'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _busy ? _progress : null),
          const SizedBox(height: 14),
          Text(_error ?? '${(_progress * 100).round()}% · 中断不会创建可用材料记录'),
        ],
      ),
      actions: [
        if (!_busy) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('retry-document-upload'),
            onPressed: _upload,
            child: const Text('安全重试'),
          ),
        ],
      ],
    );
  }
}

class _MaterialTypeSheet extends StatelessWidget {
  const _MaterialTypeSheet();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('选择材料类型', style: Theme.of(context).textTheme.titleLarge),
          Text(
            '先确定材料类型，再选择拍照、相册或文件',
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
        ],
      ),
    ),
  );
}

class _UploadSourceSheet extends StatelessWidget {
  const _UploadSourceSheet({required this.type});
  final MedicalMaterialType type;
  @override
  Widget build(BuildContext context) => SafeArea(
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
          Text(
            'JPG、JPEG、PNG 或单页 PDF · 最大 20MB / 25MP',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          _UploadOption(
            key: const Key('upload-camera-option'),
            icon: Icons.photo_camera_outlined,
            title: '拍照',
            subtitle: '仅在点击后申请相机权限',
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
            key: const Key('upload-file-option'),
            icon: Icons.attach_file_rounded,
            title: '从文件选择',
            subtitle: '支持图片和单页 PDF',
            onTap: () => Navigator.pop(context, _UploadSource.file),
          ),
          _UploadOption(
            key: const Key('upload-demo-option'),
            icon: Icons.science_outlined,
            title: '使用预置模拟材料',
            subtitle: '仅供开发和路演，不包含真实医疗信息',
            onTap: () => Navigator.pop(context, _UploadSource.demo),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => ListTile(
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
