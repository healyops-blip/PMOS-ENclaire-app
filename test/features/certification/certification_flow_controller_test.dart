import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/certification/application/certification_flow_controller.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';
import 'package:pmos_enclaire/features/certification/domain/certification_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local repository survives reconstruction for the same revision',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = LocalCertificationRepository();
      await first.write(
        CertificationRecord(
          documentId: 'persistent-document',
          revisionId: 'persistent-revision',
          status: CertificationStatus.succeeded,
          updatedAt: DateTime.utc(2026, 8, 27),
          attemptNumber: 1,
        ),
      );

      final restored = await LocalCertificationRepository().read(
        'persistent-document',
        'persistent-revision',
      );
      expect(restored.status, CertificationStatus.succeeded);
      expect(restored.attemptNumber, 1);
    },
  );

  test('local key encoding cannot collide on dotted identifiers', () async {
    final repository = LocalCertificationRepository();
    await repository.write(
      const CertificationRecord(
        documentId: 'document.part',
        revisionId: 'revision',
        status: CertificationStatus.succeeded,
      ),
    );
    await repository.write(
      const CertificationRecord(
        documentId: 'document',
        revisionId: 'part.revision',
        status: CertificationStatus.failed,
      ),
    );

    expect(
      (await repository.read('document.part', 'revision')).status,
      CertificationStatus.succeeded,
    );
    expect(
      (await repository.read('document', 'part.revision')).status,
      CertificationStatus.failed,
    );
  });

  test(
    'load and write failures become recoverable local failure states',
    () async {
      final repository = _FlakyRepository(failReads: 1, failWrites: 1);
      final controller = CertificationFlowController(
        repository: repository,
        documentId: 'document-1',
        revisionId: 'revision-1',
        transitionDuration: Duration.zero,
        delay: (_) async {},
        now: () => DateTime.utc(2026, 8, 27),
      );

      await controller.load();
      expect(controller.loading, isFalse);
      expect(controller.record.status, CertificationStatus.failed);
      expect(controller.record.failureReason, contains('读取'));

      await controller.start();
      expect(controller.record.status, CertificationStatus.failed);
      expect(controller.record.failureReason, contains('保存'));
      expect(controller.record.hasWatermark, isFalse);

      await controller.start();
      expect(controller.record.status, CertificationStatus.succeeded);
      expect(controller.record.attemptNumber, 2);
      controller.dispose();
    },
  );

  test('duplicate start while processing creates only one attempt', () async {
    final repository = MemoryCertificationRepository();
    final gate = Completer<void>();
    final controller = CertificationFlowController(
      repository: repository,
      documentId: 'document-1',
      revisionId: 'revision-1',
      delay: (_) => gate.future,
    );
    await controller.load();

    final first = controller.start();
    final duplicate = controller.start();
    await duplicate;
    expect(controller.record.status, CertificationStatus.processing);
    expect(controller.record.attemptNumber, 1);
    gate.complete();
    await first;
    expect(controller.record.status, CertificationStatus.succeeded);
    expect(controller.record.attemptNumber, 1);
    controller.dispose();
  });

  test('states are isolated by document and revision', () async {
    final repository = MemoryCertificationRepository();
    await repository.write(
      CertificationRecord(
        documentId: 'document-1',
        revisionId: 'revision-1',
        status: CertificationStatus.succeeded,
        updatedAt: DateTime.utc(2026, 8, 27),
      ),
    );

    expect(
      (await repository.read('document-1', 'revision-1')).status,
      CertificationStatus.succeeded,
    );
    expect(
      (await repository.read('document-1', 'revision-2')).status,
      CertificationStatus.notStarted,
    );
    expect(
      (await repository.read('document-2', 'revision-1')).status,
      CertificationStatus.notStarted,
    );
  });

  test('controlled failure can retry through processing to success', () async {
    final repository = MemoryCertificationRepository();
    final delays = <Duration>[];
    final controller = CertificationFlowController(
      repository: repository,
      documentId: 'document-1',
      revisionId: 'revision-1',
      transitionDuration: const Duration(milliseconds: 10),
      plan: const CertificationDemoPlan(failFirstAttempt: true),
      delay: (duration) async => delays.add(duration),
      now: () => DateTime.utc(2026, 8, 27),
    );
    await controller.load();

    final first = controller.start();
    expect(controller.record.status, CertificationStatus.processing);
    await first;
    expect(controller.record.status, CertificationStatus.failed);
    expect(controller.record.hasWatermark, isFalse);

    final retry = controller.start();
    expect(controller.record.status, CertificationStatus.processing);
    await retry;
    expect(controller.record.status, CertificationStatus.succeeded);
    expect(controller.record.hasWatermark, isTrue);
    expect(controller.record.attemptNumber, 2);
    expect(delays, hasLength(2));
    controller.dispose();
  });

  test(
    'restored processing state completes instead of getting stuck',
    () async {
      final repository = MemoryCertificationRepository();
      final now = DateTime.utc(2026, 8, 27, 12);
      await repository.write(
        CertificationRecord(
          documentId: 'document-1',
          revisionId: 'revision-1',
          status: CertificationStatus.processing,
          updatedAt: now.subtract(const Duration(seconds: 2)),
          pendingOutcome: CertificationDemoOutcome.succeeded,
          attemptNumber: 1,
        ),
      );
      final controller = CertificationFlowController(
        repository: repository,
        documentId: 'document-1',
        revisionId: 'revision-1',
        now: () => now,
        delay: (_) async {},
      );

      await controller.load();
      await Future<void>.delayed(Duration.zero);

      expect(controller.record.status, CertificationStatus.succeeded);
      expect(
        (await repository.read('document-1', 'revision-1')).status,
        CertificationStatus.succeeded,
      );
      controller.dispose();
    },
  );
}

class _FlakyRepository implements CertificationRepository {
  _FlakyRepository({this.failReads = 0, this.failWrites = 0});
  int failReads;
  int failWrites;
  CertificationRecord? record;

  @override
  Future<CertificationRecord> read(String documentId, String revisionId) async {
    if (failReads > 0) {
      failReads--;
      throw StateError('read failed');
    }
    return record ?? CertificationRecord.notStarted(documentId, revisionId);
  }

  @override
  Future<void> write(CertificationRecord value) async {
    if (failWrites > 0) {
      failWrites--;
      throw StateError('write failed');
    }
    record = value;
  }
}
