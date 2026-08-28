enum CertificationStatus { notStarted, processing, succeeded, failed }

enum CertificationDemoOutcome { succeeded, failed }

class CertificationRecord {
  const CertificationRecord({
    required this.documentId,
    required this.revisionId,
    required this.status,
    this.updatedAt,
    this.failureReason,
    this.pendingOutcome,
    this.attemptNumber = 0,
  });

  final String documentId;
  final String revisionId;
  final CertificationStatus status;
  final DateTime? updatedAt;
  final String? failureReason;

  /// Persisted only so an interrupted local demo can finish deterministically.
  /// This is not a hospital or blockchain result.
  final CertificationDemoOutcome? pendingOutcome;
  final int attemptNumber;

  bool get hasWatermark => status == CertificationStatus.succeeded;

  CertificationRecord copyWith({
    CertificationStatus? status,
    DateTime? updatedAt,
    String? failureReason,
    bool clearFailureReason = false,
    CertificationDemoOutcome? pendingOutcome,
    bool clearPendingOutcome = false,
    int? attemptNumber,
  }) {
    return CertificationRecord(
      documentId: documentId,
      revisionId: revisionId,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      failureReason: clearFailureReason
          ? null
          : failureReason ?? this.failureReason,
      pendingOutcome: clearPendingOutcome
          ? null
          : pendingOutcome ?? this.pendingOutcome,
      attemptNumber: attemptNumber ?? this.attemptNumber,
    );
  }

  static CertificationRecord notStarted(String documentId, String revisionId) {
    return CertificationRecord(
      documentId: documentId,
      revisionId: revisionId,
      status: CertificationStatus.notStarted,
    );
  }
}
