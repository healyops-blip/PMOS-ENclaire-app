import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';

enum PatientNoteStatus { draft, confirmed, skipped, consumed }

class PatientNote {
  const PatientNote({
    required this.id,
    required this.originalText,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.visitContext,
    this.confirmedText,
    this.sourceNoteId,
    this.confirmedAt,
  });

  final String id;
  final String originalText;
  final String? visitContext;
  final String? confirmedText;
  final String? sourceNoteId;
  final PatientNoteStatus status;
  final DateTime? confirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PatientNote.fromJson(Map<String, dynamic> json) => PatientNote(
    id: json['id'] as String,
    originalText: json['original_text'] as String,
    visitContext: json['visit_context'] as String?,
    confirmedText: json['confirmed_text'] as String?,
    sourceNoteId: json['source_note_id'] as String?,
    status: PatientNoteStatus.values.byName(json['status'] as String),
    confirmedAt: json['confirmed_at'] == null
        ? null
        : DateTime.parse(json['confirmed_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}

abstract interface class PatientNoteRepository {
  Future<PatientNote?> latest();
  Future<PatientNote> create(String text, {String? visitContext});
  Future<PatientNote> update(String id, String text, {String? visitContext});
  Future<PatientNote> confirm(String id);
  Future<PatientNote> skip(String id);
  Future<PatientNote> copy(String id, {String? visitContext});
}

class FastApiPatientNoteRepository implements PatientNoteRepository {
  FastApiPatientNoteRepository(this.client);

  final PomiApiClient client;

  @override
  Future<PatientNote?> latest() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/patient-notes/latest',
      );
      final value = response.data!['data'];
      return value == null
          ? null
          : PatientNote.fromJson(Map<String, dynamic>.from(value as Map));
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PatientNote> create(String text, {String? visitContext}) => _request(
    'POST',
    '/patient-notes',
    {'original_text': text, 'visit_context': visitContext},
  );

  @override
  Future<PatientNote> update(String id, String text, {String? visitContext}) =>
      _request('PUT', '/patient-notes/$id', {
        'original_text': text,
        'visit_context': visitContext,
      });

  @override
  Future<PatientNote> confirm(String id) =>
      _request('POST', '/patient-notes/$id/confirm');

  @override
  Future<PatientNote> skip(String id) =>
      _request('POST', '/patient-notes/$id/skip');

  @override
  Future<PatientNote> copy(String id, {String? visitContext}) => _request(
    'POST',
    '/patient-notes/$id/copy',
    {'visit_context': visitContext},
  );

  Future<PatientNote> _request(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final response = await client.dio.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(method: method),
      );
      return PatientNote.fromJson(
        Map<String, dynamic>.from(response.data!['data'] as Map),
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  PatientNoteFailure _failure(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      return PatientNoteFailure(
        (body['error'] as Map)['message']?.toString() ?? '自述保存失败',
      );
    }
    return const PatientNoteFailure('网络中断，输入内容仍保留，可稍后重试');
  }
}

class PatientNoteFailure implements Exception {
  const PatientNoteFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class DemoPatientNoteRepository implements PatientNoteRepository {
  DemoPatientNoteRepository({PatientNote? initial})
    : _note =
          initial ??
          PatientNote(
            id: 'demo-note-1',
            originalText: _sample,
            confirmedText: _sample,
            status: PatientNoteStatus.confirmed,
            confirmedAt: DateTime(2026, 8, 27),
            createdAt: DateTime(2026, 8, 27),
            updatedAt: DateTime(2026, 8, 27),
          );

  static const _sample = '最近两个月经期仍不规律，体重略有下降。二甲双胍偶尔因胃部不适漏服，希望复诊时讨论剂量。';
  PatientNote? _note;
  int _nextId = 2;

  @override
  Future<PatientNote?> latest() async => _note;

  @override
  Future<PatientNote> create(String text, {String? visitContext}) async {
    _note = _make(text, visitContext: visitContext);
    return _note!;
  }

  @override
  Future<PatientNote> update(
    String id,
    String text, {
    String? visitContext,
  }) async {
    _note = _make(text, id: id, visitContext: visitContext);
    return _note!;
  }

  @override
  Future<PatientNote> confirm(String id) async {
    final current = _note!;
    _note = PatientNote(
      id: current.id,
      originalText: current.originalText,
      confirmedText: current.originalText,
      status: PatientNoteStatus.confirmed,
      confirmedAt: DateTime.now(),
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    return _note!;
  }

  @override
  Future<PatientNote> skip(String id) async {
    final current = _note!;
    _note = PatientNote(
      id: current.id,
      originalText: current.originalText,
      status: PatientNoteStatus.skipped,
      confirmedAt: DateTime.now(),
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    return _note!;
  }

  @override
  Future<PatientNote> copy(String id, {String? visitContext}) async {
    _note = _make(
      _note!.confirmedText ?? _note!.originalText,
      visitContext: visitContext,
      sourceNoteId: id,
    );
    return _note!;
  }

  PatientNote _make(
    String text, {
    String? id,
    String? visitContext,
    String? sourceNoteId,
  }) => PatientNote(
    id: id ?? 'demo-note-${_nextId++}',
    originalText: text,
    visitContext: visitContext,
    sourceNoteId: sourceNoteId,
    status: PatientNoteStatus.draft,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}
