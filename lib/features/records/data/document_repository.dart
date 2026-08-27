import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';

const documentMaxBytes = 20 * 1024 * 1024;
const documentMaxPixels = 25000000;
const documentProcessingNoticeVersion = 'external-ocr-v1';

class MedicalDocument {
  const MedicalDocument({
    required this.id,
    required this.documentType,
    required this.originalFileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.currentRevisionId,
    required this.uploadedAt,
    this.pixelCount,
    this.pageCount = 1,
    this.fileHash = '',
  });

  final String id;
  final String documentType;
  final String originalFileName;
  final String mimeType;
  final int fileSizeBytes;
  final int? pixelCount;
  final int pageCount;
  final String fileHash;
  final String currentRevisionId;
  final DateTime uploadedAt;

  bool get isPdf => mimeType == 'application/pdf';

  factory MedicalDocument.fromJson(Map<String, dynamic> json) =>
      MedicalDocument(
        id: json['id'] as String,
        documentType: json['document_type'] as String,
        originalFileName: json['original_file_name'] as String,
        mimeType: json['mime_type'] as String,
        fileSizeBytes: json['file_size_bytes'] as int,
        pixelCount: json['pixel_count'] as int?,
        pageCount: json['page_count'] as int? ?? 1,
        fileHash: json['file_hash'] as String? ?? '',
        currentRevisionId: json['current_revision_id'] as String,
        uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      );
}

class DocumentRevision {
  const DocumentRevision({
    required this.id,
    required this.revisionNumber,
    required this.mimeType,
    required this.fileHash,
    required this.createdAt,
    this.replacementReason,
  });

  final String id;
  final int revisionNumber;
  final String mimeType;
  final String fileHash;
  final String? replacementReason;
  final DateTime createdAt;

