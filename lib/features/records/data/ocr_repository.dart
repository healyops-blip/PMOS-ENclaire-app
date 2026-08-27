import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/records/data/order_reconciliation_repository.dart';

enum OcrTaskStatus {
  queued,
  processing,
  pendingConfirmation,
  confirmed,
  failed,
  timedOut;

  static OcrTaskStatus fromApi(String value) => switch (value) {
    'queued' => OcrTaskStatus.queued,
    'processing' => OcrTaskStatus.processing,
    'pending_confirmation' => OcrTaskStatus.pendingConfirmation,
    'confirmed' => OcrTaskStatus.confirmed,
    'failed' => OcrTaskStatus.failed,
    'timed_out' => OcrTaskStatus.timedOut,
    _ => OcrTaskStatus.failed,
  };

  bool get isPolling => this == queued || this == processing;
}

class OcrTaskFailure {
  const OcrTaskFailure({
    required this.category,
    required this.code,
    required this.message,
  });

  final String category;
  final String code;
  final String message;

  String get userMessage => switch (category) {
    'file' => '文件无法读取或格式不受支持，请检查原始材料。',
    'network' => '网络连接中断，识别服务会按规则自动重试。',
    'timeout' => '识别超时，未重复发送结果未知的请求，你可以重新识别。',
    'provider_unavailable' => '识别服务暂时不可用，请稍后重新识别。',
    'response_format' => '识别结果格式异常，未生成医疗记录。',
    _ => '识别未完成，请稍后重试。',
  };
}

class OcrTask {
  const OcrTask({
    required this.id,
    required this.documentId,
    required this.documentRevisionId,
    required this.materialType,
    required this.status,
    required this.attemptNumber,
    required this.providerAttempts,
    this.parentTaskId,
    this.error,
    this.reused = false,
  });

  final String id;
  final String documentId;
  final String documentRevisionId;
  final String materialType;
  final OcrTaskStatus status;
  final int attemptNumber;
  final int providerAttempts;
  final String? parentTaskId;
  final OcrTaskFailure? error;
  final bool reused;

  factory OcrTask.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    return OcrTask(
      id: json['id'] as String,
      documentId: json['document_id'] as String,
      documentRevisionId: json['document_revision_id'] as String,
      materialType: json['material_type'] as String,
      status: OcrTaskStatus.fromApi(json['status'] as String),
      attemptNumber: json['attempt_number'] as int,
      providerAttempts: json['provider_attempts'] as int,
      parentTaskId: json['parent_task_id'] as String?,
      error: error is Map
          ? OcrTaskFailure(
              category: error['category']?.toString() ?? 'unknown',
              code: error['code']?.toString() ?? 'OCR_UNKNOWN',
              message: error['message']?.toString() ?? '',
            )
          : null,
      reused: json['reused'] as bool? ?? false,
    );
  }
}

class OcrFieldDraft {
  const OcrFieldDraft({
    required this.path,
    required this.value,
    required this.confidence,
    this.sourceText,
    this.uncertaintyReason,
    this.sourceRegion,
  });

  final String path;
  final Object? value;
  final double confidence;
  final String? sourceText;
  final String? uncertaintyReason;
  final Map<String, dynamic>? sourceRegion;
}

class OcrSourceDocument {
  const OcrSourceDocument({
    required this.documentId,
    required this.revisionId,
    required this.fileName,
    required this.mimeType,
    required this.revisionNumber,
  });

  final String documentId;
  final String revisionId;
  final String fileName;
  final String mimeType;
  final int revisionNumber;

  factory OcrSourceDocument.fromJson(Map<String, dynamic> json) =>
      OcrSourceDocument(
        documentId: json['document_id'] as String,
        revisionId: json['document_revision_id'] as String,
        fileName: json['original_file_name'] as String,
        mimeType: json['mime_type'] as String,
        revisionNumber: json['revision_number'] as int,
      );
}

class OcrTaskResult {
  const OcrTaskResult({
    required this.resultId,
    required this.taskId,
    required this.draft,
    required this.fields,
    this.sourceDocument,
  });

  final String resultId;
  final String taskId;
  final Map<String, dynamic> draft;
  final List<OcrFieldDraft> fields;
  final OcrSourceDocument? sourceDocument;

  factory OcrTaskResult.fromJson(Map<String, dynamic> json) => OcrTaskResult(
    resultId: json['id'] as String,
    taskId: json['task_id'] as String,
    draft: Map<String, dynamic>.from(json['validated_draft'] as Map),
    fields: (json['fields'] as List).map((item) {
      final value = Map<String, dynamic>.from(item as Map);
      return OcrFieldDraft(
        path: value['path'] as String,
        value: value['parsed_value'],
        confidence: (value['confidence'] as num).toDouble(),
        sourceText: value['source_text'] as String?,
        uncertaintyReason: value['uncertainty_reason'] as String?,
        sourceRegion: value['source_region'] == null
            ? null
            : Map<String, dynamic>.from(value['source_region'] as Map),
      );
    }).toList(),
    sourceDocument: json['source_document'] == null
        ? null
        : OcrSourceDocument.fromJson(
            Map<String, dynamic>.from(json['source_document'] as Map),
          ),
  );
}

