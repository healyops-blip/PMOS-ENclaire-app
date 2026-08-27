import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';

class OcrTaskPage extends StatefulWidget {
  const OcrTaskPage({
    required this.repository,
    required this.document,
    this.pollInterval = const Duration(seconds: 2),
    super.key,
  });

  final OcrRepository repository;
  final MedicalDocument document;
  final Duration pollInterval;

  @override
  State<OcrTaskPage> createState() => _OcrTaskPageState();
}

class _OcrTaskPageState extends State<OcrTaskPage> with WidgetsBindingObserver {
  OcrTask? _task;
  Object? _requestError;
  Timer? _timer;
  bool _foreground = true;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _create();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
    } else if (_task?.status.isPolling ?? false) {
      _poll();
    }
  }

  Future<void> _create() async {
    setState(() {
      _requestError = null;
      _requesting = true;
    });
    try {
      final task = await widget.repository.create(
        documentId: widget.document.id,
        revisionId: widget.document.currentRevisionId,
      );
      if (!mounted) return;
      setState(() {
        _task = task;
        _requesting = false;
      });
      _schedule();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _requestError = error;
        _requesting = false;
      });
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_foreground || !(_task?.status.isPolling ?? false)) return;
    _timer = Timer(widget.pollInterval, _poll);
  }

  Future<void> _poll() async {
    if (!_foreground || _requesting || _task == null) return;
    _requesting = true;
    try {
      final task = await widget.repository.get(_task!.id);
      if (!mounted) return;
      setState(() {
        _task = task;
        _requestError = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _requestError = error);
    } finally {
      _requesting = false;
      if (mounted) _schedule();
    }
  }

  Future<void> _retry() async {
    if (_task == null) return;
    setState(() {
      _requesting = true;
      _requestError = null;
    });
    try {
      final task = await widget.repository.retry(_task!.id);
      if (!mounted) return;
      setState(() => _task = task);
      _schedule();
    } on Object catch (error) {
      if (mounted) setState(() => _requestError = error);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  void _openConfirmation() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OcrPendingConfirmationPage(
          repository: widget.repository,
          task: _task!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return Scaffold(
      key: const Key('ocr-task-page'),
      appBar: AppBar(title: const Text('材料识别')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon(task?.status),
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                _title(task?.status),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _requestError?.toString() ??
                    task?.error?.userMessage ??
                    _subtitle(task?.status),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_requesting || task == null || task.status.isPolling)
                const CircularProgressIndicator(
                  key: Key('ocr-polling-indicator'),
                ),
              if (_requestError != null && task == null)
                FilledButton(onPressed: _create, child: const Text('重试创建任务')),
              if (task?.status == OcrTaskStatus.failed ||
                  task?.status == OcrTaskStatus.timedOut)
                FilledButton(
                  key: const Key('ocr-retry-button'),
                  onPressed: _requesting ? null : _retry,
                  child: const Text('重新识别'),
                ),
              if (task?.status == OcrTaskStatus.pendingConfirmation)
                FilledButton(
                  key: const Key('ocr-confirmation-entry'),
                  onPressed: _openConfirmation,
                  child: Text('进入${_materialLabel(task!.materialType)}确认'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class OcrPendingConfirmationPage extends StatelessWidget {
  const OcrPendingConfirmationPage({
    required this.repository,
    required this.task,
    super.key,
  });
  final OcrRepository repository;
  final OcrTask task;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: Key('ocr-confirmation-${task.materialType}'),
    appBar: AppBar(title: Text('${_materialLabel(task.materialType)}待确认')),
    body: FutureBuilder<OcrTaskResult>(
      future: repository.result(task.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('识别草稿尚未写入正式医疗记录，请在后续确认页面逐项核对。'),
            const SizedBox(height: 12),
            for (final field in snapshot.data!.fields)
              ListTile(
                title: Text(field.path),
                subtitle: Text(field.sourceText ?? '未识别到原文'),
                trailing: Text('${(field.confidence * 100).round()}%'),
              ),
          ],
        );
      },
    ),
  );
}

IconData _icon(OcrTaskStatus? status) => switch (status) {
  OcrTaskStatus.pendingConfirmation ||
  OcrTaskStatus.confirmed => Icons.fact_check_outlined,
  OcrTaskStatus.failed || OcrTaskStatus.timedOut => Icons.error_outline,
  _ => Icons.document_scanner_outlined,
};

String _title(OcrTaskStatus? status) => switch (status) {
  OcrTaskStatus.queued => '正在排队',
  OcrTaskStatus.processing => '正在识别',
  OcrTaskStatus.pendingConfirmation => '识别完成，等待确认',
  OcrTaskStatus.confirmed => '已确认',
  OcrTaskStatus.failed => '识别失败',
  OcrTaskStatus.timedOut => '识别超时',
  null => '正在创建识别任务',
};

String _subtitle(OcrTaskStatus? status) => switch (status) {
  OcrTaskStatus.queued => '任务已安全保存，可以离开此页面。',
  OcrTaskStatus.processing => '正在转录可见文字，不会自动作出诊断。',
  OcrTaskStatus.pendingConfirmation => '请核对识别字段后再决定是否正式保存。',
  _ => '',
};

String _materialLabel(String type) => switch (type) {
  'lab_report' => '化验报告',
  'medical_order' => '医嘱',
  'imaging_text_report' => '影像文字报告',
  _ => '门诊病历',
};
