import 'package:flutter/material.dart';
import 'package:pmos_enclaire/features/certification/presentation/certification_page.dart';
import 'package:pmos_enclaire/features/records/data/document_repository.dart';
import 'package:pmos_enclaire/features/records/data/ocr_repository.dart';
import 'package:pmos_enclaire/features/records/data/order_reconciliation_repository.dart';

class MedicalOrderReviewPage extends StatefulWidget {
  const MedicalOrderReviewPage({
    required this.gateway,
    required this.task,
    required this.result,
    this.document,
    this.documentRepository,
    super.key,
  });

  final MedicalOrderGateway gateway;
  final OcrTask task;
  final OcrTaskResult result;
  final MedicalDocument? document;
  final DocumentRepository? documentRepository;

  @override
  State<MedicalOrderReviewPage> createState() => _MedicalOrderReviewPageState();
}

class _MedicalOrderReviewPageState extends State<MedicalOrderReviewPage> {
  late final List<MedicalOrderDraft> _items = MedicalOrderDraft.fromDraft(
    widget.result.draft,
  );
  bool _submitting = false;
  Object? _error;

  bool get _ready =>
      _items.isNotEmpty &&
      _items.every((item) => item.confirmed && item.isValid);

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.gateway.confirmMedicalOrder(widget.task.id, _items);
      final reconciliation = await widget.gateway.createReconciliation(
        widget.task.id,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => MedicationReconciliationPage(
            gateway: widget.gateway,
            reconciliation: reconciliation,
            documentId: widget.task.documentId,
            revisionId: widget.task.documentRevisionId,
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('medical-order-review-page'),
    appBar: AppBar(title: const Text('逐项核对医嘱')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        const Text('请对照原件逐种核对。药名、剂量、单位或频率缺失时不能确认，识别草稿不会直接修改当前用药。'),
        const SizedBox(height: 12),
        if (widget.document != null && widget.documentRepository != null) ...[
          _OriginalDocumentPreview(
            document: widget.document!,
            repository: widget.documentRepository!,
          ),
          const SizedBox(height: 12),
        ],
        if (_items.isEmpty) const Text('未识别到药物，请返回并重新识别或人工录入。'),
        for (final item in _items)
          _OrderItemCard(
            key: Key('medical-order-item-${item.index}'),
            item: item,
            onChanged: () => setState(() {}),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            '提交失败：$_error。你刚才的修改仍保留在本页。',
            key: const Key('medical-order-submit-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton(
        key: const Key('confirm-all-medical-orders'),
        onPressed: _ready && !_submitting ? _submit : null,
        child: Text(_submitting ? '正在保存…' : '保存医嘱并进入用药对账'),
      ),
    ),
  );
}

class _OriginalDocumentPreview extends StatelessWidget {
  const _OriginalDocumentPreview({
    required this.document,
    required this.repository,
  });
  final MedicalDocument document;
  final DocumentRepository repository;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '原件 · ${document.originalFileName}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          FutureBuilder(
            future: repository.download(
              document.id,
              document.currentRevisionId,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('原件暂时无法加载，可返回材料详情重试。');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (document.isPdf) {
                return const ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('单页 PDF 原件'),
                  subtitle: Text('请同时打开材料详情对照完整页面'),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: InteractiveViewer(
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _OrderItemCard extends StatelessWidget {
  const _OrderItemCard({
    required this.item,
    required this.onChanged,
    super.key,
  });
  final MedicalOrderDraft item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '药物 ${item.index + 1}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '原文：${item.rawOrderText.isEmpty ? '未识别到原文片段' : item.rawOrderText}',
            ),
          ),
          const SizedBox(height: 12),
          _field('药名 *', item.drugName, (value) => item.drugName = value),
          _field(
            '规格',
            item.specification,
            (value) => item.specification = value,
          ),
          Row(
            children: [
              Expanded(
                child: _field(
                  '单次剂量 *',
                  item.dosageValue,
                  (value) => item.dosageValue = value,
                  number: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  '剂量单位 *',
                  item.dosageUnit,
                  (value) => item.dosageUnit = value,
                ),
              ),
            ],
          ),
          _field('频率 *', item.frequency, (value) => item.frequency = value),
          _field('疗程', item.course, (value) => item.course = value),
          _field('途径', item.route, (value) => item.route = value),
          _field('用法', item.instructions, (value) => item.instructions = value),
          _field('开具日期 *', item.orderDate, (value) => item.orderDate = value),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('原文明确写明停药'),
            subtitle: const Text('仅在原件明确要求停用时开启'),
            value: item.explicitlyStopped,
            onChanged: (value) {
              item.explicitlyStopped = value;
              onChanged();
            },
          ),
          CheckboxListTile(
            key: Key('confirm-medical-order-${item.index}'),
            contentPadding: EdgeInsets.zero,
            title: const Text('我已对照原件核对这一种药'),
            subtitle: item.isValid ? null : const Text('请先补全药名、剂量、单位、频率、日期和原文'),
            value: item.confirmed,
            onChanged: item.isValid
                ? (value) {
                    item.confirmed = value ?? false;
                    onChanged();
                  }
                : null,
          ),
        ],
      ),
    ),
  );

  Widget _field(
    String label,
    String value,
    ValueChanged<String> changed, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: value,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        changed(value);
        if (item.confirmed && !item.isValid) item.confirmed = false;
        onChanged();
      },
    ),
  );
}

