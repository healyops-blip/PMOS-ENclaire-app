import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../upload/certification_repository.dart';
import '../upload/upload_screen.dart';
import 'visit_record_detail_screen.dart';

final recordsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final values = await Future.wait([
    ref.read(apiClientProvider).get('/api/documents'),
    ref.read(apiClientProvider).get('/api/reports'),
  ]);
  return {'documents': values[0], 'reports': values[1]};
});

final reportDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, reportId) async {
      final detail = await ref
          .read(apiClientProvider)
          .get('/api/reports/$reportId');
      return Map<String, dynamic>.from(detail as Map);
    });

class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({this.initialTab = 0, this.onBack, super.key});

  final int initialTab;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordsProvider);
    return Scaffold(
      appBar: null,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (data) {
          final documentPage = Map<String, dynamic>.from(
            data['documents'] as Map,
          );
          final documents = List<Map<String, dynamic>>.from(
            (documentPage['items'] as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );
          final reportPage = Map<String, dynamic>.from(data['reports'] as Map);
          final reports = List<Map<String, dynamic>>.from(
            (reportPage['items'] as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );
          if (initialTab == 1) {
            if (smokeMode && reports.isNotEmpty) {
              return _ApiReportViewer(
                reportId: reports.first['report_id'].toString(),
                onBack: onBack,
              );
            }
            return _ReportsList(reports: reports);
          }
          if (smokeMode) return const VisitRecordsPage();
          return _DocumentsList(documents: documents);
        },
      ),
    );
  }
}

class _ApiReportViewer extends ConsumerWidget {
  const _ApiReportViewer({required this.reportId, this.onBack});

  final String reportId;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(reportDetailProvider(reportId))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (report) => ReportViewer(report: report, onBack: onBack),
      );
}

class VisitRecordsPage extends StatelessWidget {
  const VisitRecordsPage({super.key});

  static const visits = smokeVisitRecordDetails;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 18),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 96),
            children: [
              Row(
                children: [
                  Text('全部记录', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showFilters(context),
                    icon: const Icon(Icons.filter_alt_outlined, size: 19),
                    label: const Text('筛选'),
                  ),
                  TextButton.icon(
                    onPressed: () => _showUpload(context),
                    icon: const Icon(Icons.add, size: 19),
                    label: const Text('上传'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < visits.length; index++) ...[
                _VisitRecordCard(visit: visits[index]),
                if (index != visits.length - 1) const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showFilters(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder:
        (context) => const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Text(
                  '筛选记录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                SizedBox(width: double.infinity),
                FilterChip(label: Text('全部'), selected: true, onSelected: null),
                FilterChip(
                  label: Text('化验/检测'),
                  selected: false,
                  onSelected: null,
                ),
                FilterChip(
                  label: Text('门诊病历'),
                  selected: false,
                  onSelected: null,
                ),
                FilterChip(
                  label: Text('医嘱/处方'),
                  selected: false,
                  onSelected: null,
                ),
              ],
            ),
          ),
        ),
  );

  Future<void> _showUpload(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: pomiInk.withValues(alpha: .22),
    builder:
        (context) => Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 34,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .84,
            ),
            child: const UploadScreen(modal: true),
          ),
        ),
  );
}

class _DocumentsList extends StatelessWidget {
  const _DocumentsList({required this.documents});

  final List<Map<String, dynamic>> documents;

  static const labels = {
    'lab_report': '化验 / 检测',
    'medical_order': '医嘱 / 处方',
    'imaging_text_report': '影像文字报告',
    'outpatient_record': '门诊病历',
  };

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return const _EmptyState(
        icon: Icons.folder_open_outlined,
        text: '还没有上传医疗资料',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
      itemCount: documents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final document = documents[index];
        return PomiGlassCard(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            leading: _DocumentIcon(type: document['document_type'].toString()),
            title: Text(
              document['original_file_name'].toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${labels[document['document_type']] ?? document['document_type']} · '
              '${_statusLabel(document['latest_ocr_status']?.toString())}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (context) => DocumentDetailScreen(document: document),
                  ),
                ),
          ),
        );
      },
    );
  }

  static String _statusLabel(String? status) => switch (status) {
    'confirmed' => '已确认',
    'succeeded' || 'fallback' => '待确认',
    'processing' => '识别中',
    'pending' => '排队中',
    'failed' => '识别失败',
    _ => '未识别',
  };
}

class _DocumentIcon extends StatelessWidget {
  const _DocumentIcon({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      'lab_report' => Icons.science_outlined,
      'medical_order' => Icons.medication_outlined,
      'imaging_text_report' => Icons.image_search_outlined,
      _ => Icons.description_outlined,
    };
    return CircleAvatar(
      backgroundColor: pomiMint.withValues(alpha: .15),
      foregroundColor: pomiTeal,
      child: Icon(icon),
    );
  }
}

class _VisitRecordCard extends StatelessWidget {
  const _VisitRecordCard({required this.visit});

