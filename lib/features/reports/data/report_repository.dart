import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';

class ReportPreflight {
  const ReportPreflight({
    required this.missingSections,
    required this.canGenerate,
    required this.confirmedSourceCount,
  });

  final List<String> missingSections;
  final bool canGenerate;
  final int confirmedSourceCount;

  factory ReportPreflight.fromJson(Map<String, dynamic> json) =>
      ReportPreflight(
        missingSections: List<String>.from(json['missing_sections'] as List),
        canGenerate: json['can_generate'] as bool,
        confirmedSourceCount: json['confirmed_source_count'] as int,
      );
}

class ReportSnapshotItem {
  const ReportSnapshotItem({
    required this.reportId,
    required this.status,
    required this.generatedAt,
    required this.snapshotHash,
    required this.sourceDigest,
    required this.hasUpdates,
    required this.reused,
    required this.missingSections,
    this.previousReportId,
    this.snapshot,
    this.dateSources = const {},
    this.dataFreshness = const {},
  });

  final String reportId;
  final String status;
  final DateTime generatedAt;
  final String snapshotHash;
  final String sourceDigest;
  final String? previousReportId;
  final bool hasUpdates;
  final bool reused;
  final List<String> missingSections;
  final Map<String, dynamic>? snapshot;
  final Map<String, dynamic> dateSources;
  final Map<String, dynamic> dataFreshness;

  factory ReportSnapshotItem.fromJson(Map<String, dynamic> json) =>
      ReportSnapshotItem(
        reportId: json['report_id'] as String,
        status: json['status'] as String,
        generatedAt: DateTime.parse(json['generated_at'] as String),
        snapshotHash: json['snapshot_hash'] as String,
        sourceDigest: json['source_digest'] as String,
        previousReportId: json['previous_report_id'] as String?,
        hasUpdates: json['has_updates'] as bool? ?? false,
        reused: json['reused'] as bool? ?? false,
        missingSections: List<String>.from(
          json['missing_sections'] as List? ?? const [],
        ),
        snapshot: json['snapshot'] == null
            ? null
            : Map<String, dynamic>.from(json['snapshot'] as Map),
        dateSources: Map<String, dynamic>.from(
          json['date_sources'] as Map? ?? const {},
        ),
        dataFreshness: Map<String, dynamic>.from(
          json['data_freshness'] as Map? ?? const {},
        ),
      );
}

class ReportDetail {
  const ReportDetail({
    required this.item,
    required this.metadata,
    required this.summary,
    required this.trends,
    required this.records,
    required this.sources,
    required this.dataFreshness,
  });

  final ReportSnapshotItem item;
  final Map<String, dynamic> metadata;
  final ReportSummary summary;
  final ReportTrends trends;
  final Map<String, dynamic> records;
  final List<ReportSource> sources;
  final Map<String, dynamic> dataFreshness;

  factory ReportDetail.fromJson(Map<String, dynamic> json) => ReportDetail(
    item: ReportSnapshotItem.fromJson(json),
    metadata: _jsonMap(json['metadata']),
    summary: ReportSummary.fromJson(_jsonMap(json['summary'])),
    trends: ReportTrends.fromJson(_jsonMap(json['trends'])),
    records: _jsonMap(json['records']),
    sources: _jsonList(json['sources'])
        .map((value) => ReportSource.fromJson(_jsonMap(value)))
        .toList(growable: false),
    dataFreshness: _jsonMap(json['data_freshness']),
  );

  ReportSource? sourceFor(String nodeId) =>
      sources.where((source) => source.nodeId == nodeId).firstOrNull;
}

class ReportSummary {
  const ReportSummary({
    required this.profile,
    required this.currentMedications,
    required this.latestObservations,
    required this.missingSections,
    required this.disclaimers,
    this.patientNoteText,
    this.patientNoteEmptyState,
  });