class MedicationReconciliationPage extends StatefulWidget {
  const MedicationReconciliationPage({
    required this.gateway,
    required this.reconciliation,
    this.documentId,
    this.revisionId,
    super.key,
  });
  final MedicalOrderGateway gateway;
  final MedicationReconciliationDraft reconciliation;
  final String? documentId;
  final String? revisionId;

  @override
  State<MedicationReconciliationPage> createState() =>
      _MedicationReconciliationPageState();
}

class _MedicationReconciliationPageState
    extends State<MedicationReconciliationPage> {
  late MedicationReconciliationDraft _reconciliation = widget.reconciliation;
  bool _submitting = false;
  Object? _error;

  bool get _ready =>
      _reconciliation.items.every((item) => item.decision != null);

  Future<void> _execute() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final value = await widget.gateway.executeReconciliation(_reconciliation);
      if (!mounted) return;
      setState(() {
        _reconciliation = value;
        _submitting = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('medication-reconciliation-page'),
    appBar: AppBar(title: const Text('用药对账')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Text('规则版本：${_reconciliation.ruleVersion}'),
        const Text('旧药未在新医嘱出现只会标记为“不确定”，不会自动停药。请逐项决定。'),
        const SizedBox(height: 12),
        if (widget.documentId != null && widget.revisionId != null) ...[
          CertificationEntryCard(
            documentId: widget.documentId!,
            revisionId: widget.revisionId!,
            materialLabel: '医嘱／处方',
            ocrConfirmed: true,
          ),
          const SizedBox(height: 12),
        ],
        for (final item in _reconciliation.items)
          Card(
            key: Key('reconciliation-item-${item.id}'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _suggestion(item.suggestion),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text('旧：${item.oldLabel}'),
                  Text('新：${item.newLabel}'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: Key('reconciliation-decision-${item.id}'),
                    initialValue: item.decision,
                    decoration: const InputDecoration(
                      labelText: '你的决定',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      if (item.suggestion != 'manual_review')
                        const DropdownMenuItem(
                          value: 'accept',
                          child: Text('接受规则建议'),
                        ),
                      const DropdownMenuItem(
                        value: 'keep_current',
                        child: Text('保持当前用药不变'),
                      ),
                      const DropdownMenuItem(
                        value: 'reject',
                        child: Text('拒绝此项变更'),
                      ),
                    ],
                    onChanged: (value) => setState(() => item.decision = value),
                  ),
                ],
              ),
            ),
          ),
        if (_error != null)
          Text(
            '执行失败：$_error。所有决定已保留，未产生部分变更。',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_reconciliation.status == 'executed')
          const ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text('对账已完整执行'),
          ),
      ],
    ),
    bottomNavigationBar: _reconciliation.status == 'executed'
        ? null
        : SafeArea(
            minimum: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('execute-reconciliation'),
              onPressed: _ready && !_submitting ? _execute : null,
              child: Text(_submitting ? '正在执行…' : '确认并执行全部决定'),
            ),
          ),
  );
}

String _suggestion(String value) => switch (value) {
  'unchanged' => '一致：无需变更',
  'adjusted' => '同药调整：将创建新版本',
  'added' => '新增药物',
  'stopped' => '原文明示停药',
  'uncertain' => '不确定：禁止自动停药',
  _ => '需要人工核对：无法可靠匹配',
};
