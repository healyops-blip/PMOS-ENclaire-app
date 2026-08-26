enum CertificationStatus { notStarted, processing, succeeded, failed }

class CertificationRecord {
  const CertificationRecord({
    required this.documentId,
    required this.revisionId,
    required this.status,
    this.updatedAt,
    this.failureReason,
  });

  final String documentId;
  final String revisionId;
  final CertificationStatus status;
  final DateTime? updatedAt;
  final String? failureReason;

  CertificationRecord copyWith({
    CertificationStatus? status,
    DateTime? updatedAt,
    String? failureReason,
  }) {
    return CertificationRecord(
      documentId: documentId,
      revisionId: revisionId,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      failureReason: failureReason,
    );
  }
}