  final Map<String, dynamic> profile;
  final String? patientNoteText;
  final String? patientNoteEmptyState;
  final List<Map<String, dynamic>> currentMedications;
  final List<ReportTrendPoint> latestObservations;
  final List<String> missingSections;
  final List<String> disclaimers;

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
    profile: _jsonMap(json['profile']),
    patientNoteText: json['patient_note_text'] as String?,
    patientNoteEmptyState: json['patient_note_empty_state'] as String?,
    currentMedications: _jsonList(json['current_medications'])
        .map(_jsonMap)
        .toList(growable: false),
    latestObservations: _jsonList(json['latest_observations'])
        .map((value) => ReportTrendPoint.fromJson(_jsonMap(value)))
        .toList(growable: false),
    missingSections: List<String>.from(
      json['missing_sections'] as List? ?? const [],
    ),
    disclaimers: List<String>.from(json['disclaimers'] as List? ?? const []),
  );
}

class ReportTrends {
  const ReportTrends({
    required this.labs,
    required this.weights,
    required this.cycles,
    required this.medicationDaily,
  });

  final List<ReportTrend> labs;
  final List<ReportTrendPoint> weights;
  final List<ReportTrendPoint> cycles;
  final List<ReportTrendPoint> medicationDaily;

  factory ReportTrends.fromJson(Map<String, dynamic> json) => ReportTrends(
    labs: _jsonList(json['labs'])
        .map((value) => ReportTrend.fromJson(_jsonMap(value)))
        .toList(growable: false),
    weights: _points(json['weights']),
    cycles: _points(json['cycles']),
    medicationDaily: _points(json['medication_daily']),
  );

  static List<ReportTrendPoint> _points(dynamic value) =>
      _jsonList(value)
          .map((item) => ReportTrendPoint.fromJson(_jsonMap(item)))
          .toList(growable: false);
}

class ReportTrend {
  const ReportTrend({
    required this.metricId,
    required this.metricName,
    required this.comparability,
    required this.displayMode,
    required this.points,
    this.unit,
    this.comparabilityReason,
  });

  final String metricId;
  final String metricName;
  final String? unit;
  final String comparability;
  final String? comparabilityReason;
  final String displayMode;
  final List<ReportTrendPoint> points;

  factory ReportTrend.fromJson(Map<String, dynamic> json) => ReportTrend(
    metricId: json['metric_id']?.toString() ?? 'unknown',
    metricName: json['metric_name']?.toString() ?? '未命名指标',
    unit: json['unit'] as String?,
    comparability: json['comparability']?.toString() ?? 'incomparable',
    comparabilityReason: json['comparability_reason'] as String?,
    displayMode: json['display_mode']?.toString() ?? 'single_result',
    points: _jsonList(json['points'])
        .map((value) => ReportTrendPoint.fromJson(_jsonMap(value)))
        .toList(growable: false),
  );
}

class ReportTrendPoint {
  const ReportTrendPoint({
    required this.nodeId,
    required this.sourceNumber,
    required this.rawValue,
    required this.freshness,
    required this.comparability,
    this.normalizedValue,
    this.originalUnit,
    this.normalizedUnit,
    this.date,
    this.dateSource,
    this.abnormalStatus = 'unknown',
    this.exclusionReason,
    this.referenceRange,
    this.defaultCollapsed = false,
    this.record,
  });

  final String nodeId;
  final int sourceNumber;
  final String rawValue;
  final num? normalizedValue;
  final String? originalUnit;
  final String? normalizedUnit;
  final DateTime? date;
  final String? dateSource;
  final String freshness;
  final String comparability;
  final String abnormalStatus;
  final String? exclusionReason;
  final String? referenceRange;
  final bool defaultCollapsed;
  final Map<String, dynamic>? record;

  bool get isComparable => comparability == 'comparable';

