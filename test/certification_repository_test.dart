import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/upload/certification_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('certification demonstration is bound to a document revision', () async {
    final repository = LocalCertificationRepository();

    final completed = await repository.start('document-1', 'revision-1');
    final sameRevision = await repository.get('document-1', 'revision-1');
    final replacement = await repository.get('document-1', 'revision-2');

    expect(completed.status, CertificationStatus.succeeded);
    expect(sameRevision.status, CertificationStatus.succeeded);
    expect(replacement.status, CertificationStatus.notStarted);
  });
}
