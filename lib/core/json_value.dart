import 'api_client.dart';

/// Represents a field in a PATCH-like request.
///
/// An absent field leaves the server value unchanged, while a present field
/// whose value is `null` explicitly clears a nullable server value.
class JsonPatchField<T> {
  const JsonPatchField.absent() : isPresent = false, value = null;
  const JsonPatchField.value(this.value) : isPresent = true;

  final bool isPresent;
  final T? value;
}

Map<String, dynamic> jsonObject(dynamic value, [String label = 'object']) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw ApiFailure('INVALID_RESPONSE', '服务返回的 $label 格式异常');
}

List<dynamic> jsonArray(dynamic value, [String label = 'list']) {
  if (value is List) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务返回的 $label 格式异常');
}

String jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务响应缺少字段 $key');
}

String? jsonStringOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务字段 $key 格式异常');
}

int jsonInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务字段 $key 格式异常');
}

int? jsonIntOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务字段 $key 格式异常');
}

double? jsonDoubleOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw ApiFailure('INVALID_RESPONSE', '服务字段 $key 格式异常');
}

bool jsonBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务字段 $key 格式异常');
}

DateTime jsonDateTime(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(jsonString(json, key));
  if (value != null) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务字段 $key 不是有效时间');
}

DateTime? jsonDateTimeOrNull(Map<String, dynamic> json, String key) {
  final raw = jsonStringOrNull(json, key);
  if (raw == null) return null;
  final value = DateTime.tryParse(raw);
  if (value != null) return value;
  throw ApiFailure('INVALID_RESPONSE', '服务字段 $key 不是有效时间');
}

String dateValue(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