class LabConfirmationItem {
  const LabConfirmationItem({
    required this.name,
    required this.value,
    required this.unit,
    this.referenceRange,
    this.sampleDate,
    this.examDate,
    this.reportDate,
    this.visitDate,
    this.note,
  });

  final String name;
  final String value;
  final String unit;
  final String? referenceRange;
  final String? sampleDate;
  final String? examDate;
  final String? reportDate;
  final String? visitDate;
  final String? note;

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'unit': unit,
    'reference_range': _emptyAsNull(referenceRange),
    'sample_date': _emptyAsNull(sampleDate),
    'exam_date': _emptyAsNull(examDate),
    'report_date': _emptyAsNull(reportDate),
    'visit_date': _emptyAsNull(visitDate),
    'note': _emptyAsNull(note),
  };
}

class LabObservationSummary {
  const LabObservationSummary({
    required this.id,
    required this.name,
    required this.value,
    required this.unit,
    required this.abnormalStatus,
    required this.mappingStatus,
    this.metricId,
    this.trendDate,
  });

  final String id;
  final String name;
  final String value;
  final String unit;
  final String abnormalStatus;
  final String mappingStatus;
  final String? metricId;
  final String? trendDate;

  factory LabObservationSummary.fromJson(Map<String, dynamic> json) =>
      LabObservationSummary(
        id: json['id'] as String,
        name: json['original_item_name'] as String,
        value: json['numeric_value'].toString(),
        unit: json['standard_unit'] as String,
        abnormalStatus: json['abnormal_status'] as String,
        mappingStatus: json['mapping_status'] as String,
        metricId: json['standard_metric_id'] as String?,
        trendDate: json['trend_date'] as String?,
      );
}

class LabConfirmationResult {
  const LabConfirmationResult({
    required this.taskId,
    required this.reused,
    required this.confirmedAt,
    required this.observations,
  });

  final String taskId;
  final bool reused;
  final DateTime? confirmedAt;
  final List<LabObservationSummary> observations;

  factory LabConfirmationResult.fromJson(Map<String, dynamic> json) =>
      LabConfirmationResult(
        taskId: json['task_id'] as String,
        reused: json['reused'] as bool? ?? false,
        confirmedAt: json['confirmed_at'] == null
            ? null
            : DateTime.parse(json['confirmed_at'] as String),
        observations: (json['observations'] as List)
            .map(
              (value) => LabObservationSummary.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
      );
}

class OcrFieldError {
  const OcrFieldError({
    required this.path,
    required this.code,
    required this.message,
  });
  final String path;
  final String code;
  final String message;
}

abstract interface class OcrRepository {
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  });
  Future<OcrTask> get(String taskId);
  Future<OcrTaskResult> result(String taskId);
  Future<OcrTask> retry(String taskId);
  Future<LabConfirmationResult> confirmLab({
    required String taskId,
    required String resultId,
    required String expectedRevisionId,
    required List<LabConfirmationItem> items,
    String? sampleDate,
    String? examDate,
    String? reportDate,
    String? visitDate,
  });
}

class FastApiOcrRepository implements OcrRepository, MedicalOrderGateway {
  FastApiOcrRepository(this.client);

  final PomiApiClient client;
  late final MedicalOrderGateway _orders = FastApiMedicalOrderGateway(client);

  @override
  Future<void> confirmMedicalOrder(
    String taskId,
    List<MedicalOrderDraft> items,
  ) => _orders.confirmMedicalOrder(taskId, items);

  @override
  Future<MedicationReconciliationDraft> createReconciliation(String taskId) =>
      _orders.createReconciliation(taskId);

  @override
  Future<MedicationReconciliationDraft> executeReconciliation(
    MedicationReconciliationDraft reconciliation,
  ) => _orders.executeReconciliation(reconciliation);

