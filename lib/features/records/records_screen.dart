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
      VisitRecordCategory.imaging => (
        '影像报告',
        const Color(0xFFEAF2FF),
        const Color(0xFF3D70B2),
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
    final records = Map<String, dynamic>.from(
      snapshot['records'] as Map? ?? const {},
    );
    final medicationEvents = List<Map<String, dynamic>>.from(
      (records['medication_events'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
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
        if (value['source_type'] == null) {
          for (final event in medicationEvents.reversed) {
            if (event['medication_id'] == value['id'] &&
                event['source_type'] != null) {
              value['source_type'] = event['source_type'];
              break;
            }
          }
        }
        value['report_date'] = widget.report['generated_at'];
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
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'POMI'),
                            TextSpan(
                              text: '报告',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          color: pomiPurple,
                          fontSize: 20,
                          height: 28 / 22,
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
                  labTrends: labTrends,
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
                  reportDate:
                      _tryReportDate(widget.report['generated_at']) ??
                      DateTime.now(),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: pomiLine)),
    ),
    child: Row(
      children: [
        _ReportLayerTab(
          label: '摘要',
          selected: layer == 0,
          onTap: () => onSelect(0),
        ),
        _ReportLayerTab(
          label: '趋势',
          selected: layer == 1,
          onTap: () => onSelect(1),
        ),
        _ReportLayerTab(
          label: '原始数据',
          selected: layer == 2,
          onTap: () => onSelect(2),
        ),
      ],
    ),
  );
}

class _ReportLayerTab extends StatelessWidget {
  const _ReportLayerTab({
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
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? pomiPurple : pomiMuted,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: selected ? 28 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: selected ? pomiPurple : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

extension on DateTime {
  String get reportDateLabel =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  String get reportMonthLabel => '$year-${month.toString().padLeft(2, '0')}';
}

DateTime? _tryReportDate(dynamic raw) {
  final parsed = DateTime.tryParse(raw?.toString() ?? '');
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeading(title: '本次关注'),
      const SizedBox(height: 6),
      ...lines.map(
        (line) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(line, style: const TextStyle(fontSize: 12, height: 1.35)),
        ),
      ),
    ],
  );
}

