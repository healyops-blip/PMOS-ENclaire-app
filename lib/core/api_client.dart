import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'smoke_report_fixture.dart';
import 'smoke_dataset.dart';
import '../features/auth/auth_controller.dart';
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
  // Session 失效（AUTHENTICATION_REQUIRED）时刷新认证状态，
  // 让路由守卫把用户带回登录页，避免各页面停留在 401 假崩溃状态。
  void onAuthExpired() => ref.invalidate(authControllerProvider);
  return smokeMode
      ? SmokeApiClient(storage)
      : ApiClient(storage, onAuthExpired: onAuthExpired);
});

class ApiFailure implements Exception {
  ApiFailure(
    this.code,
    this.message, {
    this.statusCode,
    this.retryAfterSeconds,
    this.requestId,
    this.details,
  });

  final String code;
  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;
  final String? requestId;

  /// 后端 `error.details` 原样透传，供表单按 `fields[]` 高亮出错项。
  final Map<String, dynamic>? details;

  /// `error.details.fields` 规范化为 `[{path, code, message}]`。
  List<Map<String, dynamic>> get fieldIssues {
    final raw = details?['fields'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.storage, {String baseUrl = apiBaseUrl, this.onAuthExpired})
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
            onAuthExpired?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final FlutterSecureStorage storage;
  final void Function()? onAuthExpired;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => _request(() => dio.get(path, queryParameters: queryParameters));

  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async => _request(
    () => dio.post(path, data: data, options: Options(headers: headers)),
  );

  Future<dynamic> put(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async => _request(
    () => dio.put(path, data: data, options: Options(headers: headers)),
  );

  Future<dynamic> delete(String path, {Object? data}) async =>
      _request(() => dio.delete(path, data: data));

  Future<dynamic> upload(
    String path, {
    required Uint8List bytes,
    required String filename,
    required String documentType,
  }) async {
    final data = FormData.fromMap({
      'document_type': documentType,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _request(() => dio.post(path, data: data));
  }

  Future<Map<String, dynamic>> recognizeOcr({
    required Uint8List bytes,
    required String filename,
    required String materialType,
    required String promptVersion,
    required String consentVersion,
    required String idempotencyKey,
  }) async {
    final data = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'material_type': materialType,
      'prompt_version': promptVersion,
    });
    final value = await _request(
      () => dio.post(
        '/api/ocr/recognize',
        data: data,
        options: Options(
          headers: {
            'Idempotency-Key': idempotencyKey,
            'X-External-Processing-Consent-Version': consentVersion,
          },
        ),
      ),
    );
    return Map<String, dynamic>.from(value as Map);
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
      if (body is Map && body['success'] is bool) {
        final requestId =
            body['request_id']?.toString() ??
            response.headers.value('x-request-id');
        if (body['success'] == true) return body['data'];
        final apiError = body['error'];
        final code =
            apiError is Map
                ? apiError['code']?.toString() ?? 'REQUEST_FAILED'
                : 'REQUEST_FAILED';
        throw ApiFailure(
          code,
          _userMessage(code, null),
          statusCode: response.statusCode,
          requestId: requestId,
          details:
              apiError is Map
                  ? Map<String, dynamic>.from(
                    apiError['details'] as Map? ?? const {},
                  )
                  : null,
        );
      }
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
      final requestId =
          body['request_id']?.toString() ??
          error.response?.headers.value('x-request-id');
      return ApiFailure(
        code,
        _userMessage(code, retryAfter),
        statusCode: error.response?.statusCode,
        retryAfterSeconds: retryAfter,
        requestId: requestId,
        details: Map<String, dynamic>.from(
          apiError['details'] as Map? ?? const {},
        ),
      );
    }
    return ApiFailure(
      'NETWORK_ERROR',
      '无法连接服务器，请检查网络后重试',
      statusCode: error.response?.statusCode,
      requestId: error.response?.headers.value('x-request-id'),
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
    'PHONE_NUMBER_TAKEN' => '该手机号已注册，请直接登录',
    'VALIDATION_ERROR' => '账号或密码格式不符合要求，请检查后重试',
    'AUTH_RATE_LIMITED' when retryAfter != null => '请求过于频繁，请在 $retryAfter 秒后重试',
    'AUTH_RATE_LIMITED' => '请求过于频繁，请稍后重试',
    'CYCLE_DATE_ORDER_INVALID' => '经期开始日期不能晚于结束日期',
    'CYCLE_DATE_OVERLAP' => '该日期与已有经期记录重叠，请先结束或修改已有记录',
    'CYCLE_VERSION_CONFLICT' => '经期记录已在其他设备更新，请刷新后重试',
    'CYCLE_NOT_FOUND' => '经期记录不存在，可能已被删除',
    'OCR_NOT_CONFIGURED' => '识别服务未配置，请联系开发者',
    'OCR_TIMEOUT' => '识别超时，请稍后重试',
    'OCR_NETWORK_ERROR' => '识别服务网络异常，请稍后重试',
    'OCR_FILE_INVALID' => '图片无法读取，请重新拍摄或选择更清晰的照片',
    'OCR_RESPONSE_INVALID' => '识别结果解析失败，请重试',
    'OCR_RESPONSE_TRUNCATED' => '报告内容较多，识别结果被截断，请重试或分段拍摄',
    'OCR_HTTP_400' => '图片内容无法识别，请拍清楚一点后重试',
    'OCR_HTTP_429' => '识别请求过于频繁，请稍后重试',
    'OCR_CONFIRMATION_INVALID' => '报告中有项目未通过校验（如单位无法识别），请修正后重试',
    _ => '请求失败，请稍后重试',
  };
}

/// In-memory API used by the local Web Preview.
///
/// Enable it with `--dart-define=POMI_SMOKE_MODE=true`. It intentionally makes
/// no network requests, while keeping the same response shapes as the backend.
class SmokeApiClient extends ApiClient {
  SmokeApiClient(super.storage);

  /// Credentials shown on the local Smoke Preview login screen.
  static const demoAccountName = 'smoke';
  static const demoPassword = 'Pomi1234';

  final Map<String, dynamic> _profile = {
    'nickname': 'Pomi',
    'id': 'smoke-patient',
    'birth_year': 1997,
    'birth_date': '1997-01-01',
    'height_cm': null,
    'diagnosis_year': 2023,
    'period_duration_days': 5,
    'next_visit_date': null,
    'health_goal': '整理复诊资料，并与医生高效沟通',
    'external_ocr_notice_accepted_at': '2026-08-27T00:00:00Z',
    'onboarding_completed': true,
    'created_at': '2026-08-27T00:00:00Z',
    'updated_at': '2026-08-27T00:00:00Z',
  };
  Map<String, dynamic>? _onboardingBasic;
  Map<String, dynamic>? _onboardingCycle;
  Map<String, dynamic>? _onboardingMedications;
  final List<Map<String, dynamic>> _weights = List.generate(7, (index) {
    const values = [71.3, 70.5, 71.0, 70.7, 69.9, 70.4, 70.0];
    final timestamp =
        DateTime.now().subtract(Duration(days: (6 - index) * 4)).toUtc();
    return {
      'id': 'smoke-weight-${index + 1}',
      'record_date': timestamp.toIso8601String().substring(0, 10),
      'weight_kg': values[index],
      'created_at': timestamp.toIso8601String(),
      'updated_at': timestamp.toIso8601String(),
    };
  });
  final List<Map<String, dynamic>> _cycles = [];
  final List<Map<String, dynamic>> _medications = [
    {
      'id': 'smoke-medication-1',
      'drug_name': '盐酸二甲双胍缓释片',
      'specification': '500mg',
      'frequency': '每日 2 次 · 随餐',
      'scheduled_time': '08:00',
      'current_status': 'active',
      'today_status': 'taken',
    },
    {
      'id': 'smoke-medication-2',
      'drug_name': '叶酸',
      'specification': '0.4mg',
      'frequency': '每日 1 次',
      'scheduled_time': '08:00',
      'current_status': 'active',
      'today_status': 'taken',
    },
    {
      'id': 'smoke-medication-3',
      'drug_name': '维生素 D3',
      'specification': '2000IU',
      'frequency': '每日 1 次',
      'scheduled_time': '20:00',
      'current_status': 'active',
      'today_status': 'unrecorded',
    },
  ];
  final Map<String, Map<String, String>> _dailyOverrides = {};
  Future<List<Map<String, dynamic>>>? _datasetFuture;
  int _datasetCursor = 0;
  int _nextId = 1;

  String _id(String prefix) => '$prefix-${_nextId++}';

  String _now() => DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> _onboardingDraft(String currentStep) => {
    'id': 'smoke-onboarding',
    'current_step': currentStep,
    'basic': _onboardingBasic == null ? null : Map.of(_onboardingBasic!),
    'cycle': _onboardingCycle == null ? null : Map.of(_onboardingCycle!),
    'medications':
        _onboardingMedications == null ? null : Map.of(_onboardingMedications!),
    'updated_at': _now(),
  };

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/api/auth/me') {
      return {
        'uid': 'smoke-user',
        'account_name': 'smoke',
        'onboarding_completed': true,
      };
    }
    if (path == '/api/onboarding') {
      final currentStep =
          _onboardingMedications != null
              ? 'complete'
              : _onboardingCycle != null
              ? 'medications'
              : _onboardingBasic != null
              ? 'cycle'
              : 'basic';
      return _onboardingDraft(currentStep);
    }
    if (path == '/api/patient/profile') return Map.of(_profile);
    if (path == '/api/weights') return _copyList(_weights);
    if (path == '/api/cycles') return _copyList(_cycles);
    if (path == '/api/medications') {
      return {
        'server_date': DateTime.now().toIso8601String().substring(0, 10),
        'items': _copyList(_medications),
        'groups': <String, dynamic>{},
        'next_cursor': null,
        'has_more': false,
      };
    }
    if (path == '/api/medication-catalog') {
      final catalog =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/pomi_medications_v2.json',
                ),
              )
              as Map<String, dynamic>;
      return {
        'version': catalog['version'],
        'source': catalog['source'],
        'disclaimer': catalog['disclaimer'],
        'items': catalog['entries'],
      };
    }
    if (path == '/api/medication-daily') {
      final today = DateTime.now();
      final from =
          _parseDate(queryParameters?['from']) ??
          DateTime(today.year, today.month, 1);
      final to =
          _parseDate(queryParameters?['to']) ??
          DateTime(today.year, today.month, today.day);
      final medicationId = queryParameters?['medication_id']?.toString();
      final medications = _medications.where(
        (item) =>
            item['current_status'] == 'active' &&
            (medicationId == null || item['id'] == medicationId),
      );
      final items = <Map<String, dynamic>>[];
      for (final medication in medications) {
        var date = DateTime(from.year, from.month, from.day);
        final effectiveTo =
            to.isAfter(DateTime(today.year, today.month, today.day))
                ? DateTime(today.year, today.month, today.day)
                : to;
        while (!date.isAfter(effectiveTo)) {
          final firstExpected = DateTime(today.year, today.month, 3);
          if (date.isBefore(firstExpected)) {
            date = date.add(const Duration(days: 1));
            continue;
          }
          final dateValue = date.toIso8601String().substring(0, 10);
          final status =
              _dailyOverrides[medication['id']?.toString()]?[dateValue] ??
              _seededDailyStatus(medication['id']?.toString(), date);
          items.add({
            'id': 'smoke-daily-${medication['id']}-$dateValue',
            'medication_id': medication['id'],
            'record_date': dateValue,
            'intake_status': status,
            'recorded_at':
                status == 'unrecorded' ? null : '${dateValue}T08:00:00Z',
            'editable': true,
          });
          date = date.add(const Duration(days: 1));
        }
      }
      return items;
    }
    if (path == '/api/dashboard') {
      final today =
          _medications
              .where((item) => item['current_status'] == 'active')
              .map(
                (item) => {
                  'medication_id': item['id'],
                  'drug_name': item['drug_name'],
                  'specification': item['specification'],
                  'dosage_text': item['specification'],
                  'frequency': item['frequency'],
                  'scheduled_time': item['scheduled_time'],
                  'intake_status': item['today_status'] ?? 'unrecorded',
                  'recorded_at': null,
                },
              )
              .toList();
      return {
        'server_date': DateTime.now().toIso8601String().substring(0, 10),
        'data_as_of': DateTime.now().toUtc().toIso8601String(),
        'follow_up': {'status': 'empty', 'data': null, 'error_code': null},
        'today_medications': {
          'status': today.isEmpty ? 'empty' : 'ok',
          'data': today,
          'error_code': null,
        },
        'monthly_medication_summary': {
          'status': 'ok',
          'data': {
            'month': DateTime.now().toIso8601String().substring(0, 7),
            'taken_count': 0,
            'missed_count': 0,
            'unrecorded_count': today.length,
          },
          'error_code': null,
        },
        'tracking_summary': {
          'status': 'ok',
          'data': {
            'latest_weight': _weights.isEmpty ? null : Map.of(_weights.last),
            'latest_cycle': _cycles.isEmpty ? null : Map.of(_cycles.last),
          },
          'error_code': null,
        },
        'document_summary': {
          'status': 'ok',
          'data': {'confirmed': 0, 'total': 0},
          'error_code': null,
        },
        'latest_report': {'status': 'empty', 'data': null, 'error_code': null},
      };
    }
    if (path == '/api/documents') {
      final documents = await _datasetDocuments();
      return {'items': documents, 'total': documents.length};
    }
    if (path == '/api/reports') {
      return {
        'items': [Map<String, dynamic>.from(smokeReportListItem)],
        'next_cursor': null,
        'has_more': false,
      };
    }
    if (path == '/api/reports/smoke-report') {
      return Map<String, dynamic>.from(smokeReportDetail);
    }
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
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
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
          'onboarding_completed': true,
        },
      };
    }
    if (path == '/api/onboarding/complete') {
      final updatedAt = _now();
      _profile['onboarding_completed'] = true;
      _profile['updated_at'] = updatedAt;
      return {
        'account': {
          'uid': 'smoke-user',
          'account_name': 'smoke',
          'onboarding_completed': true,
        },
        'profile': Map.of(_profile),
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
        'current_status': 'active',
        'today_status': 'unrecorded',
        ...values,
      };
      _medications.add(item);
      return Map.of(item);
    }
    if (path == '/api/ocr/tasks') {
      return {'id': 'smoke-ocr', 'task_status': 'queued'};
    }
    return {'id': _id('smoke'), ...values};
  }

  @override
  Future<dynamic> put(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    final values = _map(data);
    if (path == '/api/onboarding/steps/basic') {
      final updatedAt = _now();
      _onboardingBasic = {...values, 'updated_at': updatedAt};
      _profile.addAll({
        'nickname': values['nickname'],
        'birth_year': values['birth_year'],
        'diagnosis_year': values['diagnosis_year'],
        'height_cm': values['height_cm'],
        'updated_at': updatedAt,
      });
      return _onboardingDraft('cycle');
    }
    if (path == '/api/onboarding/steps/cycle') {
      final updatedAt = _now();
      _onboardingCycle = {...values, 'updated_at': updatedAt};
      _profile.addAll({
        'usual_cycle_min_days': values['usual_cycle_min_days'],
        'usual_cycle_max_days': values['usual_cycle_max_days'],
        'next_visit_date': values['next_visit_date'],
        'updated_at': updatedAt,
      });
      return _onboardingDraft('medications');
    }
    if (path == '/api/onboarding/steps/medications') {
      final updatedAt = _now();
      _onboardingMedications = {...values, 'updated_at': updatedAt};
      return _onboardingDraft('complete');
    }
    if (path == '/api/patient/profile') {
      _profile.addAll(values);
      return Map.of(_profile);
    }
    final dailyStatus = RegExp(
      r'^/api/medications/([^/]+)/daily-status$',
    ).firstMatch(path);
    if (dailyStatus != null) {
      final id = dailyStatus.group(1);
      final recordDate = values['record_date']?.toString();
      final status = values['intake_status']?.toString() ?? 'unrecorded';
      final medicine =
          _medications.where((item) => item['id'] == id).firstOrNull;
      if (medicine != null) {
        medicine['today_status'] = status;
        if (id != null && recordDate != null && recordDate.isNotEmpty) {
          (_dailyOverrides[id] ??= {})[recordDate] = status;
        }
      }
      return {
        'id': _id('daily'),
        'medication_id': id,
        'record_date': recordDate,
        'intake_status': status,
      };
    }
    return {'id': _id('smoke'), ...values};
  }

  @override
  Future<dynamic> delete(String path, {Object? data}) async {
    final cycleMatch = RegExp(r'^/api/cycles/([^/]+)$').firstMatch(path);
    if (cycleMatch != null) {
      _cycles.removeWhere((item) => item['id'] == cycleMatch.group(1));
    }
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _seededDailyStatus(String? medicationId, DateTime date) {
    final today = DateTime.now();
    final firstExpected = DateTime(today.year, today.month, 3);
    if (date.isBefore(firstExpected)) return 'unrecorded';
    final day = date.day;
    return switch (medicationId) {
      'smoke-medication-1' =>
        day > 26
            ? 'unrecorded'
            : day == 8 || day == 19
            ? 'missed'
            : 'taken',
      'smoke-medication-2' =>
        day > 27
            ? 'unrecorded'
            : day == 11
            ? 'missed'
            : 'taken',
      'smoke-medication-3' => day == 15 ? 'missed' : 'taken',
      _ => 'unrecorded',
    };
  }

  @override
  Future<dynamic> upload(
    String path, {
    required Uint8List bytes,
    required String filename,
    required String documentType,
  }) async => {
    'id': _id('document'),
    'document_type': documentType,
    'original_file_name': filename,
  };

  @override
  Future<Map<String, dynamic>> recognizeOcr({
    required Uint8List bytes,
    required String filename,
    required String materialType,
    required String promptVersion,
    required String consentVersion,
    required String idempotencyKey,
  }) async {
    final documents = await _datasetDocuments();
    final matching = documents
        .where((item) => item['document_type'] == materialType)
        .toList(growable: false);
    final source =
        matching.isEmpty
            ? documents[_datasetCursor++ % documents.length]
            : matching[_datasetCursor++ % matching.length];
    return {
      'ocr_task_id': 'smoke-ocr',
      'ocr_result_id': 'smoke-result-${source['id']}',
      'document_id': source['id'],
      'document_revision_id': source['current_revision_id'],
      'material_type': materialType,
      'status': 'pending_confirmation',
      'result_source': 'smoke-dataset',
      'hospital': source['hospital'],
      'department': source['department'],
      'visit_date': source['visit_date'],
      'diagnosis_summary': source['diagnosis_summary'],
      'medical_advice': source['medical_advice'],
      'examinations': source['examinations'],
      'medication_suggestions': source['medication_suggestions'],
      'original_file_name': filename,
      'dataset_source_file': source['dataset_json_asset'],
    };
  }

  @override
  Future<List<int>> download(String path) async {
    final match = RegExp(
      r'^/api/documents/([^/]+)/revisions/[^/]+/file$',
    ).firstMatch(path);
    if (match == null) return <int>[];
    final documentId = match.group(1);
    final documents = await _datasetDocuments();
    final document =
        documents.where((item) => item['id'] == documentId).firstOrNull;
    final asset = document?['dataset_image_asset']?.toString();
    if (asset == null || asset.isEmpty) return <int>[];
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

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

  Future<List<Map<String, dynamic>>> _datasetDocuments() async {
    final loaded = await (_datasetFuture ??= loadSmokeDataset());
    final documents =
        loaded
            .map(
              (item) => smokeDatasetDocument(
                item,
                item['_dataset_json_asset']!.toString(),
              ),
            )
            .toList();
    documents.sort((a, b) {
      final aDate = a['visit_date']?.toString() ?? '';
      final bDate = b['visit_date']?.toString() ?? '';
      return bDate.compareTo(aDate);
    });
    return documents;
  }
}
