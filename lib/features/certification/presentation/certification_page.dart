import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/certification/application/certification_providers.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';

class CertificationPage extends ConsumerStatefulWidget {
  const CertificationPage({
    this.documentId = 'document-lab-006',
    this.revisionId = 'revision-v2',
    super.key,
  });

  final String documentId;
  final String revisionId;

  @override
  ConsumerState<CertificationPage> createState() => _CertificationPageState();
}

class _CertificationPageState extends ConsumerState<CertificationPage> {
  CertificationRecord? _record;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final record = await ref
        .read(certificationRepositoryProvider)
        .read(widget.documentId, widget.revisionId);
    if (mounted) setState(() => _record = record);
  }

  Future<void> _save(
    CertificationStatus status, {
    String? failureReason,
  }) async {
    final record = CertificationRecord(
      documentId: widget.documentId,
      revisionId: widget.revisionId,
      status: status,
      updatedAt: DateTime.now(),
      failureReason: failureReason,
    );
    setState(() => _record = record);
    await ref.read(certificationRepositoryProvider).write(record);
  }

  Future<void> _startCertification() async {
    await _save(CertificationStatus.processing);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted || _record?.status != CertificationStatus.processing) return;
    await _save(CertificationStatus.succeeded);
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final status = record?.status ?? CertificationStatus.notStarted;
    final processing = status == CertificationStatus.processing;
    final succeeded = status == CertificationStatus.succeeded;
    return Scaffold(
      key: const Key('certification-page'),
      appBar: AppBar(title: const Text('医院认证演示')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Row(
            children: [
              DemoBadge(label: '仅限前端演示'),
              Spacer(),
              Text(
                '模拟数据',
                style: TextStyle(color: PomiColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MaterialPreview(succeeded: succeeded),
          const SizedBox(height: 18),
          const PomiSectionTitle(title: '认证状态'),
          const SizedBox(height: 8),
          PomiSectionCard(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _StatusContent(key: ValueKey(status), record: record),
            ),
          ),
          const SizedBox(height: 16),
          PomiSectionCard(
            color: PomiColors.primaryPale,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '这项演示代表什么？',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 7),
                Text(
                  '认证状态仅保存在本机，并绑定当前材料版本。替换原文件后，新版本需要重新认证。',
                  style: TextStyle(
                    color: PomiColors.textMuted,
                    height: 1.55,
                    fontSize: 11,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '不连接医院、医生身份系统或真实区块链，不产生具有法律效力的签章或凭证。',
                  style: TextStyle(
                    color: Color(0xFF8B5D3F),
                    height: 1.55,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('advance-certification-button'),
            onPressed: processing
                ? null
                : status == CertificationStatus.succeeded
                ? null
                : _startCertification,
            icon: processing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_outlined),
            label: Text(
              processing
                  ? '认证处理中…'
                  : status == CertificationStatus.failed
                  ? '重新认证'
                  : succeeded
                  ? '演示认证已完成'
                  : '开始医院认证演示',
            ),
          ),
          if (!processing && !succeeded) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('simulate-certification-failure'),
              onPressed: () =>
                  _save(CertificationStatus.failed, failureReason: '演示网络中断'),
              child: const Text('模拟失败分支'),
            ),
          ],
          const SizedBox(height: 14),
          const Center(
            child: Text(
              '提供区块链技术支持 · 当前未连接真实区块链服务',
              style: TextStyle(color: PomiColors.textMuted, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialPreview extends StatelessWidget {
  const _MaterialPreview({required this.succeeded});

  final bool succeeded;

  @override
  Widget build(BuildContext context) {
    return PomiSectionCard(
      child: Stack(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: PomiColors.primaryPale,
                    foregroundColor: PomiColors.primary,
                    child: Icon(Icons.science_outlined),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '检测单 6 · 模拟医院 B',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '文件版本 V2 · 已完成用户确认',
                          style: TextStyle(
                            color: PomiColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              _InfoRow(label: '材料编号', value: 'document-lab-006'),
              _InfoRow(label: '修订编号', value: 'revision-v2'),
              _InfoRow(label: '文件哈希', value: '8c3d…f1a9', last: true),
            ],
          ),
          if (succeeded)
            Positioned(
              right: 2,
              bottom: 0,
              child: Transform.rotate(
                angle: -0.08,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: PomiColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                  child: const Text(
                    '演示认证',
                    style: TextStyle(
                      color: PomiColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.record, super.key});

  final CertificationRecord? record;

  @override
  Widget build(BuildContext context) {
    final status = record?.status ?? CertificationStatus.notStarted;
    final (icon, color, title, body) = switch (status) {
      CertificationStatus.notStarted => (
        Icons.radio_button_unchecked,
        PomiColors.textMuted,
        '尚未开始',
        '已确认的材料可以发起本地认证演示。',
      ),
      CertificationStatus.processing => (
        Icons.autorenew_rounded,
        PomiColors.primary,
        '处理中',
        '正在模拟认证流程，通常需要 1–2 秒。',
      ),
      CertificationStatus.succeeded => (
        Icons.check_circle_rounded,
        PomiColors.success,
        '演示认证成功',
        '本机已保存当前材料版本的演示状态。',
      ),
      CertificationStatus.failed => (
        Icons.error_outline_rounded,
        PomiColors.warning,
        '认证失败',
        record?.failureReason ?? '可以重新尝试，不影响已确认材料。',
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
              if (record?.updatedAt != null) ...[
                const SizedBox(height: 5),
                Text(
                  '更新时间 ${DateFormat('yyyy-MM-dd HH:mm').format(record!.updatedAt!)}',
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
      ),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
