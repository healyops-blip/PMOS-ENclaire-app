import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';

typedef CertificationDelay = Future<void> Function(Duration duration);
typedef CertificationNow = DateTime Function();

class CertificationDemoPlan {
  const CertificationDemoPlan({this.failFirstAttempt = false});

  /// Test/demo injection only. There is intentionally no production UI switch.
  final bool failFirstAttempt;
}

class CertificationFlowController extends ChangeNotifier {
  CertificationFlowController({
    required this.repository,
    required this.documentId,
    required this.revisionId,
    this.transitionDuration = const Duration(milliseconds: 1400),
    this.plan = const CertificationDemoPlan(),
    CertificationDelay? delay,
    CertificationNow? now,
  }) : _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now,
       _record = CertificationRecord.notStarted(documentId, revisionId);

  final CertificationRepository repository;
  final String documentId;
  final String revisionId;
  final Duration transitionDuration;
  final CertificationDemoPlan plan;
  final CertificationDelay _delay;
  final CertificationNow _now;

  CertificationRecord _record;
  bool _loading = true;
  bool _disposed = false;
  int _runToken = 0;

  CertificationRecord get record => _record;
  bool get loading => _loading;

  Future<void> load() async {
    _record = await repository.read(documentId, revisionId);
    _loading = false;
    _notify();
    if (_record.status == CertificationStatus.processing) {
      unawaited(_finishProcessing(_runToken));
    }
  }

  Future<void> start() async {
    if (_loading || _record.status == CertificationStatus.processing) return;
    if (_record.status == CertificationStatus.succeeded) return;
    final attempt = _record.attemptNumber + 1;
    final outcome = plan.failFirstAttempt && attempt == 1
        ? CertificationDemoOutcome.failed
        : CertificationDemoOutcome.succeeded;
    _record = CertificationRecord(
      documentId: documentId,
      revisionId: revisionId,
      status: CertificationStatus.processing,
      updatedAt: _now().toUtc(),
      pendingOutcome: outcome,
      attemptNumber: attempt,
    );
    await repository.write(_record);
    _notify();
    await _finishProcessing(++_runToken);
  }

  Future<void> _finishProcessing(int token) async {
    final startedAt = _record.updatedAt;
    final elapsed = startedAt == null
        ? Duration.zero
        : _now().toUtc().difference(startedAt.toUtc());
    final remaining = elapsed >= transitionDuration
        ? Duration.zero
        : transitionDuration - elapsed;
    if (remaining > Duration.zero) await _delay(remaining);
    if (_disposed || token != _runToken) return;

    // Re-read so a controller restored after navigation never overwrites a
    // newer local transition for the same revision.
    final current = await repository.read(documentId, revisionId);
    if (current.status != CertificationStatus.processing) {
      _record = current;
      _notify();
      return;
    }
    final outcome =
        current.pendingOutcome ?? CertificationDemoOutcome.succeeded;
    _record = current.copyWith(
      status: outcome == CertificationDemoOutcome.succeeded
          ? CertificationStatus.succeeded
          : CertificationStatus.failed,
      updatedAt: _now().toUtc(),
      failureReason: outcome == CertificationDemoOutcome.failed
          ? '本地演示流程未完成，原始材料与医疗数据均未受影响。'
          : null,
      clearFailureReason: outcome == CertificationDemoOutcome.succeeded,
      clearPendingOutcome: true,
    );
    await repository.write(_record);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _runToken++;
    super.dispose();
  }
}
