import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DashboardCacheEntry {
  const DashboardCacheEntry({required this.json, required this.savedAt});

  final Map<String, dynamic> json;
  final DateTime savedAt;
}

abstract interface class DashboardCacheStore {
  Future<DashboardCacheEntry?> read(String uid);
  Future<void> write(String uid, Map<String, dynamic> json, DateTime savedAt);
  Future<void> clear(String uid);
}

class SecureDashboardCacheStore implements DashboardCacheStore {
  SecureDashboardCacheStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String uid) => 'pomi.dashboard.v1.$uid';

  @override
  Future<DashboardCacheEntry?> read(String uid) async {
    final encoded = await _storage.read(key: _key(uid));
    if (encoded == null) return null;
    final value = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    return DashboardCacheEntry(
      json: Map<String, dynamic>.from(value['data'] as Map),
      savedAt: DateTime.parse(value['saved_at'] as String),
    );
  }

  @override
  Future<void> write(String uid, Map<String, dynamic> json, DateTime savedAt) {
    return _storage.write(
      key: _key(uid),
      value: jsonEncode({'saved_at': savedAt.toIso8601String(), 'data': json}),
    );
  }

  @override
  Future<void> clear(String uid) => _storage.delete(key: _key(uid));
}
