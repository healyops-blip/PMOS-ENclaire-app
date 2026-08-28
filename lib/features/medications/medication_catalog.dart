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