  factory ReportTrendPoint.fromJson(Map<String, dynamic> json) =>
      ReportTrendPoint(
        nodeId: json['node_id']?.toString() ?? '',
        sourceNumber: json['source_number'] as int? ?? 0,
        rawValue:
            json['raw_value']?.toString() ??
            json['weight_kg']?.toString() ??
            json['intake_status']?.toString() ??
            json['start_date']?.toString() ??
            '—',
        normalizedValue:
            (json['normalized_value'] ??
                    json['numeric_value'] ??
                    json['weight_kg'])
                as num?,
        originalUnit: json['original_unit'] as String?,
        normalizedUnit:
            (json['normalized_unit'] ?? json['standard_unit']) as String?,
        date: DateTime.tryParse(json['date']?.toString() ?? ''),
        dateSource: json['date_source'] as String?,
        freshness: json['freshness']?.toString() ?? 'unknown',
        comparability: json['comparability']?.toString() ?? 'not_applicable',
        abnormalStatus: json['abnormal_status']?.toString() ?? 'unknown',
        exclusionReason: json['exclusion_reason'] as String?,
        referenceRange: json['reference_range_raw'] as String?,
        defaultCollapsed: json['default_collapsed'] as bool? ?? false,
        record: json,
      );
}

class ReportSource {
  const ReportSource({
    required this.nodeId,
    required this.sourceNumber,
    required this.sourceType,
    required this.sourceRecordId,
    required this.originKind,
    required this.freshness,
    required this.comparability,
    required this.snapshotRecord,
    this.documentId,
    this.documentRevisionId,
    this.ruleExecutionId,
    this.originalValue,
    this.originalUnit,
    this.normalizedValue,
    this.normalizedUnit,
    this.referenceRangeText,
    this.materialDate,
    this.dateSource,
    this.exclusionReason,
    this.file,
  });

  final String nodeId;
  final int sourceNumber;
  final String sourceType;
  final String sourceRecordId;
  final String originKind;
  final String? documentId;
  final String? documentRevisionId;
  final String? ruleExecutionId;
  final String? originalValue;
  final String? originalUnit;
  final num? normalizedValue;
  final String? normalizedUnit;
  final String? referenceRangeText;
  final DateTime? materialDate;
  final String? dateSource;
  final String freshness;
  final String comparability;
  final String? exclusionReason;
  final Map<String, dynamic> snapshotRecord;
  final ReportSourceFile? file;

  bool get isManual => originKind == 'patient_manual';

  factory ReportSource.fromJson(Map<String, dynamic> json) => ReportSource(
    nodeId: json['node_id'] as String,
    sourceNumber: json['source_number'] as int,
    sourceType: json['source_type'] as String,
    sourceRecordId: json['source_record_id'] as String,
    originKind: json['origin_kind'] as String,
    documentId: json['document_id'] as String?,
    documentRevisionId: json['document_revision_id'] as String?,
    ruleExecutionId: json['rule_execution_id'] as String?,
    originalValue: json['original_value'] as String?,
    originalUnit: json['original_unit'] as String?,
    normalizedValue: json['normalized_value'] as num?,
    normalizedUnit: json['normalized_unit'] as String?,
    referenceRangeText: json['reference_range_text'] as String?,
    materialDate: DateTime.tryParse(json['material_date']?.toString() ?? ''),
    dateSource: json['date_source'] as String?,
    freshness: json['freshness']?.toString() ?? 'unknown',
    comparability: json['comparability']?.toString() ?? 'not_applicable',
    exclusionReason: json['exclusion_reason'] as String?,
    snapshotRecord: _jsonMap(json['snapshot_record']),
    file: json['file'] is Map
        ? ReportSourceFile.fromJson(_jsonMap(json['file']))
        : null,
  );
}

class ReportSourceFile {
  const ReportSourceFile({
    required this.status,
    this.url,
    this.mimeType,
    this.fileName,
    this.revisionNumber,
    this.fileHash,
    this.errorCode,
    this.errorMessage,
  });

  final String status;
  final String? url;
  final String? mimeType;
  final String? fileName;
  final int? revisionNumber;
  final String? fileHash;
  final String? errorCode;
  final String? errorMessage;

  bool get isAvailable => status == 'available' && url != null;

  factory ReportSourceFile.fromJson(Map<String, dynamic> json) =>
      ReportSourceFile(
        status: json['status']?.toString() ?? 'unavailable',
        url: json['url'] as String?,
        mimeType: json['mime_type'] as String?,
        fileName: json['file_name'] as String?,
        revisionNumber: json['revision_number'] as int?,
        fileHash: json['file_hash'] as String?,
        errorCode: json['error_code'] as String?,
        errorMessage: json['error_message'] as String?,
      );
}

