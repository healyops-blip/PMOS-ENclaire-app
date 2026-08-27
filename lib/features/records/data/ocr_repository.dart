import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';

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

class OcrTaskResult {
  const OcrTaskResult({
    required this.taskId,
    required this.draft,
    required this.fields,
  });

  final String taskId;
  final Map<String, dynamic> draft;
  final List<OcrFieldDraft> fields;

  factory OcrTaskResult.fromJson(Map<String, dynamic> json) => OcrTaskResult(
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
  );
}

abstract interface class OcrRepository {
  Future<OcrTask> create({
    required String documentId,
    required String revisionId,
  });
  Future<OcrTask> get(String taskId);
  Future<OcrTaskResult> result(String taskId);
  Future<OcrTask> retry(String taskId);
}

class FastApiOcrRepository implements OcrRepository {
  FastApiOcrRepository(this.client);

  final PomiApiClient client;

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
      );
    }
    return const OcrException('NETWORK_ERROR', '网络连接中断，请稍后重试。');
  }
}

class OcrException implements Exception {
  const OcrException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

class DemoOcrRepository implements OcrRepository {
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
  Future<OcrTaskResult> result(String taskId) async =>
      OcrTaskResult(taskId: taskId, draft: const {}, fields: const []);

  @override
  Future<OcrTask> retry(String taskId) async => _tasks[taskId]!;
}
