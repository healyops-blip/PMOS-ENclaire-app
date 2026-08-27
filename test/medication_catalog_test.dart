import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/medications/medication_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(MedicationCatalogCache.clearForTesting);

  test(
    'bundled medication catalog loads and preserves safety boundary',
    () async {
      final catalog = await MedicationCatalogCache.load();

      expect(catalog.version, '2.0');
      expect(catalog.entries, hasLength(20));
      expect(
        catalog.entries.every((entry) => !entry.canPrefillReminder),
        isTrue,
      );
      expect(catalog.entries.map((entry) => entry.id).toSet(), hasLength(20));
    },
  );

  test('catalog search matches standard names and aliases', () async {
    final catalog = await MedicationCatalogCache.load();

    expect(catalog.search('二甲双胍').single.id, 'med_metformin_hydrochloride');
    expect(catalog.search('格华止').single.name, '盐酸二甲双胍');
    expect(catalog.search('VD3').single.id, 'supp_vitamin_d3');
  });
}
