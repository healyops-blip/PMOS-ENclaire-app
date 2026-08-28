import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CertificationStatus { notStarted, processing, succeeded, failed }

class CertificationRecord {
  const CertificationRecord({
    required this.status,
    required this.updatedAt,
    this.failureReason,
  });

  final CertificationStatus status;
  final DateTime updatedAt;
  final String? failureReason;
}

abstract interface class CertificationRepository {
  Future<CertificationRecord> get(String documentId, String revisionId);
  Future<CertificationRecord> start(String documentId, String revisionId);
}

final certificationRepositoryProvider = Provider<CertificationRepository>(
  (ref) => LocalCertificationRepository(),
);

class LocalCertificationRepository implements CertificationRepository {
  String _key(String documentId, String revisionId) =>
      'certification:$documentId:$revisionId';

  @override
  Future<CertificationRecord> get(String documentId, String revisionId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key(documentId, revisionId));
    if (encoded == null) {
      return CertificationRecord(
        status: CertificationStatus.notStarted,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    final value = jsonDecode(encoded) as Map<String, dynamic>;
    return CertificationRecord(
      status: CertificationStatus.values.byName(value['status'] as String),
      updatedAt: DateTime.parse(value['updated_at'] as String),
      failureReason: value['failure_reason'] as String?,
    );
  }

  @override
  Future<CertificationRecord> start(
    String documentId,
    String revisionId,
  ) async {
    await _save(
      documentId,
      revisionId,
      CertificationRecord(
        status: CertificationStatus.processing,
        updatedAt: DateTime.now(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final result = CertificationRecord(
      status: CertificationStatus.succeeded,
      updatedAt: DateTime.now(),
    );
    await _save(documentId, revisionId, result);
    return result;
  }

  Future<void> _save(
    String documentId,
    String revisionId,
    CertificationRecord record,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(documentId, revisionId),
      jsonEncode({
        'status': record.status.name,
        'updated_at': record.updatedAt.toIso8601String(),
        'failure_reason': record.failureReason,
      }),
    );
  }
}
