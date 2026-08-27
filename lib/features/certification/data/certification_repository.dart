import 'dart:convert';

import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only boundary for the hospital-certification interaction demo.
///
/// A future remote implementation must be introduced as a separate product
/// decision. The current repository must never call an HTTP API or mutate OCR,
/// document, medication, or report data.
abstract interface class CertificationRepository {
  Future<CertificationRecord> read(String documentId, String revisionId);

  Future<void> write(CertificationRecord record);
}

class LocalCertificationRepository implements CertificationRepository {
  LocalCertificationRepository([this._preferences]);

  final SharedPreferencesAsync? _preferences;
  static final Map<String, String> _memoryFallback = {};

  String _key(String documentId, String revisionId) {
    final document = base64Url.encode(utf8.encode(documentId));
    final revision = base64Url.encode(utf8.encode(revisionId));
    return 'certification.v1.$document.$revision';
  }

  @override
  Future<CertificationRecord> read(String documentId, String revisionId) async {
    final key = _key(documentId, revisionId);
    String? raw;
    try {
      raw = await (_preferences ?? SharedPreferencesAsync()).getString(key);
    } on Object {
      raw = _memoryFallback[key];
    }
    if (raw == null) {
      return CertificationRecord.notStarted(documentId, revisionId);
    }
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final status = CertificationStatus.values
          .where((value) => value.name == json['status'])
          .firstOrNull;
      final pendingOutcome = CertificationDemoOutcome.values
          .where((value) => value.name == json['pending_outcome'])
          .firstOrNull;
      return CertificationRecord(
        documentId: documentId,
        revisionId: revisionId,
        status: status ?? CertificationStatus.notStarted,
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
        failureReason: json['failure_reason'] as String?,
        pendingOutcome: pendingOutcome,
        attemptNumber: json['attempt_number'] as int? ?? 0,
      );
    } on Object {
      return CertificationRecord.notStarted(documentId, revisionId);
    }
  }

  @override
  Future<void> write(CertificationRecord record) async {
    final key = _key(record.documentId, record.revisionId);
    final raw = jsonEncode({
      'status': record.status.name,
      'updated_at': record.updatedAt?.toIso8601String(),
      'failure_reason': record.failureReason,
      'pending_outcome': record.pendingOutcome?.name,
      'attempt_number': record.attemptNumber,
    });
    _memoryFallback[key] = raw;
    try {
      await (_preferences ?? SharedPreferencesAsync()).setString(key, raw);
    } on Object {
      // Unsupported test platforms retain the same revision-scoped semantics
      // through the process-local fallback. Android/iOS persist preferences.
    }
  }
}

class MemoryCertificationRepository implements CertificationRepository {
  final Map<String, CertificationRecord> _records = {};

  String _key(String documentId, String revisionId) =>
      '$documentId\u0000$revisionId';

  @override
  Future<CertificationRecord> read(String documentId, String revisionId) async {
    return _records[_key(documentId, revisionId)] ??
        CertificationRecord.notStarted(documentId, revisionId);
  }

  @override
  Future<void> write(CertificationRecord record) async {
    _records[_key(record.documentId, record.revisionId)] = record;
  }
}
