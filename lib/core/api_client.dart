import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiBaseUrl = String.fromEnvironment(
  'POMI_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
const sessionIdStorageKey = 'pomi_session_id';
const sessionExpiresAtStorageKey = 'pomi_session_expires_at';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(secureStorageProvider));
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
