import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiBaseUrl = String.fromEnvironment(
  'POMI_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
const smokeMode = bool.fromEnvironment('POMI_SMOKE_MODE');
const sessionIdStorageKey = 'pomi_session_id';
const sessionExpiresAtStorageKey = 'pomi_session_expires_at';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return smokeMode ? SmokeApiClient(storage) : ApiClient(storage);
});

class ApiFailure implements Exception {
  ApiFailure(
    this.code,
    this.message, {
    this.statusCode,
    this.retryAfterSeconds,
  });

  final String code;
  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.storage, {String baseUrl = apiBaseUrl})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await storage.read(key: sessionIdStorageKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (_errorCode(error.response?.data) == 'AUTHENTICATION_REQUIRED') {
            await Future.wait([
              storage.delete(key: sessionIdStorageKey),
              storage.delete(key: sessionExpiresAtStorageKey),
            ]);
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final FlutterSecureStorage storage;

  Future<dynamic> get(String path) async => _request(() => dio.get(path));

  Future<dynamic> post(String path, {Object? data}) async =>
      _request(() => dio.post(path, data: data));

  Future<dynamic> put(String path, {Object? data}) async =>
      _request(() => dio.put(path, data: data));

  Future<dynamic> upload(
    String path, {
    required File file,
    required String documentType,
  }) async {
    final data = FormData.fromMap({
      'document_type': documentType,
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.last,
      ),
    });
    return _request(() => dio.post(path, data: data));
  }

  Future<List<int>> download(String path) async {
    try {
      final response = await dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? [];
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  Future<dynamic> _request(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      final body = response.data;
      if (body is Map && body.length == 1 && body.containsKey('data')) {
        return body['data'];
      }
      return body;
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  ApiFailure _failure(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      final apiError = body['error'] as Map;
      final code = apiError['code']?.toString() ?? 'REQUEST_FAILED';
      final retryAfter = int.tryParse(
        error.response?.headers.value('retry-after') ?? '',
      );
      return ApiFailure(
        code,
        _userMessage(code, retryAfter),
        statusCode: error.response?.statusCode,
        retryAfterSeconds: retryAfter,
      );
    }
    return ApiFailure(
      'NETWORK_ERROR',
      '无法连接服务器，请检查网络后重试',
      statusCode: error.response?.statusCode,
    );
  }

  static String? _errorCode(dynamic body) {
    if (body is! Map || body['error'] is! Map) return null;
    return (body['error'] as Map)['code']?.toString();
  }

  static String _userMessage(String code, int? retryAfter) => switch (code) {
    'INVALID_CREDENTIALS' => '账号或密码错误',
    'AUTHENTICATION_REQUIRED' => '登录状态已失效，请重新登录',
    'ACCOUNT_NAME_TAKEN' => '该账号已存在，请直接登录或更换账号名',
    'VALIDATION_ERROR' => '账号或密码格式不符合要求，请检查后重试',
    'AUTH_RATE_LIMITED' when retryAfter != null => '请求过于频繁，请在 $retryAfter 秒后重试',
    'AUTH_RATE_LIMITED' => '请求过于频繁，请稍后重试',
    _ => '请求失败，请稍后重试',
  };
}

/// In-memory API used by the local Web Preview.
///
/// Enable it with `--dart-define=POMI_SMOKE_MODE=true`. It intentionally makes
/// no network requests, while keeping the same response shapes as the backend.
class SmokeApiClient extends ApiClient {
  SmokeApiClient(super.storage);

  final Map<String, dynamic> _profile = {
    'nickname': 'Pomi',
    'birth_date': '1997-01-01',
    'height_cm': null,
    'diagnosis_year': 2023,
    'next_visit_date': null,
    'health_goal': '整理复诊资料，并与医生高效沟通',
    'external_ocr_notice_accepted_at': '2026-08-27T00:00:00Z',
  };
  final List<Map<String, dynamic>> _weights = [];
  final List<Map<String, dynamic>> _cycles = [];
  final List<Map<String, dynamic>> _medications = [];
  int _nextId = 1;

  String _id(String prefix) => '$prefix-${_nextId++}';

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/auth/me') {
      return {
        'uid': 'smoke-user',
        'account_name': 'smoke',
        'onboarding_completed': true,
      };
    }
    if (path == '/api/patient/profile') return Map.of(_profile);
    if (path == '/api/weights') return _copyList(_weights);
    if (path == '/api/cycles') return _copyList(_cycles);
    if (path == '/api/medications') return _copyList(_medications);
    if (path == '/api/dashboard') {
      return {
        'profile': Map.of(_profile),
        'medications': _copyList(_medications),
        'latest_weight': _weights.isEmpty ? null : Map.of(_weights.last),
        'latest_cycle': _cycles.isEmpty ? null : Map.of(_cycles.last),
        'documents': {'confirmed': 0, 'total': 0},
      };
    }
    if (path == '/api/documents') {
      return {'items': <Map<String, dynamic>>[], 'total': 0};
    }
    if (path == '/api/reports') return <Map<String, dynamic>>[];
    if (path.startsWith('/api/ocr/tasks/')) {
      if (path.endsWith('/result')) {
        return {'result_source': 'smoke', 'draft': <String, dynamic>{}};
      }
      return {'id': 'smoke-ocr', 'task_status': 'succeeded'};
    }
    if (path.endsWith('/pdf')) return {'status': 'ready'};
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> post(String path, {Object? data}) async {
    final values = _map(data);
    if (path == '/api/auth/register' || path == '/api/auth/logout') {
      return <String, dynamic>{};
    }
    if (path == '/api/auth/login') {
      return {
        'session_id': 'smoke-session',
        'expires_at':
            DateTime.now()
                .toUtc()
                .add(const Duration(days: 30))
                .toIso8601String(),
        'account': {
          'uid': 'smoke-user',
          'account_name': values['account_name']?.toString() ?? 'smoke',
          'onboarding_completed': false,
        },
      };
    }
    if (path == '/api/weights') {
      final item = {'id': _id('weight'), ...values};
      _weights.add(item);
      return Map.of(item);
    }
    if (path == '/api/cycles') {
      final item = {'id': _id('cycle'), ...values};
      _cycles.add(item);
      return Map.of(item);
    }
    if (path == '/api/medications') {
      final item = {
        'id': _id('medication'),
        'today_status': 'not_recorded',
        ...values,
      };
      _medications.add(item);
      return Map.of(item);
    }
    final dailyStatus = RegExp(
      r'^/api/medications/([^/]+)/daily-status$',
    ).firstMatch(path);
    if (dailyStatus != null) {
      final id = dailyStatus.group(1);
      final medicine =
          _medications.where((item) => item['id'] == id).firstOrNull;
      if (medicine != null) {
        medicine['today_status'] = values['status'] ?? 'not_recorded';
        return Map.of(medicine);
      }
    }
    if (path == '/api/ocr/tasks') {
      return {'id': 'smoke-ocr', 'task_status': 'queued'};
    }
    return {'id': _id('smoke'), ...values};
  }

  @override
  Future<dynamic> put(String path, {Object? data}) async {
    final values = _map(data);
    if (path == '/api/patient/profile') {
      _profile.addAll(values);
      return Map.of(_profile);
    }
    return {'id': _id('smoke'), ...values};
  }

  @override
  Future<dynamic> upload(
    String path, {
    required File file,
    required String documentType,
  }) async => {
    'id': _id('document'),
    'document_type': documentType,
    'original_file_name': file.uri.pathSegments.last,
  };

  @override
  Future<List<int>> download(String path) async => <int>[];

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return Map.of(value);
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _copyList(
    List<Map<String, dynamic>> values,
  ) => values.map(Map<String, dynamic>.of).toList();
}
