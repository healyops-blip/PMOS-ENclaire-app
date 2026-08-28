import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/certification/application/certification_flow_controller.dart';
import 'package:pmos_enclaire/features/certification/application/certification_providers.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_copy.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';

class CertificationPage extends ConsumerStatefulWidget {
  const CertificationPage({
    required this.documentId,
    required this.revisionId,
    required this.materialLabel,
    this.transitionDuration = const Duration(milliseconds: 1400),
    this.demoPlan = const CertificationDemoPlan(),
    super.key,
  });

  final String documentId;
  final String revisionId;
  final String materialLabel;
  final Duration transitionDuration;

  /// Injectable for automated/demo builds. Production callers use the default
  /// golden path and do not expose a failure switch to users.
  final CertificationDemoPlan demoPlan;

  @override
  ConsumerState<CertificationPage> createState() => _CertificationPageState();
}

class _CertificationPageState extends ConsumerState<CertificationPage> {
  late final CertificationFlowController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CertificationFlowController(
      repository: ref.read(certificationRepositoryProvider),
      documentId: widget.documentId,
      revisionId: widget.revisionId,
      transitionDuration: widget.transitionDuration,
      plan: widget.demoPlan,
    )..addListener(_changed);
    _controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = _controller.record;
    final status = record.status;
    final processing = status == CertificationStatus.processing;
    final succeeded = status == CertificationStatus.succeeded;
    return Scaffold(
      key: const Key('certification-page'),
      appBar: AppBar(title: const Text(CertificationCopy.pageTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Row(
            children: [
              DemoBadge(label: '仅限本地交互演示'),
              Spacer(),
              Text(
                '不代表真实认证',
                style: TextStyle(color: PomiColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RevisionPreview(
            materialLabel: widget.materialLabel,
            documentId: widget.documentId,
            revisionId: widget.revisionId,
            showWatermark: succeeded,
          ),
          const SizedBox(height: 18),
          const PomiSectionTitle(title: '本地演示状态'),
          const SizedBox(height: 8),
          PomiSectionCard(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _controller.loading
                  ? const Center(
                      key: Key('certification-loading'),
                      child: CircularProgressIndicator(),
                    )
                  : _StatusContent(key: ValueKey(status), record: record),
            ),
          ),
          const SizedBox(height: 16),
          const _BoundaryCard(),
          const SizedBox(height: 18),
          if (!succeeded)
            FilledButton.icon(
              key: const Key('advance-certification-button'),
              onPressed: processing || _controller.loading
                  ? null
                  : _controller.start,
              icon: processing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(
                processing
                    ? '认证演示处理中…'
                    : status == CertificationStatus.failed
                    ? '重试本地认证演示'
                    : '开始医院认证演示',
              ),
            )
          else
            FilledButton.icon(
              key: const Key('finish-certification-button'),
              onPressed: () => Navigator.maybePop(context, record),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('完成并返回材料详情'),
            ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '${CertificationCopy.technologySupport} · 当前未连接真实区块链服务',
              textAlign: TextAlign.center,
              style: TextStyle(color: PomiColors.textMuted, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class CertificationEntryCard extends ConsumerStatefulWidget {
  const CertificationEntryCard({
    required this.documentId,
    required this.revisionId,
    required this.materialLabel,
    required this.ocrConfirmed,
    required this.documentRepository,
    this.demoPlan = const CertificationDemoPlan(),
    this.transitionDuration = const Duration(milliseconds: 1400),
    super.key,
  });

  final String documentId;
  final String revisionId;
  final String materialLabel;
  final bool ocrConfirmed;
  final DocumentRepository documentRepository;
  final CertificationDemoPlan demoPlan;
  final Duration transitionDuration;

  bool get eligible =>
      ocrConfirmed &&
      documentId.trim().isNotEmpty &&
      revisionId.trim().isNotEmpty;

  @override
  ConsumerState<CertificationEntryCard> createState() =>
      _CertificationEntryCardState();
}

class _CertificationEntryCardState
    extends ConsumerState<CertificationEntryCard> {
  CertificationRecord? _record;
  bool _currentRevisionAvailable = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.eligible) _load();
  }

  @override
  void didUpdateWidget(CertificationEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final inputChanged =
        oldWidget.eligible != widget.eligible ||
        oldWidget.documentId != widget.documentId ||
        oldWidget.revisionId != widget.revisionId ||
        oldWidget.documentRepository != widget.documentRepository;
    if (!inputChanged) return;
    _loadGeneration++;
    _record = null;
    _currentRevisionAvailable = false;
    if (widget.eligible) {
      _load();
    }
  }

  Future<bool> _load() async {
    final generation = ++_loadGeneration;
    final documentId = widget.documentId;
    final revisionId = widget.revisionId;
    if (!widget.eligible) return false;
    try {
      final document = await widget.documentRepository.get(documentId);
      if (!_isCurrentRequest(generation, documentId, revisionId)) return false;
      if (document.currentRevisionId != revisionId) {
        setState(() {
          _record = null;
          _currentRevisionAvailable = false;
        });
        return false;
      }
      final record = await ref
          .read(certificationRepositoryProvider)
          .read(documentId, revisionId);
      if (!_isCurrentRequest(generation, documentId, revisionId)) return false;
      setState(() {
        _record = record;
        _currentRevisionAvailable = true;
      });
      return true;
    } on Object {
      if (_isCurrentRequest(generation, documentId, revisionId)) {
        setState(() {
          _record = null;
          _currentRevisionAvailable = false;
        });
      }
      return false;
    }
  }

  bool _isCurrentRequest(
    int generation,
    String documentId,
    String revisionId,
  ) =>
      mounted &&
      generation == _loadGeneration &&
      widget.eligible &&
      widget.documentId == documentId &&
      widget.revisionId == revisionId;

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> _open() async {
    if (!await _load() || !mounted) return;
    await Navigator.of(context).push<CertificationRecord>(
      MaterialPageRoute(
        builder: (_) => CertificationPage(
          documentId: widget.documentId,
          revisionId: widget.revisionId,
          materialLabel: widget.materialLabel,
          transitionDuration: widget.transitionDuration,
          demoPlan: widget.demoPlan,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.eligible || !_currentRevisionAvailable) {
      return const SizedBox.shrink();
    }
    final status = _record?.status ?? CertificationStatus.notStarted;
    final succeeded = status == CertificationStatus.succeeded;
    return PomiSectionCard(
      key: const Key('certification-entry-card'),
      onTap: _open,
      color: succeeded ? const Color(0xFFF1F8F3) : Colors.white,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (succeeded ? PomiColors.success : PomiColors.primary)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  succeeded
                      ? Icons.verified_rounded
                      : Icons.verified_user_outlined,
                  color: succeeded ? PomiColors.success : PomiColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _entryTitle(status),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      succeeded
                          ? '仅绑定修订 ${widget.revisionId}，新修订需重新演示'
                          : '演示功能 · 不连接医院或真实区块链',
                      style: const TextStyle(
                        color: PomiColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      CertificationCopy.technologySupport,
                      style: TextStyle(
                        color: PomiColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          if (succeeded)
            const Positioned(
              right: 24,
              top: -10,
              child: CertificationWatermark(),
            ),
        ],
      ),
    );
  }
}

class CertificationWatermark extends StatelessWidget {
  const CertificationWatermark({super.key});

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.04,
    child: Container(
      key: const Key('certification-watermark'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F3).withValues(alpha: 0.94),
        border: Border.all(color: PomiColors.success, width: 1.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        CertificationCopy.watermark,
        style: TextStyle(
          color: PomiColors.success,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    ),
  );
}

class _RevisionPreview extends StatelessWidget {
  const _RevisionPreview({
    required this.materialLabel,
    required this.documentId,
    required this.revisionId,
    required this.showWatermark,
  });

  final String materialLabel;
  final String documentId;
  final String revisionId;
  final bool showWatermark;

  @override
  Widget build(BuildContext context) => PomiSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              backgroundColor: PomiColors.primaryPale,
              foregroundColor: PomiColors.primary,
              child: Icon(Icons.description_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    materialLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'OCR 已由用户确认 · 本地演示对象',
                    style: TextStyle(color: PomiColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _InfoRow(label: '材料 ID', value: documentId),
        _InfoRow(label: '当前修订 ID', value: revisionId, last: true),
        if (showWatermark) ...[
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerRight,
            child: CertificationWatermark(),
          ),
        ],
      ],
    ),
  );
}

class _BoundaryCard extends StatelessWidget {
  const _BoundaryCard();

  @override
  Widget build(BuildContext context) => PomiSectionCard(
    color: const Color(0xFFFFF8EE),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF8B5D3F)),
            SizedBox(width: 8),
            Text('演示边界', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        SizedBox(height: 9),
        Text(
          CertificationCopy.boundary,
          style: TextStyle(height: 1.55, fontSize: 11),
        ),
        SizedBox(height: 8),
        Text(
          CertificationCopy.dataSafety,
          style: TextStyle(
            color: PomiColors.textMuted,
            height: 1.55,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.record, super.key});

  final CertificationRecord record;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, body) = switch (record.status) {
      CertificationStatus.notStarted => (
        Icons.radio_button_unchecked,
        PomiColors.textMuted,
        '尚未开始',
        '当前已确认材料可以发起本地认证交互演示。',
      ),
      CertificationStatus.processing => (
        Icons.autorenew_rounded,
        PomiColors.primary,
        '处理中',
        '正在模拟认证流程，通常需要 1–2 秒。请勿重复点击。',
      ),
      CertificationStatus.succeeded => (
        Icons.check_circle_rounded,
        PomiColors.success,
        '本地演示成功',
        '成功水印只适用于页面上显示的材料修订，不代表真实医院认证。',
      ),
      CertificationStatus.failed => (
        Icons.error_outline_rounded,
        PomiColors.warning,
        '本地演示失败',
        record.failureReason ?? '可以重试；失败不会影响材料和医疗数据。',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
              if (record.updatedAt != null) ...[
                const SizedBox(height: 5),
                Text(
                  '本地更新时间 ${DateFormat('yyyy-MM-dd HH:mm').format(record.updatedAt!.toLocal())}',
                  style: const TextStyle(
                    color: PomiColors.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
    ),
    child: Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

String _entryTitle(CertificationStatus status) => switch (status) {
  CertificationStatus.notStarted => '医院认证 · 本地演示',
  CertificationStatus.processing => '本地认证演示处理中',
  CertificationStatus.succeeded => '本地认证演示已完成',
  CertificationStatus.failed => '本地认证演示失败，可重试',
};