Map<String, dynamic> _jsonMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<dynamic> _jsonList(dynamic value) => value is List ? value : const [];

abstract interface class ReportRepository {
  Future<ReportPreflight> preflight(String? patientNoteId);
  Future<ReportSnapshotItem> create(
    String? patientNoteId, {
    required bool confirmIncomplete,
  });
  Future<List<ReportSnapshotItem>> list();
  Future<ReportDetail> get(String reportId);
}

class FastApiReportRepository implements ReportRepository {
  FastApiReportRepository(this.client);

  final PomiApiClient client;

  Map<String, dynamic> _payload(
    String? patientNoteId, {
    bool confirmIncomplete = false,
  }) => {
    'patient_note_id': patientNoteId,
    'confirm_incomplete': confirmIncomplete,
  };

  @override
  Future<ReportPreflight> preflight(String? patientNoteId) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/reports/preflight',
        data: _payload(patientNoteId),
      );
      return ReportPreflight.fromJson(
        Map<String, dynamic>.from(response.data!['data'] as Map),
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ReportSnapshotItem> create(
    String? patientNoteId, {
    required bool confirmIncomplete,
  }) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/reports',
        data: _payload(patientNoteId, confirmIncomplete: confirmIncomplete),
        options: Options(
          headers: {
            'Idempotency-Key':
                'report-${patientNoteId ?? 'skipped'}-${confirmIncomplete ? 'confirmed' : 'complete'}',
          },
        ),
      );
      return ReportSnapshotItem.fromJson(
        Map<String, dynamic>.from(response.data!['data'] as Map),
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<ReportSnapshotItem>> list() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>('/reports');
      final data = Map<String, dynamic>.from(response.data!['data'] as Map);
      return (data['items'] as List)
          .map(
            (item) => ReportSnapshotItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ReportDetail> get(String reportId) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/reports/$reportId',
      );
      return ReportDetail.fromJson(
        Map<String, dynamic>.from(response.data!['data'] as Map),
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  ReportFailure _failure(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      return ReportFailure(
        (body['error'] as Map)['message']?.toString() ?? '报告生成失败',
      );
    }
    return const ReportFailure('网络中断，已确认数据不会丢失，请稍后重试');
  }
}

class DemoReportRepository implements ReportRepository {
  DemoReportRepository({this.missingSections = const []});

  final List<String> missingSections;
  final List<ReportSnapshotItem> _items = [];

  @override
  Future<ReportPreflight> preflight(String? patientNoteId) async =>
      ReportPreflight(
        missingSections: missingSections,
        canGenerate: missingSections.isEmpty,
        confirmedSourceCount: 24,
      );

  @override
  Future<ReportSnapshotItem> create(
    String? patientNoteId, {
    required bool confirmIncomplete,
  }) async {
    if (missingSections.isNotEmpty && !confirmIncomplete) {
      throw const ReportFailure('请先确认缺失资料');
    }
    if (_items.isNotEmpty && !_items.first.hasUpdates) {
      return _copy(_items.first, reused: true);
    }
    final item = ReportSnapshotItem(
      reportId: 'demo-report-${_items.length + 1}',
      status: 'succeeded',
      generatedAt: DateTime.now(),
      snapshotHash: 'd' * 64,
      sourceDigest: 'e' * 64,
      previousReportId: _items.isEmpty ? null : _items.first.reportId,
      hasUpdates: false,
      reused: false,
      missingSections: missingSections,
    );
    _items.insert(0, item);
    return item;
  }

  @override
  Future<List<ReportSnapshotItem>> list() async => List.unmodifiable(_items);

  @override
  Future<ReportDetail> get(String reportId) async =>
      ReportDetail.fromJson(_demoReportDetail(reportId));

