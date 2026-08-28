import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/reports/data/report_pdf_repository.dart';

enum _PdfAction { save, share, print }

class ReportPdfPanel extends StatefulWidget {
  const ReportPdfPanel({
    required this.reportId,
    required this.repository,
    required this.cache,
    ReportPdfSystemActions? systemActions,
    this.pollingInterval = const Duration(milliseconds: 800),
    this.maxPolls = 45,
    super.key,
  }) : systemActions = systemActions ?? const AndroidReportPdfSystemActions();

  final String reportId;
  final ReportPdfRepository repository;
  final ReportPdfCache cache;
  final ReportPdfSystemActions systemActions;
  final Duration pollingInterval;
  final int maxPolls;

  @override
  State<ReportPdfPanel> createState() => _ReportPdfPanelState();
}

class _ReportPdfPanelState extends State<ReportPdfPanel> {
  bool _busy = false;
  ReportPdfGenerationStatus? _status;
  String? _error;
  String? _success;
  _PdfAction? _retryAction;
  ScaffoldMessengerState? _messenger;
  String? _bannerSignature;

  @override
  void initState() {
    super.initState();
    unawaited(_cleanCache());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  Future<void> _cleanCache() async {
    try {
      await widget.cache.cleanup();
    } on Exception {
      // A temporary-cache cleanup failure never blocks the immutable report.
    }
  }

  Future<void> _handle(_PdfAction action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = ReportPdfGenerationStatus.queued;
      _error = null;
      _success = null;
      _retryAction = action;
    });
    try {
      var job = await widget.repository.create(widget.reportId);
      if (job.status == ReportPdfGenerationStatus.succeeded) {
        job = await widget.repository.getStatus(widget.reportId);
      }
      var polls = 0;
      while (job.status == ReportPdfGenerationStatus.queued ||
          job.status == ReportPdfGenerationStatus.processing) {
        if (!mounted) return;
        setState(() => _status = job.status);
        if (polls >= widget.maxPolls) {
          throw const ReportPdfFailure('PDF 仍在后台生成，请稍后点击重试查询');
        }
        await Future<void>.delayed(widget.pollingInterval);
        if (!mounted) return;
        job = await widget.repository.getStatus(widget.reportId);
        polls += 1;
      }
      if (job.status == ReportPdfGenerationStatus.failed) {
        throw ReportPdfFailure(
          job.failureReason?.trim().isNotEmpty == true
              ? job.failureReason!
              : 'PDF 生成失败，请重试',
        );
      }
      if (mounted) {
        setState(() => _status = ReportPdfGenerationStatus.succeeded);
      }
      final bytes = await widget.repository.download(widget.reportId);
      if (!mounted) return;
      final cached = await widget.cache.store(
        reportId: widget.reportId,
        bytes: bytes,
        suggestedName: job.fileName,
      );
      final fileName = Uri.decodeComponent(cached.uri.pathSegments.last);
      switch (action) {
        case _PdfAction.save:
          await widget.systemActions.save(cached, fileName);
        case _PdfAction.share:
          await widget.systemActions.share(cached, fileName);
        case _PdfAction.print:
          await widget.systemActions.print(cached, fileName);
      }
      if (!mounted) return;
      final message = switch (action) {
        _PdfAction.save => 'PDF 已保存到你选择的位置',
        _PdfAction.share => '已打开 Android 系统分享面板',
        _PdfAction.print => '已打开 Android 系统打印预览',
      };
      setState(() => _success = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Exception catch (error) {
      if (!mounted) return;
      final detail = error is ReportPdfFailure ? error.message : 'PDF 操作失败，请重试';
      setState(() => _error = '$detail。App 内报告和服务器文件不受影响。');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$detail，App 内报告不受影响')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final success = _success;
    final color = error != null
        ? const Color(0xFF9C3F52)
        : success != null
        ? PomiColors.success
        : PomiColors.primary;
    final message =
        error ??
        success ??
        switch (_status) {
          ReportPdfGenerationStatus.queued => 'PDF 已排队，正在准备静态报告…',
          ReportPdfGenerationStatus.processing => '正在生成静态 PDF，请稍候…',
          ReportPdfGenerationStatus.succeeded => 'PDF 已生成，正在鉴权下载…',
          ReportPdfGenerationStatus.failed => 'PDF 生成失败',
          null => null,
        };
    _scheduleBanner(message, color, error != null);
    return PopupMenuButton<_PdfAction>(
      key: const Key('report-pdf-menu'),
      tooltip: '服务器静态 PDF · 私有鉴权下载',
      enabled: !_busy,
      onSelected: _handle,
      itemBuilder: (context) => const [
        PopupMenuItem(value: _PdfAction.save, child: Text('保存 PDF')),
        PopupMenuItem(value: _PdfAction.share, child: Text('分享 PDF')),
        PopupMenuItem(value: _PdfAction.print, child: Text('打印 PDF')),
      ],
      icon: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined),
    );
  }

  void _scheduleBanner(String? message, Color color, bool failed) {
    final signature = '$message|$_busy|$failed';
    if (_bannerSignature == signature) return;
    _bannerSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = _messenger;
      if (messenger == null) return;
      messenger.clearMaterialBanners();
      if (message == null) return;
      messenger.showMaterialBanner(
        MaterialBanner(
          key: const Key('report-pdf-status'),
          backgroundColor: color.withValues(alpha: 0.08),
          leading: _busy
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: color,
                ),
          content: Text(
            message,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          actions: [
            if (failed && _retryAction != null)
              TextButton(
                key: const Key('retry-report-pdf'),
                onPressed: _busy ? null : () => _handle(_retryAction!),
                child: const Text('重试'),
              ),
            TextButton(
              onPressed: messenger.clearMaterialBanners,
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    });
  }
}
