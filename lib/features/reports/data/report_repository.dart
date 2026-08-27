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

abstract interface class ReportRepository {
  Future<ReportPreflight> preflight(String? patientNoteId);
  Future<ReportSnapshotItem> create(
    String? patientNoteId, {
    required bool confirmIncomplete,
  });
  Future<List<ReportSnapshotItem>> list();
  Future<ReportSnapshotItem> get(String reportId);
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
  Future<ReportSnapshotItem> get(String reportId) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/reports/$reportId',
      );
      return ReportSnapshotItem.fromJson(
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
  Future<ReportSnapshotItem> get(String reportId) async {
    for (final item in _items) {
      if (item.reportId == reportId) return item;
    }
    throw const ReportFailure('报告不存在');
  }

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

class ReportFailure implements Exception {
  const ReportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