  final VisitRecordDetailData visit;

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      key: ValueKey('visit-record-${visit.id}'),
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => VisitRecordDetailScreen(visit: visit),
            ),
          ),
      borderRadius: 20,
      backgroundOpacity: .36,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            visit.date,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: _VisitStatusBadge(
                              text: visit.verificationLabel,
                              tone: visit.verificationState,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      _VisitMetadataFields(visit: visit),
                      if (visit.historyNote != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          '超过 6 个月 · 仅供参考',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF9B6818),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      const Align(
                        alignment: Alignment.center,
                        child: Text(
                          '区块链技术支持',
                          style: TextStyle(
                            color: pomiPurple,
                            fontSize: 10,
                            height: 14 / 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Column(
                  children: [
                    Icon(Icons.chevron_right_rounded, color: pomiSecondaryText),
                    SizedBox(height: 2),
                    Text(
                      '详情',
                      style: TextStyle(
                        color: pomiSecondaryText,
                        fontSize: 10,
                        height: 14 / 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: pomiLine),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < visit.summaryItems.length;
                  index++
                ) ...[
                  _VisitRecordRow(row: visit.summaryItems[index]),
                  if (index != visit.summaryItems.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitMetadataFields extends StatelessWidget {
  const _VisitMetadataFields({required this.visit});

  final VisitRecordDetailData visit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(
          visit.hospital,
          key: ValueKey('visit-hospital-${visit.id}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          visit.department,
          key: ValueKey('visit-department-${visit.id}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          visit.doctor,
          key: ValueKey('visit-doctor-${visit.id}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (visit.contextLabel != null)
          Text(
            visit.contextLabel!,
            key: ValueKey('visit-context-${visit.id}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _VisitStatusBadge extends StatelessWidget {
  const _VisitStatusBadge({required this.text, required this.tone});

  final String text;
  final VisitVerificationState tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      VisitVerificationState.verified || VisitVerificationState.archived => (
        pomiPurple.withValues(alpha: .10),
        pomiPurple,
      ),
      VisitVerificationState.pending => (
        const Color(0xFFE4F1FF),
        const Color(0xFF2F81C5),
      ),
      VisitVerificationState.unverified => (
        const Color(0xFFF1F0F3),
        pomiSecondaryText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VisitRecordRow extends StatelessWidget {
  const _VisitRecordRow({required this.row});

  final VisitRecordSummaryItem row;

  @override
  Widget build(BuildContext context) {
    final (tag, background, foreground) = switch (row.category) {
      VisitRecordCategory.lab => (
        '化验/检测',
        pomiPurple.withValues(alpha: .09),
        pomiPurple,
      ),
      VisitRecordCategory.order => (
        '医嘱/处方',
        pomiMint.withValues(alpha: .12),
        const Color(0xFF169F91),
      ),
      VisitRecordCategory.outpatient => (
        '门诊病历',
        const Color(0xFFFFF2D9),
        const Color(0xFFC78519),
      ),
    };
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            row.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            tag,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (row.trailing != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({required this.document, super.key});

  final Map<String, dynamic> document;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  CertificationRecord? _certification;
  bool _certifying = false;

  String get documentId => widget.document['id'].toString();
  String get revisionId => widget.document['current_revision_id'].toString();

  @override
  void initState() {
    super.initState();
    _loadCertification();
  }

  Future<void> _loadCertification() async {
    final value = await ref
        .read(certificationRepositoryProvider)
        .get(documentId, revisionId);
    if (mounted) setState(() => _certification = value);
  }

  Future<void> _certify() async {
    setState(() {
      _certifying = true;
      _certification = CertificationRecord(
        status: CertificationStatus.processing,
        updatedAt: DateTime.now(),
      );
    });
    final result = await ref
        .read(certificationRepositoryProvider)
        .start(documentId, revisionId);
    if (mounted) {
      setState(() {
        _certification = result;
        _certifying = false;
      });
    }
  }

  Future<void> _openOriginal() async {
    final bytes = await ref
        .read(apiClientProvider)
        .download('/api/documents/$documentId/revisions/$revisionId/file');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => OriginalFileScreen(
              bytes: Uint8List.fromList(bytes),
              mimeType: widget.document['mime_type'].toString(),
              fileName: widget.document['original_file_name'].toString(),
            ),
      ),
    );
  }

  Future<void> _openReconciliation() async {
    try {
      final value = await ref
          .read(apiClientProvider)
          .post(
            '/api/medication-reconciliations',
            data: {'ocr_task_id': widget.document['latest_ocr_task_id']},
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) => ReconciliationScreen(
                reconciliation: Map<String, dynamic>.from(value as Map),
              ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _certification?.status ?? CertificationStatus.notStarted;
    final confirmed = widget.document['latest_ocr_status'] == 'confirmed';
    return Scaffold(
      appBar: AppBar(title: const Text('资料详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          if (status == CertificationStatus.succeeded)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE4F1ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFB8D8CE)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_outlined, color: pomiTeal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '本机认证演示 · 已完成\n未真实上链，不代表医院签发',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            widget.document['original_file_name'].toString(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          _DetailRow(
            label: '材料类型',
            value: widget.document['document_type'].toString(),
          ),
          _DetailRow(
            label: '上传时间',
            value: widget.document['uploaded_at'].toString(),
          ),
          _DetailRow(
            label: '文件大小',
            value: '${widget.document['file_size_bytes']} bytes',
          ),
          _DetailRow(
            label: '识别状态',
            value: widget.document['latest_ocr_status']?.toString() ?? '未识别',
          ),
          _DetailRow(label: '修订标识', value: revisionId),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openOriginal,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('查看原件'),
          ),
          const SizedBox(height: 10),
          if (confirmed &&
              widget.document['document_type'] == 'medical_order') ...[
            OutlinedButton.icon(
              onPressed: _openReconciliation,
              icon: const Icon(Icons.compare_arrows),
              label: const Text('用药对账'),
            ),
            const SizedBox(height: 10),
          ],
          if (confirmed && status != CertificationStatus.succeeded)
            FilledButton.icon(
              onPressed: _certifying ? null : _certify,
              icon:
                  _certifying
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.verified_outlined),
              label: Text(_certifying ? '认证处理中' : '医院认证'),
            ),
          if (confirmed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '提供区块链技术支持（当前仅为本地界面演示）',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: pomiSecondaryText),
              ),
            ),
        ],
      ),
    );
  }
}

class ReconciliationScreen extends ConsumerStatefulWidget {
  const ReconciliationScreen({required this.reconciliation, super.key});

  final Map<String, dynamic> reconciliation;

  @override
  ConsumerState<ReconciliationScreen> createState() =>
      _ReconciliationScreenState();
}

class _ReconciliationScreenState extends ConsumerState<ReconciliationScreen> {
  final Map<String, String> _decisions = {};
  bool _saving = false;

  Future<void> _save(List<Map<String, dynamic>> items) async {
    if (items.any((item) => !_decisions.containsKey(item['id']))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请逐项选择处理方式')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/api/medication-reconciliations/${widget.reconciliation['id']}',
            data: {
              'decisions':
                  items
                      .map(
                        (item) => {
                          'item_id': item['id'],
                          'decision': _decisions[item['id']],
                        },
                      )
                      .toList(),
            },
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(
      (widget.reconciliation['items'] as List).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final alreadyConfirmed =
        widget.reconciliation['reconciliation_status'] == 'confirmed';
    return Scaffold(
      appBar: AppBar(title: const Text('用药对账')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          const Text(
            '逐项核对新旧医嘱',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('旧药未出现在新医嘱中，不会自动标记停药。'),
          const SizedBox(height: 18),
          ...items.map((item) {
            final oldInstruction = item['old_instruction'] as Map?;
            final newInstruction = item['new_instruction'] as Map?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PomiGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item['drug_name'].toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '现有：${oldInstruction?['dosage_text'] ?? '无当前记录'} '
                        '${oldInstruction?['frequency'] ?? ''}',
                      ),
                      Text(
                        '医嘱：${newInstruction?['dosage_text'] ?? '未提取'} '
                        '${newInstruction?['frequency'] ?? ''}',
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue:
                            alreadyConfirmed
                                ? item['user_decision']?.toString()
                                : null,
                        decoration: const InputDecoration(labelText: '处理方式'),
                        items: const [
                          DropdownMenuItem(
                            value: 'accept_new',
                            child: Text('采用新医嘱'),
                          ),
                          DropdownMenuItem(
                            value: 'keep_existing',
                            child: Text('保留当前用法'),
                          ),
                          DropdownMenuItem(
                            value: 'stop_existing',
                            child: Text('确认停用现有药物'),
                          ),
                          DropdownMenuItem(
                            value: 'manual_review',
                            child: Text('暂不变更，线下确认'),
                          ),
                        ],
                        onChanged:
                            alreadyConfirmed
                                ? null
                                : (value) {
                                  if (value != null) {
                                    _decisions[item['id'].toString()] = value;
                                  }
                                },
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar:
          alreadyConfirmed
              ? null
              : SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(items),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? '正在保存' : '确认对账'),
                ),
              ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(color: pomiSecondaryText),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class OriginalFileScreen extends StatelessWidget {
  const OriginalFileScreen({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    super.key,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, overflow: TextOverflow.ellipsis),
        actions: [
          if (mimeType == 'application/pdf')
            IconButton(
              tooltip: '打印',
              onPressed:
                  () => Printing.layoutPdf(onLayout: (format) async => bytes),
              icon: const Icon(Icons.print_outlined),
            ),
        ],
      ),
      body:
          mimeType == 'application/pdf'
              ? PdfPreview(
                build: (format) async => bytes,
                canChangePageFormat: false,
              )
              : InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(child: Image.memory(bytes)),
              ),
    );
  }
}

class _ReportsList extends ConsumerWidget {
  const _ReportsList({required this.reports});

  final List<Map<String, dynamic>> reports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body:
          reports.isEmpty
              ? const _EmptyState(
                icon: Icons.summarize_outlined,
                text: '还没有生成复诊报告',
              )
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
                itemCount: reports.length,
                separatorBuilder:
                    (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final report = reports[index];
                  return PomiGlassCard(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFE9E3),
                        foregroundColor: pomiCoral,
                        child: Icon(Icons.summarize_outlined),
                      ),
                      title: const Text('数据汇总'),
                      subtitle: Text(report['generated_at'].toString()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final detail = await ref
                            .read(apiClientProvider)
                            .get('/api/reports/${report['report_id']}');
                        if (context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (context) => ReportViewer(
                                    report: Map<String, dynamic>.from(
                                      detail as Map,
                                    ),
                                  ),
                            ),
                          );
                        }
                      },
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createReport(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('患者自述'),
      ),
    );
  }

  Future<void> _createReport(BuildContext context, WidgetRef ref) async {
    final statement = TextEditingController();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => Padding(
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
                  '患者自述',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text('可补充患者自述；指标看板会自动汇总已上传的检验单和其他资料。'),
                const SizedBox(height: 16),
                TextField(
                  controller: statement,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    hintText: '例如：最近三个月经期、用药感受和希望与医生讨论的问题',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('确认自述并生成'),
                ),
              ],
            ),
          ),
    );
    if (accepted != true) {
      statement.dispose();
      return;
    }
    try {
      final api = ref.read(apiClientProvider);
      final text = statement.text.trim();
      String? noteId;
      if (text.isNotEmpty) {
        final note = await api.post(
          '/api/patient-notes',
          data: {'original_text': text},
        );
        await api.post('/api/patient-notes/${note['id']}/confirm');
        noteId = note['id']?.toString();
      }
      final report = await api.post(
        '/api/reports',
        data: {
          if (noteId != null) 'patient_note_id': noteId,
          'confirm_incomplete': true,
        },
      );
      ref.invalidate(recordsProvider);
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (context) => ReportViewer(
                  report: Map<String, dynamic>.from(report as Map),
                ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      statement.dispose();
    }
  }
}

class ReportViewer extends ConsumerStatefulWidget {
  const ReportViewer({required this.report, this.onBack, super.key});

  final Map<String, dynamic> report;
  final VoidCallback? onBack;

  @override
  ConsumerState<ReportViewer> createState() => _ReportViewerState();
}

class _ReportViewerState extends ConsumerState<ReportViewer> {
  int _layer = 0;
  String? _selectedTrendMetricId;
  final _cycleSectionKey = GlobalKey();
  final _bmiSectionKey = GlobalKey();
  final _medicationSectionKey = GlobalKey();
  final _labSectionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final snapshot = Map<String, dynamic>.from(
      widget.report['snapshot'] as Map,
    );
    final summary = Map<String, dynamic>.from(snapshot['summary'] as Map);
    final profile = Map<String, dynamic>.from(
      summary['profile'] as Map? ?? const {},
    );
    summary['patient_name'] = profile['nickname'];
    summary['patient_statement'] = summary['patient_note_text'];
    final trends = Map<String, dynamic>.from(snapshot['trends'] as Map);
    final medicines = List<Map<String, dynamic>>.from(
      (summary['current_medications'] as List? ?? []).map((item) {
        final value = Map<String, dynamic>.from(item as Map);
        final dosageValue = value['dosage_value'];
        final dosageUnit = value['dosage_unit']?.toString() ?? '';
        value['dosage_text'] =
            dosageValue == null
                ? value['specification']
                : '$dosageValue$dosageUnit';
        return value;
      }),
    );
    final labTrends = List<Map<String, dynamic>>.from(
      (trends['labs'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final labs = <Map<String, dynamic>>[];
    for (final group in labTrends) {
      final points = List<Map<String, dynamic>>.from(
        (group['points'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      if (points.isEmpty) continue;
      final point = points.last;
      point['metric_id'] = group['metric_id'];
      point['item_name'] =
          group['metric_name'] ?? point['original_item_name'] ?? '指标';
      point['sample_date'] = point['date'];
      point['raw_unit'] =
          point['original_unit'] ?? point['normalized_unit'] ?? group['unit'];
      labs.add(point);
    }
    Map<String, dynamic>? glucoseTrend;
    for (final group in labTrends) {
      final metricId = group['metric_id']?.toString().toLowerCase() ?? '';
      final name =
          (group['metric_name'] ?? group['item_name'])?.toString() ?? '';
      if (metricId == 'glucose' ||
          name.contains('空腹血糖') ||
          name.toLowerCase().contains('fasting glucose')) {
        glucoseTrend = group;
        break;
      }
    }
    final selectedTrend =
        _selectedTrendMetricId == null
            ? null
            : labTrends.cast<Map<String, dynamic>?>().firstWhere(
              (group) =>
                  group?['metric_id']?.toString() == _selectedTrendMetricId,
              orElse: () => null,
            );
    final weights = List<Map<String, dynamic>>.from(
      (trends['weights'] as List? ?? []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final cycles = List<Map<String, dynamic>>.from(
      (trends['cycles'] as List? ?? []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final sourceGroups = <String, List<Map<String, dynamic>>>{
      '报告来源': List<Map<String, dynamic>>.from(
        (snapshot['sources'] as List? ?? []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
    };
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  onPressed: () {
                    if (_layer != 0) {
                      setState(() => _layer = 0);
                      return;
                    }
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      widget.onBack?.call();
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: Text(
                        'POMI报告',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ReportLayerNavigation(
            layer: _layer,
            onSelect: (layer) {
              setState(() {
                _layer = layer;
                if (layer == 1) _selectedTrendMetricId = null;
              });
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _layer,
              children: [
                _ReportSummaryLayer(
                  report: widget.report,
                  summary: summary,
                  medicines: medicines,
                  labs: labs,
                  glucoseTrend: glucoseTrend,
                  weights: weights,
                  cycles: cycles,
                  cycleCount: cycles.length,
                  weightCount: weights.length,
                  sourceCount: sourceGroups['报告来源']!.length,
                  cycleSectionKey: _cycleSectionKey,
                  bmiSectionKey: _bmiSectionKey,
                  medicationSectionKey: _medicationSectionKey,
                  labSectionKey: _labSectionKey,
                  onOpenTrends:
                      (metricId) => setState(() {
                        _selectedTrendMetricId = metricId;
                        _layer = 1;
                      }),
                  onOpenSources: () => setState(() => _layer = 2),
                  medicalBoundary: (summary['disclaimers'] as List? ?? const [])
                      .join('\n'),
                ),
                _ReportTrendLayer(
                  weights: weights,
                  cycles: cycles,
                  labs: labs,
                  glucoseTrend: glucoseTrend,
                  selectedMetricId: _selectedTrendMetricId,
                  selectedTrend: selectedTrend,
                  onSelectMetric:
                      (metricId) => setState(() {
                        _selectedTrendMetricId = metricId;
                        _layer = 1;
                      }),
                  onOpenSources: () => setState(() => _layer = 2),
                ),
                _ReportSourceLayer(sourceGroups: sourceGroups),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportLayerNavigation extends StatelessWidget {
  const _ReportLayerNavigation({required this.layer, required this.onSelect});

  final int layer;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
    child: Row(
      children: [
        _ReportLayerChip(
          label: '1  摘要',
          selected: layer == 0,
          onTap: () => onSelect(0),
        ),
        const SizedBox(width: 7),
        _ReportLayerChip(
          label: '2  趋势',
          selected: layer == 1,
          onTap: () => onSelect(1),
        ),
        const SizedBox(width: 7),
        _ReportLayerChip(
          label: '3  原始数据',
          selected: layer == 2,
          onTap: () => onSelect(2),
        ),
      ],
    ),
  );
}

class _ReportLayerChip extends StatelessWidget {
  const _ReportLayerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? pomiPurple : const Color(0xFFF1EFF4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : pomiMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReportSummaryLayer extends StatelessWidget {
  const _ReportSummaryLayer({
    required this.report,
    required this.summary,
    required this.medicines,
    required this.labs,
    required this.glucoseTrend,
    required this.weights,
    required this.cycles,
    required this.cycleCount,
    required this.weightCount,
    required this.sourceCount,
    required this.cycleSectionKey,
    required this.bmiSectionKey,
    required this.medicationSectionKey,
    required this.labSectionKey,
    required this.onOpenTrends,
    required this.onOpenSources,
    required this.medicalBoundary,
  });
  final Map<String, dynamic> report;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> medicines;
  final List<Map<String, dynamic>> labs;
  final Map<String, dynamic>? glucoseTrend;
  final List<Map<String, dynamic>> weights;
  final List<Map<String, dynamic>> cycles;
  final String medicalBoundary;
  final int cycleCount;
  final int weightCount;
  final int sourceCount;
  final GlobalKey cycleSectionKey;
  final GlobalKey bmiSectionKey;
  final GlobalKey medicationSectionKey;
  final GlobalKey labSectionKey;
  final ValueChanged<String?> onOpenTrends;
  final VoidCallback onOpenSources;

  String get _reportAbstract {
    final weightSummary = Map<String, dynamic>.from(
      summary['weight_summary'] as Map? ?? const {},
    );
    final weight = weightSummary['latest_weight_kg'];
    final bmi = weightSummary['latest_bmi'];
    final glucosePoints = glucoseTrend?['points'] as List? ?? const [];
    final glucose =
        glucosePoints.isEmpty
            ? null
            : Map<String, dynamic>.from(glucosePoints.last as Map);
    final glucoseText =
        glucose == null
            ? ''
            : '最新空腹血糖 ${glucose['normalized_value'] ?? glucose['numeric_value'] ?? glucose['raw_value'] ?? '—'} ${glucose['normalized_unit'] ?? glucoseTrend?['unit'] ?? glucose['original_unit'] ?? ''}。';
    return '本次报告汇总 $cycleCount 次经期记录、$weightCount 个体重数据点、${labs.length} 项检查指标和 ${medicines.length} 项当前用药。'
        '${weight == null ? '' : '当前体重 $weight kg${bmi == null ? '' : '，BMI $bmi'}。'}'
        '$glucoseText';
  }

  Map<String, dynamic> get _weightSummary =>
      Map<String, dynamic>.from(summary['weight_summary'] as Map? ?? const {});

  String get _bmiAssessment => switch (_weightSummary['bmi_status']) {
    'low' => '偏低',
    'in_range' => '范围内',
    'high' => '略高',
    _ => '暂无评估',
  };

  Map<String, dynamic>? get _latestCycle => cycles.isEmpty ? null : cycles.last;

  int? get _latestCompletedCycleLength {
    for (final cycle in cycles.reversed) {
      final value = cycle['cycle_length_days'];
      if (value is int) return value;
    }
    return null;
  }

  String _shortDate(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    return date == null ? '—' : '${date.month}/${date.day}';
  }

  String get _latestPeriodRange {
    final cycle = _latestCycle;
    if (cycle == null) return '—';
    final start = _shortDate(cycle['start_date']);
    final end = _shortDate(cycle['end_date']);
    return end == '—' ? '$start 起' : '$start–$end';
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
    children: [
      _DoctorReportHeader(
        name: (summary['profile'] as Map?)?['nickname']?.toString() ?? '未设置姓名',
        height: (summary['profile'] as Map?)?['height_cm'],
        weight: _weightSummary['latest_weight_kg'],
      ),
      const SizedBox(height: 12),
      _CompactTextSection(
        title: '患者自述',
        text: summary['patient_statement']?.toString() ?? '未填写',
      ),
      const SizedBox(height: 12),
      _CompactTextSection(title: '摘要', text: _reportAbstract),
      const SizedBox(height: 14),
      _SectionHeading(title: '近期基础信息', trailing: '点击卡片查看完整趋势'),
      const SizedBox(height: 7),
      KeyedSubtree(
        key: cycleSectionKey,
        child: _RecentCycleCard(
          cycleLengthDays: _latestCompletedCycleLength,
          periodLengthDays: _latestCycle?['duration_days'] as int?,
          periodRange: _latestPeriodRange,
          currentStartDate: _latestCycle?['start_date']?.toString(),
          onTap: () => onOpenTrends('cycle'),
        ),
      ),
      const SizedBox(height: 9),
      KeyedSubtree(
        key: bmiSectionKey,
        child: _CompactBmiCard(
          weights: weights,
          weightSummary: _weightSummary,
          assessment: _bmiAssessment,
          onTap: () => onOpenTrends('weight'),
        ),
      ),
      const SizedBox(height: 14),
      KeyedSubtree(
        key: labSectionKey,
        child: _KeyMetricsSection(labs: labs, onOpenTrends: onOpenTrends),
      ),
      const SizedBox(height: 14),
      KeyedSubtree(
        key: medicationSectionKey,
        child: _CompactMedicationSection(medicines: medicines),
      ),
      const SizedBox(height: 10),
      _ReportSourceShortcut(
        labCount: labs.length,
        cycleCount: cycleCount,
        weightCount: weightCount,
        sourceCount: sourceCount,
        onTap: onOpenSources,
      ),
      const SizedBox(height: 12),
      Text(
        medicalBoundary,
        style: const TextStyle(color: pomiMuted, fontSize: 11),
      ),
    ],
  );
}

class _DoctorReportHeader extends StatelessWidget {
  const _DoctorReportHeader({
    required this.name,
    required this.height,
    required this.weight,
  });

  final String name;
  final dynamic height;
  final dynamic weight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: pomiLine)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '身高 ${height ?? '—'} cm',
          style: const TextStyle(color: pomiMuted),
        ),
        const SizedBox(width: 12),
        Text(
          '体重 ${weight ?? '—'} kg',
          style: const TextStyle(color: pomiMuted),
        ),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      if (trailing != null)
        Text(trailing!, style: const TextStyle(color: pomiMuted, fontSize: 10)),
    ],
  );
}

class _CompactTextSection extends StatelessWidget {
  const _CompactTextSection({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeading(title: title),
      const SizedBox(height: 5),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: pomiLine),
        ),
        child: Text(text, style: const TextStyle(height: 1.45, fontSize: 12)),
      ),
    ],
  );
}

class _RecentCycleCard extends StatelessWidget {
  const _RecentCycleCard({
    required this.cycleLengthDays,
    required this.periodLengthDays,
    required this.periodRange,
    required this.currentStartDate,
    required this.onTap,
  });

  final int? cycleLengthDays;
  final int? periodLengthDays;
  final String periodRange;
  final String? currentStartDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PomiGlassCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
    backgroundColor: const Color(0xFFF7F6F8),
    child: Column(
      children: [
        Row(
          children: [
            _ClinicalStat(label: '周期时长', value: '${cycleLengthDays ?? '—'} 天'),
            _ClinicalStat(label: '月经长度', value: '${periodLengthDays ?? '—'} 天'),
            _ClinicalStat(label: '月经时间', value: periodRange),
            const Icon(Icons.chevron_right_rounded, color: pomiMuted, size: 18),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          width: double.infinity,
          child: CustomPaint(
            painter: _CycleSundialPainter(
              cycleLengthDays: cycleLengthDays ?? 56,
              periodLengthDays: periodLengthDays ?? 0,
              startLabel: _monthDay(currentStartDate),
            ),
          ),
        ),
      ],
    ),
  );

  static String _monthDay(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    return date == null
        ? '未记录'
        : '${date.month.toString().padLeft(2, '0')}–${date.day.toString().padLeft(2, '0')}';
  }
}

class _ClinicalStat extends StatelessWidget {
  const _ClinicalStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: pomiMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _CycleSundialPainter extends CustomPainter {
  const _CycleSundialPainter({
    required this.cycleLengthDays,
    required this.periodLengthDays,
    required this.startLabel,
  });

  final int cycleLengthDays;
  final int periodLengthDays;
  final String startLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 4.0;
    final right = size.width - 4;
    final y = size.height * .58;
    final maxDays = cycleLengthDays.clamp(28, 56);
    final grid = Paint()..color = const Color(0xFFE7E4EB);
    for (var day = 0; day <= 56; day += 7) {
      final x = left + (right - left) * day / 56;
      canvas.drawLine(Offset(x, 13), Offset(x, size.height - 4), grid);
      _paintText(canvas, '$day', Offset(x, 0), center: true);
    }
    final track =
        Paint()
          ..color = const Color(0xFFE8DFF2)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(right, y), track);
    final periodEnd =
        left + (right - left) * periodLengthDays.clamp(0, 56) / 56;
    final period =
        Paint()
          ..color = pomiPurple
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(periodEnd, y), period);
    final cycleEnd = left + (right - left) * maxDays / 56;
    final active =
        Paint()
          ..color = pomiPurple.withValues(alpha: .45)
          ..strokeWidth = 1.5;
    _drawDashedLine(
      canvas,
      Offset(periodEnd + 5, y),
      Offset(cycleEnd, y),
      active,
    );
    _paintText(canvas, '当前周期  $startLabel', Offset(left, y + 10));
    _paintText(
      canvas,
      '进行中',
      Offset(right, y + 10),
      rightAligned: true,
      accent: true,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    for (var x = start.dx; x < end.dx; x += 7) {
      canvas.drawLine(
        Offset(x, start.dy),
        Offset((x + 4).clamp(x, end.dx), end.dy),
        paint,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset, {
    bool center = false,
    bool rightAligned = false,
    bool accent = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: accent ? pomiPurple : pomiMuted, fontSize: 8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx =
        center
            ? offset.dx - painter.width / 2
            : rightAligned
            ? offset.dx - painter.width
            : offset.dx;
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _CycleSundialPainter oldDelegate) =>
      oldDelegate.cycleLengthDays != cycleLengthDays ||
      oldDelegate.periodLengthDays != periodLengthDays ||
      oldDelegate.startLabel != startLabel;
}

class _CompactBmiCard extends StatelessWidget {
  const _CompactBmiCard({
    required this.weights,
    required this.weightSummary,
    required this.assessment,
    required this.onTap,
  });

  final List<Map<String, dynamic>> weights;
  final Map<String, dynamic> weightSummary;
  final String assessment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PomiGlassCard(
    onTap: onTap,
    padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
    backgroundColor: const Color(0xFFF7F6F8),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BMI 趋势',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                '${weightSummary['latest_bmi'] ?? '—'}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '$assessment · ${weightSummary['latest_weight_kg'] ?? '—'} kg',
                style: const TextStyle(color: pomiMuted, fontSize: 10),
              ),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(height: 78, child: _BmiMiniChart(weights: weights)),
        ),
        const Icon(Icons.chevron_right_rounded, color: pomiMuted, size: 18),
      ],
    ),
  );
}

class _BmiMiniChart extends StatelessWidget {
  const _BmiMiniChart({required this.weights});
  final List<Map<String, dynamic>> weights;

  @override
  Widget build(BuildContext context) {
    final points = weights.where((item) => item['bmi'] is num).toList();
    final visible =
        points.length > 6 ? points.sublist(points.length - 6) : points;
    return CustomPaint(
      painter: _TrendLinePainter(
        visible.map((item) => (item['bmi'] as num).toDouble()).toList(),
        visible.map((_) => '').toList(),
        fractionDigits: 1,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _KeyMetricsSection extends StatelessWidget {
  const _KeyMetricsSection({required this.labs, required this.onOpenTrends});

  final List<Map<String, dynamic>> labs;
  final ValueChanged<String?> onOpenTrends;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeading(title: '近期关键指标', trailing: '异常优先 · 点击查看趋势'),
      const SizedBox(height: 7),
      if (labs.isEmpty)
        const PomiGlassCard(padding: EdgeInsets.all(12), child: Text('暂无已确认指标'))
      else
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.78,
          children:
              labs
                  .take(6)
                  .map(
                    (item) => _MetricSummaryCard(
                      item: item,
                      onTap: () => onOpenTrends(item['metric_id']?.toString()),
                    ),
                  )
                  .toList(),
        ),
    ],
  );
}

class _MetricSummaryCard extends StatelessWidget {
  const _MetricSummaryCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = item['abnormal_status']?.toString();
    final abnormal = status == 'high' || status == 'low';
    final statusText =
        status == 'high'
            ? '偏高'
            : status == 'low'
            ? '偏低'
            : '范围内';
    return PomiGlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 7),
      backgroundColor:
          abnormal ? const Color(0xFFFFF5F3) : const Color(0xFFF7F8F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['item_name']?.toString() ?? '指标',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: pomiMuted, fontSize: 10),
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  color: abnormal ? pomiCoral : pomiSuccess,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '${item['raw_value'] ?? '—'} ${item['raw_unit'] ?? ''}',
            style: TextStyle(
              color: abnormal ? pomiCoral : pomiInk,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  item['sample_date']?.toString() ?? '',
                  style: const TextStyle(color: pomiMuted, fontSize: 9),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: pomiMuted,
                size: 14,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactMedicationSection extends StatelessWidget {
  const _CompactMedicationSection({required this.medicines});
  final List<Map<String, dynamic>> medicines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeading(title: '当前用药', trailing: '${medicines.length} 项'),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: pomiLine),
        ),
        child: Text(
          medicines.isEmpty
              ? '暂无当前用药'
              : medicines
                  .map((item) => item['drug_name']?.toString() ?? '用药')
                  .join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}

class _ReportSourceShortcut extends StatelessWidget {
  const _ReportSourceShortcut({
    required this.labCount,
    required this.cycleCount,
    required this.weightCount,
    required this.sourceCount,
    required this.onTap,
  });
  final int labCount;
  final int cycleCount;
  final int weightCount;
  final int sourceCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.source_outlined, size: 17, color: pomiPurple),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              '报告数据来源',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '$labCount 项检查 · $cycleCount 次经期 · $weightCount 个体重点 · $sourceCount 份材料',
            style: const TextStyle(color: pomiMuted, fontSize: 9),
          ),
          const Icon(Icons.chevron_right_rounded, size: 16, color: pomiMuted),
        ],
      ),
    ),
  );
}

class _BmiTrendChart extends StatefulWidget {
  const _BmiTrendChart({required this.weights});
  final List<Map<String, dynamic>> weights;

  @override
  State<_BmiTrendChart> createState() => _BmiTrendChartState();
}

class _BmiTrendChartState extends State<_BmiTrendChart> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allPoints =
        widget.weights.where((item) => item['bmi'] is num).toList();
    final points =
        allPoints.length <= 8
            ? allPoints
            : allPoints.sublist(allPoints.length - 8);
    final values = points.map((e) => (e['bmi'] as num).toDouble()).toList();
    final labels =
        points
            .map((e) => e['record_date']?.toString().substring(0, 10) ?? '')
            .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final desiredWidth = values.length * 96.0;
        final chartWidth =
            desiredWidth > constraints.maxWidth
                ? desiredWidth
                : constraints.maxWidth;
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: chartWidth > constraints.maxWidth,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: chartWidth,
              height: constraints.maxHeight - 12,
              child: CustomPaint(
                painter: _TrendLinePainter(
                  values,
                  labels,
                  unitLabel: 'BMI',
                  fractionDigits: 1,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter(
    this.values,
    this.labels, {
    this.unitLabel,
    this.fractionDigits = 2,
  });
  final List<double> values;
  final List<String> labels;
  final String? unitLabel;
  final int fractionDigits;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final min = values.reduce((a, b) => a < b ? a : b) - .5;
    final max = values.reduce((a, b) => a > b ? a : b) + .5;
    final chart = Rect.fromLTWH(
      48,
      unitLabel == null ? 12 : 38,
      size.width - 64,
      unitLabel == null ? size.height - 36 : size.height - 62,
    );
    if (unitLabel != null) {
      _drawText(
        canvas,
        unitLabel!,
        const Offset(28, 14),
        const TextStyle(color: pomiMuted, fontSize: 10),
      );
    }
    final grid =
        Paint()
          ..color = const Color(0xFFECEAF0)
          ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = chart.top + chart.height * i / 2;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      final label = (max - (max - min) * i / 2).toStringAsFixed(fractionDigits);
      _drawText(
        canvas,
        label,
        Offset(2, y - 7),
        const TextStyle(color: pomiMuted, fontSize: 11),
      );
    }
    final line =
        Paint()
          ..color = pomiPurple
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x =
          values.length == 1
              ? chart.center.dx
              : chart.left + chart.width * i / (values.length - 1);
      final y = chart.bottom - (values[i] - min) / (max - min) * chart.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = pomiPurple);
    }
    if (values.length > 1) canvas.drawPath(path, line);
    for (var i = 0; i < values.length; i++) {
      final x =
          values.length == 1
              ? chart.center.dx
              : chart.left + chart.width * i / (values.length - 1);
      _drawCenteredText(
        canvas,
        labels[i],
        Offset(x, chart.bottom + 8),
        const TextStyle(color: pomiMuted, fontSize: 10),
        size.width,
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
    double availableWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final left = (center.dx - painter.width / 2).clamp(
      2.0,
      availableWidth - painter.width - 2,
    );
    painter.paint(canvas, Offset(left, center.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.labels != labels ||
      oldDelegate.unitLabel != unitLabel ||
      oldDelegate.fractionDigits != fractionDigits;
}

class _GlucoseTrendChart extends StatefulWidget {
  const _GlucoseTrendChart({required this.points, required this.unit});

  final List<Map<String, dynamic>> points;
  final String unit;

  @override
  State<_GlucoseTrendChart> createState() => _GlucoseTrendChartState();
}

class _GlucoseTrendChartState extends State<_GlucoseTrendChart> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final points = <_GlucosePoint>[];
      for (var i = 0; i < widget.points.length; i++) {
        final point = _GlucosePoint.fromBackend(widget.points[i], i);
        if (point != null) points.add(point);
      }
      final desiredWidth = points.length * 96.0;
      final chartWidth =
          desiredWidth > constraints.maxWidth
              ? desiredWidth
              : constraints.maxWidth;
      return CustomPaint(
        painter: _TrendChartFramePainter(),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: chartWidth > constraints.maxWidth,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: chartWidth,
                height: constraints.maxHeight - 16,
                child: CustomPaint(
                  painter: _GlucoseTrendPainter(points, widget.unit),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _TrendChartFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(18),
    );
    canvas.drawRRect(frame, Paint()..color = const Color(0xFFFCFBFD));
    final border = Path()..addRRect(frame);
    final paint =
        Paint()
          ..color = const Color(0xFFB8B0C0)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
    for (final metric in border.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 5).clamp(0, metric.length)),
          paint,
        );
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartFramePainter oldDelegate) => false;
}

enum _GlucosePointState { high, low, normal, converted, unverified }

class _GlucosePoint {
  const _GlucosePoint({
    required this.value,
    required this.date,
    required this.hospital,
    required this.state,
    this.referenceMin,
    this.referenceMax,
  });

  final double value;
  final String date;
  final String hospital;
  final _GlucosePointState state;
  final double? referenceMin;
  final double? referenceMax;

  static _GlucosePoint? fromBackend(Map<String, dynamic> item, int index) {
    final value = _number(
      item['normalized_value'] ?? item['numeric_value'] ?? item['raw_value'],
    );
    final rawDate = item['date']?.toString();
    if (value == null || rawDate == null || rawDate.isEmpty) return null;
    final originalUnit = item['original_unit']?.toString();
    final normalizedUnit = item['normalized_unit']?.toString();
    final converted =
        originalUnit != null &&
        normalizedUnit != null &&
        originalUnit != normalizedUnit;
    final abnormal = item['abnormal_status']?.toString();
    final comparable = item['comparability']?.toString() != 'incomparable';
    final state =
        !comparable || abnormal == 'unknown'
            ? _GlucosePointState.unverified
            : abnormal == 'high'
            ? _GlucosePointState.high
            : abnormal == 'low'
            ? _GlucosePointState.low
            : converted
            ? _GlucosePointState.converted
            : _GlucosePointState.normal;
    final sourceNumber = item['source_number'] ?? index + 1;
    return _GlucosePoint(
      value: value,
      date: rawDate.length >= 7 ? rawDate.substring(0, 7) : rawDate,
      hospital:
          item['facility']?.toString() ??
          item['hospital_name']?.toString() ??
          '来源 $sourceNumber',
      state: state,
      referenceMin: _number(
        item['normalized_reference_lower'] ?? item['reference_lower'],
      ),
      referenceMax: _number(
        item['normalized_reference_upper'] ?? item['reference_upper'],
      ),
    );
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _GlucoseTrendPainter extends CustomPainter {
  _GlucoseTrendPainter(this.points, this.unit);

  final List<_GlucosePoint> points;
  final String unit;

  double get _minY {
    final values = [
      ...points.map((point) => point.value),
      ...points.map((point) => point.referenceMin).whereType<double>(),
    ];
    if (values.isEmpty) return 3.8;
    final minimum = values.reduce((a, b) => a < b ? a : b);
    return minimum >= 3.8 ? 3.8 : (minimum / .4).floor() * .4;
  }

  double get _maxY {
    final values = [
      ...points.map((point) => point.value),
      ...points.map((point) => point.referenceMax).whereType<double>(),
    ];
    if (values.isEmpty) return 6.2;
    final maximum = values.reduce((a, b) => a > b ? a : b);
    return maximum <= 6.2 ? 6.2 : (maximum / .4).ceil() * .4;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final chart = Rect.fromLTRB(46, 58, size.width - 18, size.height - 72);
    _drawText(
      canvas,
      unit,
      const Offset(28, 25),
      const TextStyle(color: pomiMuted, fontSize: 11),
    );

    final gridPaint =
        Paint()
          ..color = const Color(0xFFE3DFE6)
          ..strokeWidth = 1;
    for (var i = 0; i < 7; i++) {
      final tick = _maxY - (_maxY - _minY) * i / 6;
      final y = _mapY(tick, chart);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _drawRightAlignedText(
        canvas,
        tick.toStringAsFixed(1),
        Offset(chart.left - 8, y - 7),
        const TextStyle(color: pomiMuted, fontSize: 10),
      );
    }

    final offsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x =
          points.length == 1
              ? chart.center.dx
              : chart.left + chart.width * i / (points.length - 1);
      final y = _mapY(point.value, chart);
      offsets.add(Offset(x, y));
      final referenceMin = point.referenceMin;
      final referenceMax = point.referenceMax;
      if (referenceMin != null && referenceMax != null) {
        canvas.drawLine(
          Offset(x, _mapY(referenceMin, chart)),
          Offset(x, _mapY(referenceMax, chart)),
          Paint()
            ..color = const Color(0xFFC8C3CC)
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round,
        );
      } else if (referenceMin ?? referenceMax case final bound?) {
        final boundY = _mapY(bound, chart);
        canvas.drawLine(
          Offset(x - 5, boundY),
          Offset(x + 5, boundY),
          Paint()
            ..color = const Color(0xFFC8C3CC)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final trendPaint =
        Paint()
          ..color = pomiPurple
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke;
    for (var i = 1; i < points.length; i++) {
      if (points[i - 1].state == _GlucosePointState.unverified ||
          points[i].state == _GlucosePointState.unverified) {
        continue;
      }
      _drawDashedPath(
        canvas,
        Path()
          ..moveTo(offsets[i - 1].dx, offsets[i - 1].dy)
          ..lineTo(offsets[i].dx, offsets[i].dy),
        trendPaint,
        dash: 5,
        gap: 5,
      );
    }

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final offset = offsets[i];
      final color = switch (point.state) {
        _GlucosePointState.high => const Color(0xFFB84A4A),
        _GlucosePointState.low => const Color(0xFFB84A4A),
        _GlucosePointState.normal => const Color(0xFF43785B),
        _GlucosePointState.converted => pomiPurple,
        _GlucosePointState.unverified => const Color(0xFF817A88),
      };
      canvas.drawCircle(offset, 7, Paint()..color = Colors.white);
      if (point.state == _GlucosePointState.unverified) {
        canvas.drawCircle(
          offset,
          6,
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      } else {
        canvas.drawCircle(offset, 5.5, Paint()..color = color);
      }

      final suffix = switch (point.state) {
        _GlucosePointState.high => ' ↑',
        _GlucosePointState.low => ' ↓',
        _GlucosePointState.converted => '*',
        _GlucosePointState.unverified => '?',
        _GlucosePointState.normal => '',
      };
      _drawCenteredText(
        canvas,
        '${point.value.toStringAsFixed(1)}$suffix',
        Offset(offset.dx, offset.dy - 27),
        TextStyle(
          color: color,
          fontSize: 11,
          fontWeight:
              point.state == _GlucosePointState.high
                  ? FontWeight.w800
                  : FontWeight.w600,
        ),
        size.width,
      );
      _drawCenteredText(
        canvas,
        point.date,
        Offset(offset.dx, chart.bottom + 25),
        const TextStyle(color: pomiMuted, fontSize: 9),
        size.width,
      );
      _drawCenteredText(
        canvas,
        point.hospital,
        Offset(offset.dx, chart.bottom + 44),
        const TextStyle(color: pomiMuted, fontSize: 9),
        size.width,
      );
    }
  }

  double _mapY(double value, Rect chart) =>
      chart.bottom - (value - _minY) / (_maxY - _minY) * chart.height;

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + dash).clamp(0, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _drawRightAlignedText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width, offset.dy));
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
    double availableWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final left = (center.dx - painter.width / 2).clamp(
      3.0,
      availableWidth - painter.width - 3,
    );
    painter.paint(canvas, Offset(left, center.dy));
  }

  @override
  bool shouldRepaint(covariant _GlucoseTrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.unit != unit;
}

class _GlucoseTrendSection extends StatelessWidget {
  const _GlucoseTrendSection({required this.trend});

  final Map<String, dynamic>? trend;

  @override
  Widget build(BuildContext context) {
    final points = List<Map<String, dynamic>>.from(
      (trend?['points'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final unit = trend?['unit']?.toString() ?? 'mmol/L';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '空腹血糖（FPG）趋势',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text('单位：$unit', style: const TextStyle(color: pomiMuted)),
        const SizedBox(height: 8),
        if (points.isEmpty)
          const PomiGlassCard(
            padding: EdgeInsets.all(15),
            child: Text('暂无可比较的空腹血糖数据'),
          )
        else
          SizedBox(
            height: 350,
            child: _GlucoseTrendChart(points: points, unit: unit),
          ),
      ],
    );
  }
}

class _SelectedLabTrendSection extends StatelessWidget {
  const _SelectedLabTrendSection({required this.trend});

  final Map<String, dynamic> trend;

  @override
  Widget build(BuildContext context) {
    final name =
        trend['metric_name']?.toString() ??
        trend['item_name']?.toString() ??
        '检查指标';
    final unit = trend['unit']?.toString() ?? '';
    final points = List<Map<String, dynamic>>.from(
      (trend['points'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final values = <double>[];
    final labels = <String>[];
    for (final point in points) {
      final value = _trendNumber(
        point['normalized_value'] ??
            point['numeric_value'] ??
            point['raw_value'],
      );
      final date = point['date']?.toString() ?? '';
      if (value == null || date.isEmpty) continue;
      values.add(value);
      labels.add(date.length > 10 ? date.substring(0, 10) : date);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$name趋势',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        if (unit.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('单位：$unit', style: const TextStyle(color: pomiMuted)),
        ],
        const SizedBox(height: 8),
        if (values.isEmpty)
          const PomiGlassCard(
            padding: EdgeInsets.all(15),
            child: Text('暂无可绘制的趋势数据'),
          )
        else
          SizedBox(
            height: 300,
            child: PomiGlassCard(
              padding: const EdgeInsets.all(2),
              child: CustomPaint(
                painter: _TrendLinePainter(
                  values,
                  labels,
                  unitLabel: unit.isEmpty ? null : unit,
                  fractionDigits:
                      values.any((value) => value.abs() >= 10) ? 1 : 2,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    );
  }

  double? _trendNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _ReportTrendLayer extends StatelessWidget {
  const _ReportTrendLayer({
    required this.weights,
    required this.cycles,
    required this.labs,
    required this.glucoseTrend,
    required this.selectedMetricId,
    required this.selectedTrend,
    required this.onSelectMetric,
    required this.onOpenSources,
  });
  final List<Map<String, dynamic>> weights;
  final List<Map<String, dynamic>> cycles;
  final List<Map<String, dynamic>> labs;
  final Map<String, dynamic>? glucoseTrend;
  final String? selectedMetricId;
  final Map<String, dynamic>? selectedTrend;
  final ValueChanged<String> onSelectMetric;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Row(
        children: [
          const Expanded(
            child: Text(
              '完整趋势',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton.icon(
            onPressed: onOpenSources,
            icon: const Icon(Icons.source_outlined, size: 16),
            label: const Text('原始数据'),
          ),
        ],
      ),
      const Text(
        '一次只查看一个指标；点击下方数据节点可继续追溯来源。',
        style: TextStyle(color: pomiMuted, fontSize: 11),
      ),
      const SizedBox(height: 12),
      if (selectedMetricId == 'cycle')
        _CycleTrendDetail(cycles: cycles, onOpenSources: onOpenSources)
      else if (selectedMetricId == 'weight')
        _WeightTrendDetail(weights: weights, onOpenSources: onOpenSources)
      else if (selectedTrend != null) ...[
        if (selectedMetricId == 'glucose')
          _GlucoseTrendSection(trend: glucoseTrend)
        else
          _SelectedLabTrendSection(trend: selectedTrend!),
        const SizedBox(height: 10),
        _LabTrendPoints(trend: selectedTrend!, onOpenSources: onOpenSources),
      ] else
        _TrendMetricIndex(
          labs: labs,
          hasCycles: cycles.isNotEmpty,
          hasWeights: weights.isNotEmpty,
          onSelectMetric: onSelectMetric,
        ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
      children: children,
    );
  }
}

class _TrendMetricIndex extends StatelessWidget {
  const _TrendMetricIndex({
    required this.labs,
    required this.hasCycles,
    required this.hasWeights,
    required this.onSelectMetric,
  });

  final List<Map<String, dynamic>> labs;
  final bool hasCycles;
  final bool hasWeights;
  final ValueChanged<String> onSelectMetric;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, String)>[
      if (hasCycles) ('cycle', '经期周期', '查看周期时长与月经记录'),
      if (hasWeights) ('weight', 'BMI / 体重', '查看完整 BMI 趋势'),
      ...labs.map(
        (item) => (
          item['metric_id']?.toString() ?? '',
          item['item_name']?.toString() ?? '检查指标',
          '${item['raw_value'] ?? '—'} ${item['raw_unit'] ?? ''}',
        ),
      ),
    ].where((item) => item.$1.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(title: '选择指标'),
        const SizedBox(height: 7),
        PomiGlassCard(
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFFF7F6F8),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                ListTile(
                  dense: true,
                  title: Text(
                    items.elementAt(i).$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    items.elementAt(i).$3,
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: pomiMuted,
                  ),
                  onTap: () => onSelectMetric(items.elementAt(i).$1),
                ),
                if (i != items.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CycleTrendDetail extends StatelessWidget {
  const _CycleTrendDetail({required this.cycles, required this.onOpenSources});

  final List<Map<String, dynamic>> cycles;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final latest = cycles.isEmpty ? null : cycles.last;
    int? completedLength;
    for (final cycle in cycles.reversed) {
      if (cycle['cycle_length_days'] is int) {
        completedLength = cycle['cycle_length_days'] as int;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(title: '经期周期趋势', trailing: '点击记录查看来源'),
        const SizedBox(height: 7),
        PomiGlassCard(
          padding: const EdgeInsets.all(12),
          backgroundColor: const Color(0xFFF7F6F8),
          child: SizedBox(
            height: 72,
            width: double.infinity,
            child: CustomPaint(
              painter: _CycleSundialPainter(
                cycleLengthDays: completedLength ?? 56,
                periodLengthDays: latest?['duration_days'] as int? ?? 0,
                startLabel: _RecentCycleCard._monthDay(
                  latest?['start_date']?.toString(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        PomiGlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children:
                cycles.reversed.take(8).map((item) {
                  final range =
                      '${item['start_date'] ?? '—'} 至 ${item['end_date'] ?? '进行中'}';
                  final details =
                      '周期 ${item['cycle_length_days'] ?? '—'} 天 · 月经 ${item['duration_days'] ?? '—'} 天';
                  return ListTile(
                    dense: true,
                    title: Text(
                      range,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      details,
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: const Icon(
                      Icons.source_outlined,
                      size: 17,
                      color: pomiPurple,
                    ),
                    onTap: onOpenSources,
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }
}

class _WeightTrendDetail extends StatelessWidget {
  const _WeightTrendDetail({
    required this.weights,
    required this.onOpenSources,
  });

  final List<Map<String, dynamic>> weights;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeading(title: 'BMI / 体重趋势', trailing: '点击记录查看来源'),
      const SizedBox(height: 7),
      SizedBox(
        height: 240,
        child: CustomPaint(
          painter: _TrendChartFramePainter(),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _BmiTrendChart(weights: weights),
          ),
        ),
      ),
      const SizedBox(height: 9),
      PomiGlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          children:
              weights.reversed
                  .take(8)
                  .map(
                    (item) => ListTile(
                      dense: true,
                      title: Text(
                        item['record_date']?.toString() ?? '—',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'BMI ${item['bmi'] ?? '—'}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${item['weight_kg'] ?? '—'} kg',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.source_outlined,
                            size: 17,
                            color: pomiPurple,
                          ),
                        ],
                      ),
                      onTap: onOpenSources,
                    ),
                  )
                  .toList(),
        ),
      ),
    ],
  );
}

class _LabTrendPoints extends StatelessWidget {
  const _LabTrendPoints({required this.trend, required this.onOpenSources});

  final Map<String, dynamic> trend;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final points = List<Map<String, dynamic>>.from(
      (trend['points'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    return PomiGlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children:
            points.reversed.take(8).map((point) {
              final value =
                  point['normalized_value'] ??
                  point['numeric_value'] ??
                  point['raw_value'] ??
                  '—';
              final unit =
                  point['normalized_unit'] ??
                  point['original_unit'] ??
                  trend['unit'] ??
                  '';
              final abnormal =
                  point['abnormal_status'] == 'high' ||
                  point['abnormal_status'] == 'low';
              return ListTile(
                dense: true,
                title: Text(
                  point['date']?.toString() ?? '—',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  point['facility']?.toString() ?? '点击查看原始报告',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$value $unit',
                      style: TextStyle(
                        color: abnormal ? pomiCoral : pomiInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.source_outlined,
                      size: 17,
                      color: pomiPurple,
                    ),
                  ],
                ),
                onTap: onOpenSources,
              );
            }).toList(),
      ),
    );
  }
}

class _ReportSourceLayer extends StatelessWidget {
  const _ReportSourceLayer({required this.sourceGroups});
  final Map<String, List<Map<String, dynamic>>> sourceGroups;

  @override
  Widget build(BuildContext context) {
    final nonEmpty =
        sourceGroups.entries.where((entry) => entry.value.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
      children: [
        const Text(
          '报告数据来源',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          '原始数据来源存证 · 仅供参考 · 不构成诊断',
          style: TextStyle(color: pomiMuted, height: 1.5),
        ),
        const SizedBox(height: 16),
        if (nonEmpty.isEmpty)
          const _EmptyState(icon: Icons.source_outlined, text: '当前报告没有医疗材料来源')
        else
          ...nonEmpty.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PomiGlassCard(
                child: ExpansionTile(
                  title: Text(
                    '${entry.key}（${entry.value.length}）',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  children:
                      entry.value.map((item) {
                        final label =
                            item['item_name'] ??
                            item['drug_name'] ??
                            item['examination_name'] ??
                            item['source_type'] ??
                            item['hospital_name'] ??
                            entry.key;
                        return ListTile(
                          leading: const Icon(
                            Icons.description_outlined,
                            color: pomiPurple,
                          ),
                          title: Text(label.toString()),
                          subtitle: Text(
                            '材料 ${_shortId(item['document_id'])} · 修订 ${_shortId(item['document_revision_id'])}',
                          ),
                        );
                      }).toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _shortId(dynamic value) {
    final text = value?.toString() ?? '无';
    return text.length > 8 ? '${text.substring(0, 8)}…' : text;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: pomiSecondaryText),
          const SizedBox(height: 12),
          Text(text),
        ],
      ),
    );
  }
}
