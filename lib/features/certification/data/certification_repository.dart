import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class CertificationRepository {
  Future<CertificationRecord> read(String documentId, String revisionId);

  Future<void> write(CertificationRecord record);
}

class LocalCertificationRepository implements CertificationRepository {
  LocalCertificationRepository([this._preferences]);

  final SharedPreferencesAsync? _preferences;
  static final Map<String, String> _memoryFallback = {};

  String _key(String documentId, String revisionId) {
    return 'certification.$documentId.$revisionId';
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
    final parts = raw?.split('|') ?? const <String>[];
    final status = CertificationStatus.values.where((value) {
      return parts.isNotEmpty && value.name == parts.first;
    }).firstOrNull;
    return CertificationRecord(
      documentId: documentId,
      revisionId: revisionId,
      status: status ?? CertificationStatus.notStarted,
      updatedAt: parts.length > 1 ? DateTime.tryParse(parts[1]) : null,
      failureReason: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
    );
  }

  @override
  Future<void> write(CertificationRecord record) async {
    final key = _key(record.documentId, record.revisionId);
    final raw = [
      record.status.name,
      record.updatedAt?.toIso8601String() ?? '',
      record.failureReason ?? '',
    ].join('|');
    _memoryFallback[key] = raw;
    try {
      await (_preferences ?? SharedPreferencesAsync()).setString(key, raw);
    } on Object {
      // Widget tests and unsupported platforms use the in-memory fallback.
    }
  }
}
