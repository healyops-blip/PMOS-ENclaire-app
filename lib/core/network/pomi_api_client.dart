import 'dart:async';

import 'package:dio/dio.dart';

const pomiApiBaseUrl = String.fromEnvironment(
  'POMI_API_BASE_URL',
  defaultValue: 'https://api.healy1012-ops.top/api',
);

class PomiApiClient {
  PomiApiClient({String baseUrl = pomiApiBaseUrl, Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              headers: const {'Accept': 'application/json'},
            ),
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            try {
              await onUnauthorized?.call();
            } on Object {
              // Session invalidation must never swallow the original 401.
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  FutureOr<void> Function()? onUnauthorized;

  void useSession(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) {
      dio.options.headers.remove('Authorization');
    } else {
      dio.options.headers['Authorization'] = 'Bearer $sessionId';
    }
  }
}