class _ReportSummaryLayer extends StatelessWidget {
  const _ReportSummaryLayer({
    required this.report,
    required this.summary,
    required this.medicines,
    required this.labs,
    required this.labTrends,
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
  final List<Map<String, dynamic>> labTrends;
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

  Map<String, dynamic> get _profile =>
      Map<String, dynamic>.from(summary['profile'] as Map? ?? const {});

  DateTime get _reportDate =>
      _tryReportDate(report['generated_at']) ?? DateTime.now();

  int? get _age {
    final birthDate = _tryReportDate(_profile['birth_date']);
    if (birthDate == null) return null;
    var age = _reportDate.year - birthDate.year;
    if (_reportDate.month < birthDate.month ||
        (_reportDate.month == birthDate.month &&
            _reportDate.day < birthDate.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }

  String get _dataRange {
    final dates = <DateTime>[];
    for (final cycle in cycles) {
      final date = _tryReportDate(cycle['start_date']);
      if (date != null) dates.add(date);
    }
    for (final weight in weights) {
      final date = _tryReportDate(weight['record_date']);
      if (date != null) dates.add(date);
    }
    for (final trend in labTrends) {
      for (final point in trend['points'] as List? ?? const []) {
        final date = _tryReportDate((point as Map)['date']);
        if (date != null) dates.add(date);
      }
    }
    if (dates.isEmpty) return '数据范围未记录';
    dates.sort();
    return '数据 ${dates.first.reportMonthLabel} ~ ${dates.last.reportMonthLabel}';
  }

  String get _diagnosisLine {
    final diagnosisYear = int.tryParse(
      _profile['diagnosis_year']?.toString() ?? '',
    );
    final duration =
        diagnosisYear == null
            ? null
            : (_reportDate.year - diagnosisYear).clamp(0, 99);
    final diagnosisText =
        duration == null ? '已确诊 PCOS · 确诊时间未记录' : '已确诊 PCOS $duration 年';
    return '$diagnosisText · 当前无备孕计划';
  }

  String get _cycleAttentionLine {
    final start = _tryReportDate(_latestCycle?['start_date']);
    if (start == null) return '末次月经未记录 · 周期天数未记录';
    final day = _reportDate.difference(start).inDays + 1;
    return '末次月经 ${start.reportDateLabel} · 周期第 ${day < 1 ? 1 : day} 天';
  }

  String get _abnormalAttentionLine {
    final abnormal =
        labs.where((item) {
            final status = item['abnormal_status']?.toString();
            return status == 'high' || status == 'low';
          }).toList()
          ..sort((a, b) {
            final aDate = _tryReportDate(a['sample_date']);
            final bDate = _tryReportDate(b['sample_date']);
            return (bDate ?? DateTime(0)).compareTo(aDate ?? DateTime(0));
          });
    if (abnormal.isEmpty) {
      return '近期已确认指标未见超出报告参考范围';
    }
    final descriptions = abnormal.take(2).map((item) {
      final status = item['abnormal_status'] == 'high' ? '↑' : '↓';
      final date = _tryReportDate(item['sample_date']);
      final days =
          date == null
              ? null
              : _reportDate.difference(date).inDays.clamp(0, 9999);
      final value =
          item['normalized_value'] ??
          item['raw_value'] ??
          item['numeric_value'] ??
          '—';
      final unit =
          item['normalized_unit'] ??
          item['raw_unit'] ??
          item['original_unit'] ??
          '';
      final facility = item['facility'] ?? item['hospital_name'] ?? '医院未记录';
      return '${item['item_name'] ?? '指标'} $value $unit $status｜${days == null ? '日期未记录' : '$days 天前'}｜$facility';
    });
    return '近期异常：${descriptions.join('；')}';
  }

  String get _medicationAttentionLine {
    if (medicines.isEmpty) return '当前用药：暂无记录';
    return '当前用药：${medicines.map((item) => item['drug_name'] ?? '用药').join('、')}';
  }

  List<String> get _attentionLines => [
    _diagnosisLine,
    _cycleAttentionLine,
    _abnormalAttentionLine,
    _medicationAttentionLine,
  ];

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

  int? get _currentCycleDays {
    final start = _tryReportDate(_latestCycle?['start_date']);
    if (start == null) return null;
    final days = _reportDate.difference(start).inDays + 1;
    return days < 1 ? 1 : days;
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
        name: _profile['nickname']?.toString() ?? '未设置姓名',
        age: _age,
        height: _profile['height_cm'],
        weight: _weightSummary['latest_weight_kg'],
        dataRange: _dataRange,
      ),
      const SizedBox(height: 12),
      _CompactTextSection(
        title: '患者自述',
        text: summary['patient_statement']?.toString() ?? '未填写',
      ),
      const SizedBox(height: 12),
      _AttentionSection(lines: _attentionLines),
      const SizedBox(height: 14),
      const _SectionHeading(title: '近期基础信息', trailing: '点击查看完整趋势'),
      const SizedBox(height: 7),
      KeyedSubtree(
        key: cycleSectionKey,
        child: _RecentCycleCard(
          cycleLengthDays: _latestCompletedCycleLength,
          periodLengthDays: _latestCycle?['duration_days'] as int?,
          periodRange: _latestPeriodRange,
          currentStartDate: _latestCycle?['start_date']?.toString(),
          currentCycleDays: _currentCycleDays,
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
    required this.age,
    required this.height,
    required this.weight,
    required this.dataRange,
  });

  final String name;
  final int? age;
  final dynamic height;
  final dynamic weight;
  final String dataRange;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: pomiLine)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$name · ${age ?? '—'} 岁 · ${height ?? '—'} cm · ${weight ?? '—'} kg',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(dataRange, style: const TextStyle(color: pomiMuted, fontSize: 11)),
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
    required this.currentCycleDays,
    required this.onTap,
  });

  final int? cycleLengthDays;
  final int? periodLengthDays;
  final String periodRange;
  final String? currentStartDate;
  final int? currentCycleDays;
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
              cycleLengthDays: currentCycleDays ?? cycleLengthDays ?? 56,
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
    final roundedDays = (cycleLengthDays + 6) ~/ 7 * 7;
    final maxDays = roundedDays < 56 ? 56 : roundedDays;
    final grid = Paint()..color = const Color(0xFFE7E4EB);
    for (var day = 0; day <= maxDays; day += 7) {
      final x = left + (right - left) * day / maxDays;
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
        left + (right - left) * periodLengthDays.clamp(0, maxDays) / maxDays;
    final period =
        Paint()
          ..color = pomiPurple
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(periodEnd, y), period);
    final cycleEnd =
        left + (right - left) * cycleLengthDays.clamp(1, maxDays) / maxDays;
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
      if (medicines.isEmpty)
        const _MedicationEmptyState()
      else
        ...medicines.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _MedicationSummaryTile(item: item),
          ),
        ),
    ],
  );
}