  factory DocumentRevision.fromJson(Map<String, dynamic> json) =>
      DocumentRevision(
        id: json['id'] as String,
        revisionNumber: json['revision_number'] as int,
        mimeType: json['mime_type'] as String,
        fileHash: json['file_hash'] as String,
        replacementReason: json['replacement_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class SelectedDocumentFile {
  const SelectedDocumentFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

abstract interface class DocumentRepository {
  Future<List<MedicalDocument>> list({String? documentType});
  Future<MedicalDocument> get(String id);
  Future<MedicalDocument> upload({
    required SelectedDocumentFile file,
    required String documentType,
    required String consentVersion,
    required String idempotencyKey,
    required void Function(int sent, int total) onProgress,
  });
  Future<List<DocumentRevision>> revisions(String documentId);
  Future<DocumentRevision> replace({
    required String documentId,
    required String expectedRevisionId,
    required String reason,
    required SelectedDocumentFile file,
    required String idempotencyKey,
    required void Function(int sent, int total) onProgress,
  });
  Future<Uint8List> download(String documentId, String revisionId);
  Future<void> delete(String documentId);
}

class FastApiDocumentRepository implements DocumentRepository {
  FastApiDocumentRepository(this.client);

  final PomiApiClient client;

  @override
  Future<List<MedicalDocument>> list({String? documentType}) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/documents',
        queryParameters: documentType == null
            ? null
            : {'document_type': documentType},
      );
      final data = _data(response.data!);
      return (data['items'] as List)
          .map(
            (value) => MedicalDocument.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<MedicalDocument> get(String id) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/documents/$id',
      );
      return MedicalDocument.fromJson(_data(response.data!));
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<MedicalDocument> upload({
    required SelectedDocumentFile file,
    required String documentType,
    required String consentVersion,
    required String idempotencyKey,
    required void Function(int sent, int total) onProgress,
  }) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/documents',
        data: FormData.fromMap({
          'document_type': documentType,
          'external_processing_consent_version': consentVersion,
          'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
        }),
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        onSendProgress: onProgress,
      );
      return MedicalDocument.fromJson(_data(response.data!));
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<DocumentRevision>> revisions(String documentId) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/documents/$documentId/revisions',
      );
      return (_data(response.data!) as List)
          .map(
            (value) => DocumentRevision.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<DocumentRevision> replace({
    required String documentId,
    required String expectedRevisionId,
    required String reason,
    required SelectedDocumentFile file,
    required String idempotencyKey,
    required void Function(int sent, int total) onProgress,
  }) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/documents/$documentId/revisions',
        data: FormData.fromMap({
          'replacement_reason': reason,
          'expected_current_revision_id': expectedRevisionId,
          'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
        }),
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        onSendProgress: onProgress,
      );
      return DocumentRevision.fromJson(_data(response.data!));
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Uint8List> download(String documentId, String revisionId) async {
    try {
      final response = await client.dio.get<List<int>>(
        '/documents/$documentId/revisions/$revisionId/file',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data!);
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> delete(String documentId) async {
    try {
      await client.dio.delete<void>('/documents/$documentId');
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  dynamic _data(Map<String, dynamic> envelope) => envelope['data'];

  DocumentFailure _failure(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      final value = body['error'] as Map;
      return DocumentFailure(
        value['code']?.toString() ?? 'UPLOAD_FAILED',
        value['message']?.toString() ?? '材料处理失败，请重试',
      );
    }
    return const DocumentFailure('NETWORK_ERROR', '网络连接中断，文件未保存，请安全重试');
  }
}

class DocumentFailure implements Exception {
  const DocumentFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class DemoDocumentRepository implements DocumentRepository {
  DemoDocumentRepository();

  final List<MedicalDocument> _documents = [];
  final Map<String, List<DocumentRevision>> _revisions = {};
  final Map<(String, String), Uint8List> _files = {};
  final Map<String, DocumentRevision> _replacementRequests = {};

  @override
  Future<List<MedicalDocument>> list({String? documentType}) async => _documents
      .where(
        (item) => documentType == null || item.documentType == documentType,
      )
      .toList();

  @override
  Future<MedicalDocument> get(String id) async =>
      _documents.firstWhere((item) => item.id == id);

  @override
  Future<MedicalDocument> upload({
    required SelectedDocumentFile file,
    required String documentType,
    required String consentVersion,
    required String idempotencyKey,
    required void Function(int sent, int total) onProgress,
  }) async {
    onProgress(file.bytes.length, file.bytes.length);
    final id = 'demo-${_documents.length + 1}';
    final item = MedicalDocument(
      id: id,
      documentType: documentType,
      originalFileName: file.name,
      mimeType: file.name.toLowerCase().endsWith('.pdf')
          ? 'application/pdf'
          : 'image/png',
      fileSizeBytes: file.bytes.length,
      fileHash: 'demo-sha256',
      currentRevisionId: '$id-r1',
      uploadedAt: DateTime.now(),
    );
    _documents.insert(0, item);
    _revisions[id] = [
      DocumentRevision(
        id: item.currentRevisionId,
        revisionNumber: 1,
        mimeType: item.mimeType,
        fileHash: item.fileHash,
        createdAt: item.uploadedAt,
      ),
    ];
    _files[(id, item.currentRevisionId)] = file.bytes;
    return item;
  }

  @override
  Future<List<DocumentRevision>> revisions(String documentId) async =>
      List.unmodifiable(_revisions[documentId] ?? const []);

  @override
  Future<DocumentRevision> replace({
    required String documentId,
    required String expectedRevisionId,
    required String reason,
    required SelectedDocumentFile file,
    required String idempotencyKey,
    required void Function(int sent, int total) onProgress,
  }) async {
    final requestKey = '$documentId:$idempotencyKey';
    if (_replacementRequests.containsKey(requestKey)) {
      return _replacementRequests[requestKey]!;
    }
    final index = _documents.indexWhere((item) => item.id == documentId);
    if (index < 0) {
      throw const DocumentFailure('RESOURCE_NOT_FOUND', '材料不存在。');
    }
    final current = _documents[index];
    if (current.currentRevisionId != expectedRevisionId) {
      throw const DocumentFailure('RESOURCE_VERSION_CONFLICT', '材料已更新，请刷新后重试。');
    }
    onProgress(file.bytes.length, file.bytes.length);
    final history = _revisions[documentId]!;
    final revisionNumber = history.length + 1;
    final revisionId = '$documentId-r$revisionNumber';
    final mimeType = file.name.toLowerCase().endsWith('.pdf')
        ? 'application/pdf'
        : 'image/png';
    final revision = DocumentRevision(
      id: revisionId,
      revisionNumber: revisionNumber,
      mimeType: mimeType,
      fileHash: 'demo-replacement-sha256',
      replacementReason: reason,
      createdAt: DateTime.now(),
    );
    history.insert(0, revision);
    _files[(documentId, revisionId)] = file.bytes;
    _documents[index] = MedicalDocument(
      id: current.id,
      documentType: current.documentType,
      originalFileName: file.name,
      mimeType: mimeType,
      fileSizeBytes: file.bytes.length,
      fileHash: revision.fileHash,
      currentRevisionId: revision.id,
      uploadedAt: current.uploadedAt,
    );
    _replacementRequests[requestKey] = revision;
    return revision;
  }

  @override
  Future<Uint8List> download(String documentId, String revisionId) async =>
      _files[(documentId, revisionId)] ?? Uint8List(0);

  @override
  Future<void> delete(String documentId) async {
    _documents.removeWhere((item) => item.id == documentId);
    _revisions.remove(documentId);
    _files.removeWhere((key, _) => key.$1 == documentId);
    _replacementRequests.removeWhere(
      (key, _) => key.startsWith('$documentId:'),
    );
  }
}

int _documentIdempotencySequence = 0;

String newDocumentIdempotencyKey() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final sequence = (_documentIdempotencySequence++).toRadixString(36);
  return 'flutter-$timestamp-$sequence';
}