  ReportSnapshotItem _copy(ReportSnapshotItem item, {required bool reused}) =>
      ReportSnapshotItem(
        reportId: item.reportId,
        status: item.status,
        generatedAt: item.generatedAt,
        snapshotHash: item.snapshotHash,
        sourceDigest: item.sourceDigest,
        previousReportId: item.previousReportId,
        hasUpdates: item.hasUpdates,
        reused: reused,
        missingSections: item.missingSections,
        snapshot: item.snapshot,
        dateSources: item.dateSources,
        dataFreshness: item.dataFreshness,
      );
}

Map<String, dynamic> _demoReportDetail(String reportId) {
  Map<String, dynamic> point(
    String id,
    int source,
    String raw,
    num? normalized,
    String? date, {
    String comparability = 'comparable',
    String? reason,
    bool archived = false,
  }) => {
    'id': 'record-$id',
    'node_id': id,
    'source_number': source,
    'raw_value': raw,
    'numeric_value': normalized,
    'normalized_value': normalized,
    'original_unit': 'mmol/L',
    'standard_unit': 'mmol/L',
    'normalized_unit': 'mmol/L',
    'reference_range_raw': '3.9–6.1',
    'date': date,
    'date_source': date == null ? null : 'sample_date',
    'freshness': archived ? 'archived' : 'current',
    'default_collapsed': archived,
    'comparability': comparability,
    'exclusion_reason': reason,
    'abnormal_status': normalized != null && normalized > 6.1
        ? 'high'
        : 'normal',
  };

  final labPoints = [
    point('source-1', 1, '5.4', 5.4, '2025-04-12', archived: true),
    point('source-2', 2, '5.8', 5.8, '2026-06-18'),
    point('source-3', 3, '6.3', 6.3, '2026-08-26'),
    point(
      'source-4',
      4,
      'positive',
      null,
      null,
      comparability: 'incomparable',
      reason: 'metric_needs_manual_review',
    ),
  ];
  final singlePoints = [point('source-5', 5, '2.1', 2.1, '2026-08-20')];
  final doublePoints = [
    point('source-6', 6, '5.8', 5.8, '2026-03-20'),
    point('source-7', 7, '5.5', 5.5, '2026-08-20'),
  ];
  final sourceNodes = [
    for (final value in [...labPoints, ...singlePoints, ...doublePoints])
      {
        'node_id': value['node_id'],
        'source_number': value['source_number'],
        'source_type': 'lab_observation',
        'source_record_id': value['id'],
        'origin_kind': 'medical_document',
        'document_id': 'demo-document-${value['source_number']}',
        'document_revision_id': 'demo-revision-${value['source_number']}',
        'rule_execution_id': null,
        'original_value': value['raw_value'],
        'original_unit': value['original_unit'],
        'normalized_value': value['normalized_value'],
        'normalized_unit': value['normalized_unit'],
        'reference_range_text': value['reference_range_raw'],
        'material_date': value['date'],
        'date_source': value['date_source'],
        'freshness': value['freshness'],
        'comparability': value['comparability'],
        'exclusion_reason': value['exclusion_reason'],
        'snapshot_record': value,
        'file': {
          'status': value['source_number'] == 4 ? 'unavailable' : 'available',
          'url': value['source_number'] == 4
              ? null
              : '/api/documents/demo-document-${value['source_number']}/revisions/demo-revision-${value['source_number']}/file',
          'mime_type': 'image/png',
          'file_name': '化验单 ${value['source_number']}.png',
          'revision_number': 1,
          'file_hash': 'demo-file-hash-${value['source_number']}',
          'error_code': value['source_number'] == 4
              ? 'SOURCE_FILE_UNAVAILABLE'
              : null,
          'error_message': value['source_number'] == 4
              ? '原始文件暂时不可用，快照中的结构化原值仍可查看。'
              : null,
        },
      },
    for (final value in const [
      (
        nodeId: 'weight-source-1',
        source: 8,
        type: 'weight_record',
        recordId: 'weight-1',
        original: '69.6',
        date: '2026-08-20',
      ),
      (
        nodeId: 'cycle-source-1',
        source: 9,
        type: 'menstrual_cycle',
        recordId: 'cycle-1',
        original: '2026-08-02',
        date: '2026-08-02',
      ),
      (
        nodeId: 'daily-source-1',
        source: 10,
        type: 'medication_daily',
        recordId: 'daily-1',
        original: 'taken',
        date: '2026-08-26',
      ),
    ])
      {
        'node_id': value.nodeId,
        'source_number': value.source,
        'source_type': value.type,
        'source_record_id': value.recordId,
        'origin_kind': 'patient_manual',
        'document_id': null,
        'document_revision_id': null,
        'rule_execution_id': null,
        'original_value': value.original,
        'original_unit': value.type == 'weight_record' ? 'kg' : null,
        'normalized_value': value.type == 'weight_record' ? 69.6 : null,
        'normalized_unit': value.type == 'weight_record' ? 'kg' : null,
        'reference_range_text': null,
        'material_date': value.date,
        'date_source': 'record_date',
        'freshness': 'current',
        'comparability': 'not_applicable',
        'exclusion_reason': null,
        'snapshot_record': const <String, dynamic>{},
        'file': null,
      },
  ];
  return {
    'report_id': reportId,
    'status': 'succeeded',
    'generated_at': '2026-08-27T12:00:00Z',
    'snapshot_hash': 'd' * 64,
    'source_digest': 'e' * 64,
    'previous_report_id': null,
    'has_updates': false,
    'reused': false,
    'missing_sections': const [],
    'metadata': {
      'rule_version': 'report-rules-v1',
      'template_version': 'report-snapshot-v1',
      'generated_at': '2026-08-27T12:00:00Z',
      'simulated_data': true,
    },
    'summary': {
      'profile': {
        'nickname': '林晓晴',
        'birth_date': '1997-03-12',
        'primary_condition': 'PCOS',
        'next_visit_date': '2026-09-06',
      },
      'patient_note_text': '最近两个月经期仍不规律，希望复诊时讨论用药感受。',
      'patient_note_empty_state': null,
      'current_medications': [
        {'drug_name': '二甲双胍', 'dosage_value': 500, 'dosage_unit': 'mg'},
        {'drug_name': '叶酸', 'dosage_value': 0.4, 'dosage_unit': 'mg'},
      ],
      'latest_observations': [labPoints[2]],
      'missing_sections': const ['imaging'],
      'disclaimers': const ['模拟数据，仅供演示。', '本报告只整理已确认快照，不构成诊断或治疗建议。'],
    },
    'trends': {
      'labs': [
        {
          'metric_id': 'glucose',
          'metric_name': '空腹血糖',
          'unit': 'mmol/L',
          'comparability': 'incomparable',
          'comparability_reason': '部分结果待人工确认',
          'display_mode': 'trend',
          'points': labPoints,
        },
        {
          'metric_id': 'single',
          'metric_name': '促甲状腺激素',
          'unit': 'mIU/L',
          'comparability': 'comparable',
          'display_mode': 'single_result',
          'points': singlePoints,
        },
        {
          'metric_id': 'double',
          'metric_name': '糖化血红蛋白',
          'unit': '%',
          'comparability': 'comparable',
          'display_mode': 'comparison',
          'points': doublePoints,
        },
      ],
      'weights': [
        {
          'id': 'weight-1',
          'node_id': 'weight-source-1',
          'source_number': 8,
          'weight_kg': 69.6,
          'date': '2026-08-20',
          'date_source': 'record_date',
          'freshness': 'current',
        },
      ],
      'cycles': [
        {
          'id': 'cycle-1',
          'node_id': 'cycle-source-1',
          'source_number': 9,
          'start_date': '2026-08-02',
          'date': '2026-08-02',
          'date_source': 'record_date',
          'freshness': 'current',
        },
      ],
      'medication_daily': [
        {
          'id': 'daily-1',
          'node_id': 'daily-source-1',
          'source_number': 10,
          'intake_status': 'taken',
          'date': '2026-08-26',
          'date_source': 'record_date',
          'freshness': 'current',
        },
      ],
    },
    'records': const {
      'medication_history': [],
      'medication_events': [],
      'medical_orders': [],
      'imaging': [],
      'outpatient': [],
    },
    'sources': sourceNodes,
    'data_freshness': const {},
  };
}

class ReportFailure implements Exception {
  const ReportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
