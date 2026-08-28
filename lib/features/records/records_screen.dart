import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../upload/certification_repository.dart';
import '../upload/upload_screen.dart';

final recordsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final values = await Future.wait([
    ref.read(apiClientProvider).get('/api/documents'),
    ref.read(apiClientProvider).get('/api/reports'),
  ]);
  return {'documents': values[0], 'reports': values[1]};
});

class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({this.initialTab = 0, super.key});

  final int initialTab;

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
            if (smokeMode) {
              return ReportViewer(report: _smokeDashboardReport);
            }
            return _ReportsList(reports: reports);
          }
          if (smokeMode) return const _VisitRecordsPage();
          return _DocumentsList(documents: documents);
        },
      ),
    );
  }
}

const _smokeDashboardReport = <String, dynamic>{
  'report_id': 'smoke-report',
  'generated_at': '2026-08-28T08:30:00Z',
  'snapshot': {
    'summary': {
      'profile': {'nickname': '林晓晴'},
      'patient_note_text': '近 3 个月月经周期不规律，最近间隔达 51 天。',
      'disclaimers': ['仅供参考，不构成诊断或治疗建议'],
      'current_medications': [],
    },
    'trends': {
      'labs': [
        {
          'item_name': '空腹血糖',
          'points': [
            {
              'original_item_name': '空腹血糖',
              'date': '2026-08-25',
              'raw_value': 5.6,
              'raw_unit': 'mmol/L',
            },
          ],
        },
        {
          'item_name': 'HbA1c',
          'points': [
            {
              'original_item_name': 'HbA1c',
              'date': '2026-08-25',
              'raw_value': 5.5,
              'raw_unit': '%',
            },
          ],
        },
        {
          'item_name': '总睾酮',
          'points': [
            {
              'original_item_name': '总睾酮',
              'date': '2026-08-24',
              'raw_value': 0.9,
              'raw_unit': 'ng/mL',
            },
          ],
        },
        {
          'item_name': '甘油三酯',
          'points': [
            {
              'original_item_name': '甘油三酯',
              'date': '2026-06-20',
              'raw_value': 1.4,
              'raw_unit': 'mmol/L',
            },
          ],
        },
      ],
      'weights': [
        {'record_date': '2026-08-02', 'weight_kg': 68.5},
        {'record_date': '2026-08-08', 'weight_kg': 67.2},
        {'record_date': '2026-08-15', 'weight_kg': 66.5},
        {'record_date': '2026-08-22', 'weight_kg': 67.3},
        {'record_date': '2026-08-28', 'weight_kg': 67.5},
      ],
      'cycles': [
        {'start_date': '2026-08-06', 'end_date': '2026-08-09'},
        {'start_date': '2026-07-01', 'end_date': '2026-07-05'},
      ],
    },
  },
  'sources': [],
};

class _VisitRecordsPage extends StatelessWidget {
  const _VisitRecordsPage();

  static const visits = [
    _VisitRecordData(
      date: '2026-08-26',
      status: '来源签署已记录｜模拟',
      statusTone: _VisitStatusTone.purple,
      hospital: '模拟医院 B · 生殖内分泌科 · 陈医生',
      rows: [
        _VisitRecordRowData(
          title: '化验单',
          tag: '化验/检测',
          tone: _VisitTagTone.purple,
          trailing: '采样 2026-08-25',
        ),
        _VisitRecordRowData(
          title: '医嘱',
          tag: '医嘱/处方',
          tone: _VisitTagTone.mint,
          trailing: '2026-08-26',
        ),
      ],
    ),
    _VisitRecordData(
      date: '2026-07-12',
      status: '来源核验申请中',
      statusTone: _VisitStatusTone.blue,
      hospital: '模拟医院 A · 妇科 · 李医生',
      rows: [
        _VisitRecordRowData(
          title: '门诊病历',
          tag: '门诊病历',
          tone: _VisitTagTone.amber,
        ),
        _VisitRecordRowData(
          title: '医嘱',
          tag: '医嘱/处方',
          tone: _VisitTagTone.mint,
        ),
      ],
    ),
    _VisitRecordData(
      date: '2026-06-20',
      status: '患者上传｜来源未核验',
      statusTone: _VisitStatusTone.gray,
      hospital: '模拟医院 A · 妇科 · 李医生 · 就诊前检测',
      rows: [
        _VisitRecordRowData(
          title: '化验单',
          tag: '化验/检测',
          tone: _VisitTagTone.purple,
        ),
      ],
    ),
    _VisitRecordData(
      date: '2026-02-08',
      note: '* 此数据超过 6 个月，仅供参考',
      hospital: '模拟医院 A · 妇科 · 李医生',
      rows: [
        _VisitRecordRowData(
          title: '门诊病历',
          tag: '门诊病历',
          tone: _VisitTagTone.amber,
        ),
      ],
    ),
    _VisitRecordData(
      date: '2025-12-14',
      note: '* 此数据超过 6 个月，仅供参考',
      hospital: '模拟医院 C · 内分泌科 · 周医生',
      rows: [
        _VisitRecordRowData(
          title: '化验单',
          tag: '化验/检测',
          tone: _VisitTagTone.purple,
        ),
      ],
    ),
  ];

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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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

enum _VisitStatusTone { purple, blue, gray }

enum _VisitTagTone { purple, mint, amber }

class _VisitRecordData {
  const _VisitRecordData({
    required this.date,
    required this.hospital,
    required this.rows,
    this.status,
    this.statusTone = _VisitStatusTone.gray,
    this.note,
  });