  @override
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  }) => _taskRequest(
    () => client.dio.post<Map<String, dynamic>>(
      '/ocr/tasks',
      data: {'document_id': documentId, 'document_revision_id': revisionId},
    ),
  );

  @override
  Future<OcrTask> get(String taskId) => _taskRequest(
    () => client.dio.get<Map<String, dynamic>>('/ocr/tasks/$taskId'),
  );

  @override
  Future<OcrTaskResult> result(String taskId) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/ocr/tasks/$taskId/result',
      );
      return OcrTaskResult.fromJson(_data(response.data!));
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<OcrTask> retry(String taskId) => _taskRequest(
    () => client.dio.post<Map<String, dynamic>>('/ocr/tasks/$taskId/retry'),
  );

  @override
  Future<LabConfirmationResult> confirmLab({
    required String taskId,
    required String resultId,
    required String expectedRevisionId,
    required List<LabConfirmationItem> items,
    String? sampleDate,
    String? examDate,
    String? reportDate,
    String? visitDate,
  }) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/ocr/tasks/$taskId/confirm',
        data: {
          'result_id': resultId,
          'expected_revision_id': expectedRevisionId,
          'visit_id': null,
          'sample_date': _emptyAsNull(sampleDate),
          'exam_date': _emptyAsNull(examDate),
          'report_date': _emptyAsNull(reportDate),
          'visit_date': _emptyAsNull(visitDate),
          'items': items.map((item) => item.toJson()).toList(),
        },
      );
      return LabConfirmationResult.fromJson(_data(response.data!));
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  Future<OcrTask> _taskRequest(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      final response = await request();
      return OcrTask.fromJson(_data(response.data!));
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) =>
      Map<String, dynamic>.from(envelope['data'] as Map);

  OcrException _failure(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      final value = body['error'] as Map;
      return OcrException(
        value['code']?.toString() ?? 'OCR_REQUEST_FAILED',
        value['message']?.toString() ?? '识别请求失败',
        fieldErrors: _fieldErrors(value),
      );
    }
    return const OcrException('NETWORK_ERROR', '网络连接中断，请稍后重试。');
  }

  List<OcrFieldError> _fieldErrors(Map value) {
    final details = value['details'];
    if (details is! Map || details['fields'] is! List) return const [];
    return (details['fields'] as List)
        .whereType<Map>()
        .map(
          (field) => OcrFieldError(
            path: field['path']?.toString() ?? '',
            code: field['code']?.toString() ?? 'LAB_FIELD_INVALID',
            message: field['message']?.toString() ?? '字段无效',
          ),
        )
        .toList();
  }
}

class OcrException implements Exception {
  const OcrException(this.code, this.message, {this.fieldErrors = const []});
  final String code;
  final String message;
  final List<OcrFieldError> fieldErrors;

  @override
  String toString() => message;
}

class DemoOcrRepository implements OcrRepository, MedicalOrderGateway {
  final Map<String, OcrTask> _tasks = {};
  final Map<String, int> _polls = {};

  @override
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  }) async {
    final existing = _tasks.values.where(
      (task) => task.documentRevisionId == revisionId,
    );
    if (existing.isNotEmpty) return existing.first;
    final task = OcrTask(
      id: 'demo-ocr-${_tasks.length + 1}',
      documentId: documentId,
      documentRevisionId: revisionId,
      materialType: 'lab_report',
      status: OcrTaskStatus.queued,
      attemptNumber: 1,
      providerAttempts: 0,
    );
    _tasks[task.id] = task;
    return task;
  }

  @override
  Future<OcrTask> get(String taskId) async {
    final current = _tasks[taskId]!;
    final polls = (_polls[taskId] ?? 0) + 1;
    _polls[taskId] = polls;
    final updated = OcrTask(
      id: current.id,
      documentId: current.documentId,
      documentRevisionId: current.documentRevisionId,
      materialType: current.materialType,
      status: polls > 1
          ? OcrTaskStatus.pendingConfirmation
          : OcrTaskStatus.processing,
      attemptNumber: current.attemptNumber,
      providerAttempts: polls,
    );
    _tasks[taskId] = updated;
    return updated;
  }

  @override
  Future<OcrTaskResult> result(String taskId) async => OcrTaskResult(
    resultId: 'demo-result-1',
    taskId: taskId,
    draft: const {
      'report_date': '2026-08-20',
      'items': [
        {
          'name': '空腹血糖',
          'value': '5.2',
          'unit': 'mmol/L',
          'reference_range': '3.9-6.1',
        },
      ],
    },
    fields: const [
      OcrFieldDraft(
        path: 'items.0.value',
        value: '5.2',
        confidence: 0.72,
        sourceText: '5.2',
      ),
    ],
  );

  @override
  Future<OcrTask> retry(String taskId) async => _tasks[taskId]!;

  @override
  Future<void> confirmMedicalOrder(
    String taskId,
    List<MedicalOrderDraft> items,
  ) async {}

  @override
  Future<MedicationReconciliationDraft> createReconciliation(
    String taskId,
  ) async => const MedicationReconciliationDraft(
    id: 'demo-reconciliation',
    status: 'draft',
    ruleVersion: 'pomi-med-reconcile-v1',
    items: [],
  );

  @override
  Future<MedicationReconciliationDraft> executeReconciliation(
    MedicationReconciliationDraft reconciliation,
  ) async => MedicationReconciliationDraft(
    id: reconciliation.id,
    status: 'executed',
    ruleVersion: reconciliation.ruleVersion,
    items: reconciliation.items,
  );

  @override
  Future<LabConfirmationResult> confirmLab({
    required String taskId,
    required String resultId,
    required String expectedRevisionId,
    required List<LabConfirmationItem> items,
    String? sampleDate,
    String? examDate,
    String? reportDate,
    String? visitDate,
  }) async => LabConfirmationResult(
    taskId: taskId,
    reused: false,
    confirmedAt: DateTime.now(),
    observations: [
      for (var index = 0; index < items.length; index++)
        LabObservationSummary(
          id: 'demo-lab-$index',
          name: items[index].name,
          value: items[index].value,
          unit: items[index].unit,
          abnormalStatus: 'unknown',
          mappingStatus: 'needs_manual_review',
        ),
    ],
  );
}

String? _emptyAsNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
