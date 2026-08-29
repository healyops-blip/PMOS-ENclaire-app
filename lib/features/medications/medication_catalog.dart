import 'dart:convert';

import 'package:flutter/services.dart';

class MedicationCatalogEntry {
  const MedicationCatalogEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.itemType,
    required this.pcosContext,
    required this.dosageForms,
    required this.strengthCandidates,
    required this.aliases,
    required this.route,
    required this.usageReference,
    required this.scheduleSource,
    required this.userEditable,
    required this.canPrefillReminder,
    required this.reviewStatus,
    required this.recordStatus,
  });

  factory MedicationCatalogEntry.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((item) => '$item')
            .toList();

    return MedicationCatalogEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      itemType: json['item_type'] as String,
      pcosContext: json['pcos_context'] as String,
      dosageForms: strings('dosage_forms'),
      strengthCandidates: strings('strength_candidates'),
      aliases: strings('aliases'),
      route: json['route'] as String,
      usageReference: json['usage_reference'] as String,
      scheduleSource: json['schedule_source'] as String,
      userEditable: json['user_editable'] as bool,
      canPrefillReminder: json['can_prefill_reminder'] as bool,
      reviewStatus: json['review_status'] as String,
      recordStatus: json['record_status'] as String,
    );
  }

  final String id;
  final String name;
  final String category;
  final String itemType;
  final String pcosContext;
  final List<String> dosageForms;
  final List<String> strengthCandidates;
  final List<String> aliases;
  final String route;
  final String usageReference;
  final String scheduleSource;
  final bool userEditable;
  final bool canPrefillReminder;
  final String reviewStatus;
  final String recordStatus;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return name.toLowerCase().contains(normalized) ||
        aliases.any((alias) => alias.toLowerCase().contains(normalized));
  }
}

class MedicationCatalog {
  const MedicationCatalog({
    required this.version,
    required this.disclaimer,
    required this.entries,
  });

  factory MedicationCatalog.fromJson(Map<String, dynamic> json) {
    return MedicationCatalog(
      version: json['version'] as String,
      disclaimer: json['disclaimer'] as String,
      entries: (json['entries'] as List<dynamic>)
          .map(
            (entry) => MedicationCatalogEntry.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final String version;
  final String disclaimer;
  final List<MedicationCatalogEntry> entries;

  List<MedicationCatalogEntry> search(String query) =>
      entries.where((entry) => entry.matches(query)).toList(growable: false);
}

class MedicationCatalogCache {
  MedicationCatalogCache._();

  static const assetPath = 'assets/data/pomi_medications_v2.json';
  static Future<MedicationCatalog>? _cached;

  static Future<MedicationCatalog> load() {
    return _cached ??= rootBundle.loadString(assetPath).then((source) {
      final json = jsonDecode(source);
      return MedicationCatalog.fromJson(Map<String, dynamic>.from(json as Map));
    });
  }

  static void clearForTesting() => _cached = null;
}

/// Returns the Chinese generic name used by the UI for a known catalog item.
///
/// Patient records may contain an OCR/source-language name, so the API keeps
/// that value for auditability. Presentation code should use this helper when
/// rendering a medication name. Unknown custom medicines are left unchanged.
String medicationDisplayName(Object? value, {Object? standardDrugId}) {
  final id = standardDrugId?.toString().trim().toLowerCase();
  const byId = <String, String>{
    'med_ethinylestradiol_cyproterone_acetate': '炔雌醇环丙孕酮片',
    'med_ethinylestradiol_drospirenone': '炔雌醇屈螺酮片',
    'med_metformin_hydrochloride': '盐酸二甲双胍',
    'rxnorm:metformin': '盐酸二甲双胍',
    'med_spironolactone': '螺内酯',
    'med_dydrogesterone': '地屈孕酮',
    'med_micronized_progesterone': '黄体酮',
    'med_medroxyprogesterone_acetate': '醋酸甲羟孕酮',
    'med_semaglutide': '司美格鲁肽',
    'med_liraglutide': '利拉鲁肽',
    'supp_inositol': '肌醇',
    'supp_vitamin_d3': '维生素D3',
    'rxnorm:cholecalciferol': '维生素D3',
    'supp_vitamin_b12': '维生素B12',
    'supp_calcium_vitamin_d3': '钙维生素D复方制剂',
    'med_letrozole': '来曲唑',
    'med_clomiphene_citrate': '枸橼酸氯米芬',
    'supp_folic_acid': '叶酸',
    'pomi:folic-acid': '叶酸',
    'otc_paracetamol': '对乙酰氨基酚',
    'otc_ibuprofen': '布洛芬',
    'otc_compound_paracetamol_amantadine': '复方氨酚烷胺制剂',
    'otc_dextromethorphan': '右美沙芬',
  };
  if (id != null && byId.containsKey(id)) return byId[id]!;

  final name = value?.toString().trim() ?? '';
  if (name.isEmpty) return '未命名药品';
  final normalized = name.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  const aliases = <String, String>{
    'metformin': '盐酸二甲双胍',
    'metforminxr': '盐酸二甲双胍',
    'metforminhydrochloride': '盐酸二甲双胍',
    'folicacid': '叶酸',
    'vitamind3': '维生素D3',
    'vitamind': '维生素D3',
    'cholecalciferol': '维生素D3',
    'inositol': '肌醇',
    'myoinositol': '肌醇',
    'dchiroinositol': '肌醇',
    'ibuprofen': '布洛芬',
    'paracetamol': '对乙酰氨基酚',
    'acetaminophen': '对乙酰氨基酚',
    'dextromethorphan': '右美沙芬',
  };
  return aliases[normalized] ?? name;
}