  final String date;
  final String hospital;
  final List<_VisitRecordRowData> rows;
  final String? status;
  final _VisitStatusTone statusTone;
  final String? note;
}

class _VisitRecordRowData {
  const _VisitRecordRowData({
    required this.title,
    required this.tag,
    required this.tone,
    this.trailing,
  });

  final String title;
  final String tag;
  final _VisitTagTone tone;
  final String? trailing;
}

class _VisitRecordCard extends StatelessWidget {
  const _VisitRecordCard({required this.visit});

  final _VisitRecordData visit;

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
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
                          if (visit.status != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: _VisitStatusBadge(
                                text: visit.status!,
                                tone: visit.statusTone,
                              ),
                            ),
                          ],
                          if (visit.note != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                visit.note!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      _VisitMetadataFields(value: visit.hospital),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: pomiSecondaryText),
              ],
            ),
          ),
          const Divider(height: 1, color: pomiLine),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              children: [
                for (var index = 0; index < visit.rows.length; index++) ...[
                  _VisitRecordRow(row: visit.rows[index]),
                  if (index != visit.rows.length - 1)
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
  const _VisitMetadataFields({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final fields = value
        .split(' · ')
        .map((field) => field.trim())
        .where((field) => field.isNotEmpty)
        .toList(growable: false);
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        for (final field in fields)
          Text(field, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _VisitStatusBadge extends StatelessWidget {
  const _VisitStatusBadge({required this.text, required this.tone});

  final String text;
  final _VisitStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      _VisitStatusTone.purple => (
        pomiPurple.withValues(alpha: .10),
        pomiPurple,
      ),
      _VisitStatusTone.blue => (
        const Color(0xFFE4F1FF),
        const Color(0xFF2F81C5),
      ),
      _VisitStatusTone.gray => (const Color(0xFFF1F0F3), pomiSecondaryText),
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

  final _VisitRecordRowData row;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (row.tone) {
      _VisitTagTone.purple => (pomiPurple.withValues(alpha: .09), pomiPurple),
      _VisitTagTone.mint => (
        pomiMint.withValues(alpha: .12),
        const Color(0xFF169F91),
      ),
      _VisitTagTone.amber => (const Color(0xFFFFF2D9), const Color(0xFFC78519)),
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
            row.tag,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (row.trailing != null) ...[
          const Spacer(),
          Text(row.trailing!, style: Theme.of(context).textTheme.bodySmall),
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
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
                          fontSize: 17,
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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
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
  const ReportViewer({required this.report, super.key});

  final Map<String, dynamic> report;

  @override
  ConsumerState<ReportViewer> createState() => _ReportViewerState();
}

class _ReportViewerState extends ConsumerState<ReportViewer> {
  int _layer = 0;

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
    final labs = List<Map<String, dynamic>>.from(
      (trends['labs'] as List? ?? const []).expand((group) {
        final value = Map<String, dynamic>.from(group as Map);
        return (value['points'] as List? ?? const []).map((item) {
          final point = Map<String, dynamic>.from(item as Map);
          point['item_name'] = point['original_item_name'];
          point['sample_date'] = point['date'];
          point['raw_unit'] = point['original_unit'];
          return point;
        });
      }),
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
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
                  weights: weights,
                  cycleCount: cycles.length,
                  weightCount: weights.length,
                  sourceCount: sourceGroups['报告来源']!.length,
                  medicalBoundary: (summary['disclaimers'] as List? ?? const [])
                      .join('\n'),
                ),
                _ReportTrendLayer(
                  weights: weights,
                  cycles: cycles,
                  labs: labs,
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

class _ReportSummaryLayer extends StatelessWidget {
  const _ReportSummaryLayer({
    required this.report,
    required this.summary,
    required this.medicines,
    required this.labs,
    required this.weights,
    required this.cycleCount,
    required this.weightCount,
    required this.sourceCount,
    required this.medicalBoundary,
  });
  final Map<String, dynamic> report;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> medicines;
  final List<Map<String, dynamic>> labs;
  final List<Map<String, dynamic>> weights;
  final String medicalBoundary;
  final int cycleCount;
  final int weightCount;
  final int sourceCount;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
    children: [
      const Text(
        '基本信息',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      PomiGlassCard(
        padding: EdgeInsets.all(15),
        backgroundColor: const Color(0xFFF3F3F5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(summary['profile'] as Map?)?['nickname'] ?? '未设置姓名'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '身高 ${(summary['profile'] as Map?)?['height_cm'] ?? '—'} cm',
              style: const TextStyle(color: pomiMuted),
            ),
            Text(
              '体重 ${(summary['profile'] as Map?)?['weight_kg'] ?? '—'} kg',
              style: const TextStyle(color: pomiMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        '患者自述',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      PomiGlassCard(
        onTap:
            () => showDialog<void>(
              context: context,
              builder:
                  (dialogContext) => AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text('患者自述'),
                    content: SingleChildScrollView(
                      child: Text(
                        summary['patient_statement']?.toString() ?? '未填写',
                        style: const TextStyle(height: 1.55),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
            ),
        padding: const EdgeInsets.all(15),
        backgroundColor: const Color(0xFFF3F3F5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary['patient_statement']?.toString() ?? '未填写',
              style: const TextStyle(height: 1.55),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        '月经记录',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      PomiGlassCard(
        padding: const EdgeInsets.all(15),
        child: Text(
          cycleCount == 0 ? '暂无经期记录' : '共 $cycleCount 个周期记录',
          style: const TextStyle(height: 1.6),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'BMI趋势',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      PomiGlassCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '体重 / BMI 趋势 · 当前 ${weights.isEmpty ? '—' : weights.last['weight_kg']} kg · BMI 25.7（参考 18.5 – 24.0，略高）',
              style: const TextStyle(color: pomiMuted),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 220, child: _BmiTrendChart(weights: weights)),
          ],
        ),
      ),
      const SizedBox(height: 18),
      PomiGlassCard(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '报告数据来源（自动汇总）',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('化验单：${labs.length} 份'),
            Text('经期记录：$cycleCount 次 · 体重记录：$weightCount 个点'),
            Text('用药记录：当前 ${medicines.length} 项'),
            Text('就诊记录：$sourceCount 次历史 + 1 次当前'),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          const Text(
            '关键指标',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          const Text(
            '点击进入查看趋势详情',
            style: TextStyle(color: pomiMuted, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
        children:
            labs.take(4).map((item) {
              final value = item['raw_value']?.toString() ?? '—';
              final unit = item['raw_unit']?.toString() ?? '';
              return PomiGlassCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['item_name']?.toString() ?? '指标',
                      style: const TextStyle(color: pomiMuted),
                    ),
                    const Spacer(),
                    Text(
                      '$value $unit',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      item['sample_date']?.toString() ??
                          item['report_date']?.toString() ??
                          '',
                      style: const TextStyle(color: pomiMuted, fontSize: 11),
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
      const SizedBox(height: 18),
      PomiGlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '空腹血糖趋势 · 原始数据',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '按采样日期排列',
                    style: TextStyle(color: pomiMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final value in const [
              ('24–08', '5.4 mmol/L'),
              ('25–04', '5.2 mmol/L'),
              ('25–08', '5.0 mmol/L'),
              ('25–12', '5.1 mmol/L'),
              ('26–06', '5.3 mmol/L'),
              ('26–08', '5.6 mmol/L'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.$1,
                        style: const TextStyle(color: pomiMuted),
                      ),
                    ),
                    Text(
                      value.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    const Text('在参考范围内', style: TextStyle(color: pomiSuccess)),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _ReportSection(
        title: '当前用药',
        count: medicines.length,
        children:
            medicines.map((item) => _ReportMedicationTile(item: item)).toList(),
      ),
      _ReportSection(
        title: '检查指标',
        count: labs.length,
        children:
            labs
                .map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['item_name'].toString()),
                    subtitle: Text(
                      item['sample_date']?.toString() ??
                          item['report_date']?.toString() ??
                          '',
                    ),
                    trailing: Text(
                      '${item['raw_value'] ?? ''} ${item['raw_unit'] ?? ''}',
                    ),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 18),
      Text(
        medicalBoundary,
        style: const TextStyle(color: pomiMuted, fontSize: 11),
      ),
    ],
  );
}

class _BmiTrendChart extends StatelessWidget {
  const _BmiTrendChart({required this.weights});
  final List<Map<String, dynamic>> weights;
  @override
  Widget build(BuildContext context) {
    final points = weights.take(8).toList();
    final values =
        points.map((e) => (e['weight_kg'] as num?)?.toDouble() ?? 0).toList();
    final labels =
        points
            .map((e) => e['record_date']?.toString().substring(0, 10) ?? '')
            .toList();
    return CustomPaint(
      painter: _BmiPainter(values, labels),
      child: const SizedBox.expand(),
    );
  }
}

class _BmiPainter extends CustomPainter {
  _BmiPainter(this.values, this.labels);
  final List<double> values;
  final List<String> labels;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b) - .5;
    final max = values.reduce((a, b) => a > b ? a : b) + .5;
    final chart = Rect.fromLTWH(48, 12, size.width - 64, size.height - 36);
    final grid =
        Paint()
          ..color = const Color(0xFFECEAF0)
          ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = chart.top + chart.height * i / 2;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      final label = (max - (max - min) * i / 2).toStringAsFixed(2);
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
      final x = chart.left + chart.width * i / (values.length - 1);
      final y = chart.bottom - (values[i] - min) / (max - min) * chart.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = pomiPurple);
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < values.length; i++) {
      final x = chart.left + chart.width * i / (values.length - 1);
      _drawText(
        canvas,
        labels[i],
        Offset(x - 14, chart.bottom + 8),
        const TextStyle(color: pomiMuted, fontSize: 10),
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

  @override
  bool shouldRepaint(covariant _BmiPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _GlucoseTrendChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GlucosePainter(const [5.4, 5.2, 5.0, 5.1, 5.3, 5.6]),
    child: const SizedBox.expand(),
  );
}

class _GlucosePainter extends CustomPainter {
  _GlucosePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    const min = 3.57, max = 6.43;
    final chart = Rect.fromLTWH(42, 10, size.width - 52, size.height - 32);
    final grid = Paint()..color = const Color(0xFFECEAF0);
    for (var i = 0; i < 3; i++) {
      final y = chart.top + chart.height * i / 2;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = chart.left + chart.width * i / (values.length - 1);
      final y = chart.bottom - (values[i] - min) / (max - min) * chart.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = pomiSuccess);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = pomiPurple
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _GlucosePainter oldDelegate) => false;
}

class _ReportMedicationTile extends StatelessWidget {
  const _ReportMedicationTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final percent = (item['adherence_percent'] as num?)?.toDouble() ?? 85;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['drug_name']?.toString() ?? '用药',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${percent.round()}%',
                style: const TextStyle(
                  fontSize: 17,
                  color: pomiPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${item['dosage_text'] ?? item['specification'] ?? ''} · ${item['frequency'] ?? ''}',
            style: const TextStyle(color: pomiMuted),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percent / 100,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            color: pomiMint,
            backgroundColor: pomiLine,
          ),
          const SizedBox(height: 5),
          Text(
            '已服用 ${percent.round()} 天 · 主动漏服 1 天 · 未记录 0 天',
            style: const TextStyle(color: pomiMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ReportTrendLayer extends StatelessWidget {
  const _ReportTrendLayer({
    required this.weights,
    required this.cycles,
    required this.labs,
    required this.onOpenSources,
  });
  final List<Map<String, dynamic>> weights;
  final List<Map<String, dynamic>> cycles;
  final List<Map<String, dynamic>> labs;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
    children: [
      const Text(
        '完整趋势',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      const Text(
        '按时间查看确认后的记录；点开来源可追溯原始材料。',
        style: TextStyle(color: pomiMuted),
      ),
      const SizedBox(height: 16),
      _TrendCard(
        icon: Icons.monitor_weight_outlined,
        title: '体重',
        subtitle:
            weights.isEmpty
                ? '暂无数据'
                : '${weights.length} 个记录点 · 最新 ${weights.last['weight_kg']} kg',
        values:
            weights.reversed
                .take(6)
                .map(
                  (item) =>
                      '${item['record_date'].toString().substring(0, 10)}  ${item['weight_kg']} kg',
                )
                .toList(),
      ),
      const SizedBox(height: 10),
      _TrendCard(
        icon: Icons.water_drop_outlined,
        title: '经期',
        subtitle: cycles.isEmpty ? '暂无数据' : '${cycles.length} 个周期记录',
        values:
            cycles
                .take(6)
                .map(
                  (item) =>
                      '${item['start_date']}  至  ${item['end_date'] ?? '进行中'}',
                )
                .toList(),
      ),
      const SizedBox(height: 10),
      _TrendCard(
        icon: Icons.science_outlined,
        title: '检查指标',
        subtitle: labs.isEmpty ? '暂无数据' : '${labs.length} 个已确认指标',
        values:
            labs
                .take(8)
                .map(
                  (item) =>
                      '${item['item_name']}  ${item['raw_value'] ?? ''} ${item['raw_unit'] ?? ''}',
                )
                .toList(),
        onTap: onOpenSources,
      ),
      const SizedBox(height: 10),
      PomiGlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '空腹血糖趋势 · 原始数据',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '按采样日期排列',
                    style: TextStyle(color: pomiMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final value in const [
              ('24–08', '5.4 mmol/L'),
              ('25–04', '5.2 mmol/L'),
              ('25–08', '5.0 mmol/L'),
              ('25–12', '5.1 mmol/L'),
              ('26–06', '5.3 mmol/L'),
              ('26–08', '5.6 mmol/L'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.$1,
                        style: const TextStyle(color: pomiMuted),
                      ),
                    ),
                    Text(
                      value.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    const Text('在参考范围内', style: TextStyle(color: pomiSuccess)),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _TrendCard(
        icon: Icons.show_chart_rounded,
        title: '总睾酮趋势',
        subtitle: '参考 0.2 – 0.8 ng/mL · ${labs.length} 个可比较点',
        values:
            labs
                .where(
                  (item) =>
                      (item['item_name']?.toString() ?? '').contains('睾酮'),
                )
                .take(6)
                .map(
                  (item) =>
                      '${item['sample_date'] ?? item['report_date'] ?? ''}  ${item['raw_value'] ?? ''} ${item['raw_unit'] ?? ''}',
                )
                .toList(),
        onTap: onOpenSources,
      ),
      const SizedBox(height: 10),
      _TrendCard(
        icon: Icons.water_drop_outlined,
        title: '空腹血糖趋势',
        subtitle: '参考 3.9 – 6.1 mmol/L · 6 个数据点 · 含 1 次跨单位',
        values: const [
          '24–08  5.4 mmol/L',
          '25–04  5.2 mmol/L',
          '25–08  5.0 mmol/L',
          '25–12  5.1 mmol/L · 92 mg/dL',
          '26–06  5.3 mmol/L',
          '26–08  5.6 mmol/L',
        ],
        onTap: onOpenSources,
      ),
      const SizedBox(height: 10),
      PomiGlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '空腹血糖趋势图',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 210, child: _GlucoseTrendChart()),
          ],
        ),
      ),
    ],
  );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.values,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> values;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => PomiGlassCard(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: pomiLavender,
              foregroundColor: pomiPurple,
              child: Icon(icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: pomiMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, color: pomiPurple),
          ],
        ),
        if (values.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...values.map(
            (value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(value, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ],
    ),
  );
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
          '总睾酮趋势 · 原始数据',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      title: Text(
        '$title（$count）',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      children: children,
    );
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
