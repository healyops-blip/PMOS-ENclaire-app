import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/presentation/upload_flow.dart';
import 'package:pmos_enclaire/features/records/presentation/ocr_task_page.dart';
import 'package:printing/printing.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    required this.repository,
    required this.ocrRepository,
    super.key,
  });

  final DocumentRepository repository;
  final OcrRepository ocrRepository;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String? _filter;
  late Future<List<MedicalDocument>> _documents = _load();

  Future<List<MedicalDocument>> _load() =>
      widget.repository.list(documentType: _filter);

  void _reload() => setState(() => _documents = _load());

  @override
  Widget build(BuildContext context) {
    const filters = <(String, String?)>[
      ('全部', null),
      ('化验', 'lab_report'),
      ('处方', 'medical_order'),
      ('影像', 'imaging_text_report'),
      ('门诊', 'outpatient_record'),
    ];
    return ColoredBox(
      key: const Key('records-page'),
      color: PomiColors.surfaceMuted,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: PomiPageHeader(
              title: '医疗材料',
              subtitle: '私有存储 · 原始文件与每次修订均可追溯',
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ChoiceChip(
                  label: Text(filters[index].$1),
                  selected: filters[index].$2 == _filter,
                  onSelected: (_) {
                    _filter = filters[index].$2;
                    _reload();
                  },
                  selectedColor: PomiColors.primary,
                  labelStyle: TextStyle(
                    color: filters[index].$2 == _filter
                        ? Colors.white
                        : PomiColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          FutureBuilder<List<MedicalDocument>>(
            future: _documents,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: _StatusView(
                    icon: Icons.cloud_off_rounded,
                    title: '材料加载失败',
                    action: '重试',
                    onPressed: _reload,
                  ),
                );
              }
              final items = snapshot.data!;
              if (items.isEmpty) {
                return SliverFillRemaining(
                  child: _StatusView(
                    icon: Icons.folder_open_rounded,
                    title: '还没有这类材料',
                    action: '上传材料',
                    onPressed: () => showUploadFlow(
                      context,
                      repository: widget.repository,
                      ocrRepository: widget.ocrRepository,
                      onUploaded: _reload,
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 126),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _DocumentCard(
                    document: items[index],
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => DocumentDetailPage(
                            repository: widget.repository,
                            ocrRepository: widget.ocrRepository,
                            documentId: items[index].id,
                          ),
                        ),
                      );
                      _reload();
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.onTap});
  final MedicalDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PomiSectionCard(
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: PomiColors.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            document.isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.originalFileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${_typeLabel(document.documentType)} · '
                '${DateFormat('yyyy-MM-dd HH:mm').format(document.uploadedAt.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'SHA-256 ${document.fileHash.isEmpty ? '已保存' : document.fileHash.substring(0, 8)}…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}

class DocumentDetailPage extends StatefulWidget {
  const DocumentDetailPage({
    required this.repository,
    required this.ocrRepository,
    required this.documentId,
    super.key,
  });
  final DocumentRepository repository;
  final OcrRepository ocrRepository;
  final String documentId;

  @override
  State<DocumentDetailPage> createState() => _DocumentDetailPageState();
}

class _DocumentDetailPageState extends State<DocumentDetailPage> {
  late Future<(MedicalDocument, List<DocumentRevision>, Uint8List)> _content =
      _load();

  Future<(MedicalDocument, List<DocumentRevision>, Uint8List)> _load() async {
    final document = await widget.repository.get(widget.documentId);
    final revisions = await widget.repository.revisions(widget.documentId);
    final bytes = await widget.repository.download(
      document.id,
      document.currentRevisionId,
    );
    return (document, revisions, bytes);
  }

  void _reload() => setState(() => _content = _load());

  Future<void> _replace(MedicalDocument document) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null || !mounted) return;
    final file = SelectedDocumentFile(
      name: picked.name,
      bytes: picked.bytes ?? await picked.xFile.readAsBytes(),
    );
    await validateSelectedDocument(file);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建新文件修订？'),
        content: const Text('旧修订和哈希将永久保留用于追溯。结构化字段纠错不需要替换文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-revision-replace'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.replace(
      documentId: document.id,
      expectedRevisionId: document.currentRevisionId,
      reason: '用户确认替换为更清晰的原始材料',
      file: file,
      onProgress: (_, _) {},
    );
    _reload();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这份材料？'),
        content: const Text('材料会立即隐藏；未被报告引用的文件将在 7 天回收期后清理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-document-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.delete(widget.documentId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('document-detail-page'),
    appBar: AppBar(title: const Text('材料详情')),
    body: FutureBuilder<(MedicalDocument, List<DocumentRevision>, Uint8List)>(
      future: _content,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _StatusView(
            icon: Icons.error_outline,
            title: '无法读取私有材料',
            action: '重试',
            onPressed: _reload,
          );
        }
        final (document, revisions, bytes) = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            SizedBox(
              height: 360,
              child: document.isPdf
                  ? PdfPreview(
                      build: (_) async => bytes,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      allowPrinting: false,
                      allowSharing: false,
                    )
                  : InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(height: 14),
            PomiSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.originalFileName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '完整 SHA-256\n${document.fileHash}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '大小：${(document.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('修订历史', style: Theme.of(context).textTheme.titleMedium),
            for (final revision in revisions)
              ListTile(
                leading: CircleAvatar(
                  child: Text('V${revision.revisionNumber}'),
                ),
                title: Text(
                  DateFormat('yyyy-MM-dd HH:mm')
                      .format(revision.createdAt.toLocal()),
                ),
                subtitle: Text(revision.replacementReason ?? '首次上传'),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('start-document-ocr-button'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => OcrTaskPage(
                    repository: widget.ocrRepository,
                    document: document,
                    documentRepository: widget.repository,
                  ),
                ),
              ),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('开始或查看文字识别'),
            ),
            FilledButton.icon(
              key: const Key('replace-document-button'),
              onPressed: () => _replace(document),
              icon: const Icon(Icons.upload_file),
              label: const Text('替换原始文件'),
            ),
            TextButton.icon(
              key: const Key('delete-document-button'),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除材料'),
            ),
          ],
        );
      },
    ),
  );
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.title,
    required this.action,
    required this.onPressed,
  });
  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 54, color: PomiColors.textMuted),
        const SizedBox(height: 10),
        Text(title),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    ),
  );
}

String _typeLabel(String value) => switch (value) {
  'lab_report' => '化验／检测',
  'medical_order' => '医嘱／处方',
  'imaging_text_report' => '影像文字报告',
  _ => '门诊病历',
};