class _MedicationEmptyState extends StatelessWidget {
  const _MedicationEmptyState();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F6F8),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: pomiLine),
    ),
    child: const Text('暂无当前用药', style: TextStyle(fontSize: 12)),
  );
}

class _MedicationSummaryTile extends StatelessWidget {
  const _MedicationSummaryTile({required this.item});

  final Map<String, dynamic> item;

  bool get _isMedicalOrder => const {
    'medical_order',
    'outpatient_record',
  }.contains(item['source_type']?.toString());

  double? get _completion {
    final value = item['completion_percent'];
    if (value is! num) return null;
    return value.toDouble().clamp(0, 100);
  }

  String get _usage {
    final parts = <String>[
      if ((item['route']?.toString() ?? '').isNotEmpty)
        item['route'].toString(),
      if ((item['frequency']?.toString() ?? '').isNotEmpty)
        item['frequency'].toString(),
      if ((item['dosage_text']?.toString() ?? '').isNotEmpty)
        item['dosage_text'].toString(),
    ];
    return parts.isEmpty ? '服用方式未记录' : parts.join(' · ');
  }

  String get _patientMedicationDuration {
    final start = _tryReportDate(item['start_date']);
    final end = _tryReportDate(item['report_date']) ?? DateTime.now();
    if (start == null) return '开始日期未记录 · 已服用天数未记录';
    final days = end.difference(start).inDays + 1;
    return '始于 ${start.reportDateLabel} · 已服用 ${days < 1 ? 1 : days} 天';
  }

  @override
  Widget build(BuildContext context) {
    final completion = _completion;
    final taken = item['taken_units'];
    final planned = item['planned_total_units'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F6F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pomiLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['drug_name']?.toString() ?? '用药',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _isMedicalOrder ? '医嘱用药' : '患者自用',
                style: const TextStyle(color: pomiMuted, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(_usage, style: const TextStyle(color: pomiMuted, fontSize: 10)),
          if (_isMedicalOrder) ...[
            const SizedBox(height: 6),
            if (completion == null)
              const Text(
                '完成率待后端同步',
                style: TextStyle(color: pomiMuted, fontSize: 10),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: completion / 100,
                        backgroundColor: const Color(0xFFE5E0EA),
                        color: pomiPurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '完成率 ${completion.round()}%',
                    style: const TextStyle(
                      color: pomiPurple,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (taken is num && planned is num)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '已服用 ${taken.toInt()} / 疗程 ${planned.toInt()} 颗',
                    style: const TextStyle(color: pomiMuted, fontSize: 9),
                  ),
                ),
            ],
          ] else ...[
            const SizedBox(height: 3),
            Text(
              _patientMedicationDuration,
              style: const TextStyle(color: pomiMuted, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
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

class _BmiTrendChart extends StatelessWidget {
  const _BmiTrendChart({required this.weights});
  final List<Map<String, dynamic>> weights;

  @override
  Widget build(BuildContext context) {
    final allPoints = weights.where((item) => item['bmi'] is num).toList();
    final points =
        allPoints.length <= 6
            ? allPoints
            : allPoints.sublist(allPoints.length - 6);
    final values = points.map((e) => (e['bmi'] as num).toDouble()).toList();
    final labels =
        points
            .map((e) => e['record_date']?.toString().substring(0, 10) ?? '')
            .toList();
    return CustomPaint(
      painter: _TrendLinePainter(
        values,
        labels,
        unitLabel: 'BMI',
        fractionDigits: 1,
      ),
      child: const SizedBox.expand(),
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

class _GlucoseTrendChart extends StatelessWidget {
  const _GlucoseTrendChart({required this.points, required this.unit});

  final List<Map<String, dynamic>> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final parsedPoints = <_GlucosePoint>[];
    for (var i = 0; i < points.length; i++) {
      final point = _GlucosePoint.fromBackend(points[i], i);
      if (point != null) parsedPoints.add(point);
    }
    final visiblePoints =
        parsedPoints.length <= 6
            ? parsedPoints
            : parsedPoints.sublist(parsedPoints.length - 6);
    return CustomPaint(
      painter: _TrendChartFramePainter(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: CustomPaint(
          painter: _GlucoseTrendPainter(visiblePoints, unit),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
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
            height: 230,
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
    required this.reportDate,
    required this.weights,
    required this.cycles,
    required this.labs,
    required this.glucoseTrend,
    required this.selectedMetricId,
    required this.selectedTrend,
    required this.onSelectMetric,
    required this.onOpenSources,
  });
  final DateTime reportDate;
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
        _CycleTrendDetail(cycles: cycles, reportDate: reportDate)
      else if (selectedMetricId == 'weight')
        _WeightTrendDetail(weights: weights)
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
  const _CycleTrendDetail({required this.cycles, required this.reportDate});

  final List<Map<String, dynamic>> cycles;
  final DateTime reportDate;

  @override
  Widget build(BuildContext context) {
    final rows = _CycleChartRow.fromCycles(cycles, reportDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(title: '经期周期趋势', trailing: '当前周期 + 近期 5 个完整周期'),
        const SizedBox(height: 7),
        PomiGlassCard(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          backgroundColor: const Color(0xFFF7F6F8),
          child:
              rows.isEmpty
                  ? const Text('暂无经期记录')
                  : _CycleHistoryChart(rows: rows),
        ),
      ],
    );
  }
}

class _CycleChartRow {
  const _CycleChartRow({
    required this.label,
    required this.dateLabel,
    required this.periodDays,
    required this.totalDays,
    required this.current,
  });

  final String label;
  final String dateLabel;
  final int periodDays;
  final int totalDays;
  final bool current;

  static List<_CycleChartRow> fromCycles(
    List<Map<String, dynamic>> cycles,
    DateTime reportDate,
  ) {
    if (cycles.isEmpty) return const [];
    final sorted = [...cycles]..sort(
      (a, b) => (a['start_date'] ?? '').toString().compareTo(
        (b['start_date'] ?? '').toString(),
      ),
    );
    final latest = sorted.last;
    final latestStart = _tryReportDate(latest['start_date']);
    final currentDays =
        latestStart == null ? 1 : reportDate.difference(latestStart).inDays + 1;
    final completed =
        sorted
            .take(sorted.length - 1)
            .where((item) => item['cycle_length_days'] is num)
            .toList()
            .reversed
            .take(5)
            .toList();
    return [
      _CycleChartRow(
        label: '当前周期',
        dateLabel: _RecentCycleCard._monthDay(latest['start_date']?.toString()),
        periodDays: (latest['duration_days'] as num?)?.toInt() ?? 0,
        totalDays: currentDays < 1 ? 1 : currentDays,
        current: true,
      ),
      for (var i = 0; i < completed.length; i++)
        _CycleChartRow(
          label: '前 ${i + 1} 周期',
          dateLabel: _RecentCycleCard._monthDay(
            completed[i]['start_date']?.toString(),
          ),
          periodDays: (completed[i]['duration_days'] as num?)?.toInt() ?? 0,
          totalDays: (completed[i]['cycle_length_days'] as num?)?.toInt() ?? 1,
          current: false,
        ),
    ];
  }
}

class _CycleHistoryChart extends StatelessWidget {
  const _CycleHistoryChart({required this.rows});

  final List<_CycleChartRow> rows;

  @override
  Widget build(BuildContext context) {
    final longest = rows
        .map((row) => row.totalDays)
        .reduce((a, b) => a > b ? a : b);
    final roundedDays = (longest + 6) ~/ 7 * 7;
    final maxDays = roundedDays < 56 ? 56 : roundedDays;
    final ticks = [for (var day = 0; day <= maxDays; day += 7) day];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 70),
          child: Row(
            children: [
              for (final tick in ticks)
                Expanded(
                  child: Text(
                    '$tick',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: pomiMuted, fontSize: 8),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ...rows.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 66,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.label,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        row.dateLabel,
                        style: const TextStyle(color: pomiMuted, fontSize: 8),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 26,
                    child: CustomPaint(
                      painter: _CycleHistoryRowPainter(
                        row: row,
                        maxDays: maxDays,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CycleHistoryRowPainter extends CustomPainter {
  const _CycleHistoryRowPainter({required this.row, required this.maxDays});

  final _CycleChartRow row;
  final int maxDays;

  @override
  void paint(Canvas canvas, Size size) {
    const y = 9.0;
    final grid =
        Paint()
          ..color = const Color(0xFFE7E4EB)
          ..strokeWidth = 1;
    for (var day = 0; day <= maxDays; day += 7) {
      final x = size.width * day / maxDays;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final periodEnd = size.width * row.periodDays.clamp(0, maxDays) / maxDays;
    canvas.drawLine(
      const Offset(0, y),
      Offset(periodEnd, y),
      Paint()
        ..color = pomiPurple
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    final cycleEnd = size.width * row.totalDays.clamp(1, maxDays) / maxDays;
    final remaining =
        Paint()
          ..color =
              row.current
                  ? pomiPurple.withValues(alpha: .38)
                  : const Color(0xFFC8C1CD)
          ..strokeWidth = 1.5;
    for (var x = periodEnd + 5; x < cycleEnd; x += 7) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + 4).clamp(x, cycleEnd), y),
        remaining,
      );
    }
    canvas.drawCircle(Offset(cycleEnd, y), 2.5, Paint()..color = pomiPurple);
    final label = row.current ? '进行中' : '${row.totalDays} 天';
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: row.current ? pomiPurple : pomiMuted,
          fontSize: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset((cycleEnd + 4).clamp(0, size.width - text.width), y + 5),
    );
  }

  @override
  bool shouldRepaint(covariant _CycleHistoryRowPainter oldDelegate) =>
      oldDelegate.row != row || oldDelegate.maxDays != maxDays;
}

class _WeightTrendDetail extends StatelessWidget {
  const _WeightTrendDetail({required this.weights});

  final List<Map<String, dynamic>> weights;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionHeading(title: 'BMI / 体重趋势', trailing: '近期 6 个可比数据点'),
      const SizedBox(height: 7),
      SizedBox(
        height: 205,
        child: CustomPaint(
          painter: _TrendChartFramePainter(),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _BmiTrendChart(weights: weights),
          ),
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
