import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      sessionIdStorageKey: 'session-token',
      sessionExpiresAtStorageKey: '2026-09-01T00:00:00Z',
    });
  });

  test(
    'unwraps the business envelope and sends session plus query data',
    () async {
      final storage = const FlutterSecureStorage();
      final client = ApiClient(storage, baseUrl: 'https://api.example.test');
      RequestOptions? captured;
      client.dio.httpClientAdapter = CallbackAdapter((options) {
        captured = options;
        return _jsonResponse(200, {
          'success': true,
          'data': {'value': 42},
          'request_id': 'req_success',
          'error': null,
        });
      });

      final value = await client.get(
        '/api/example',
        queryParameters: {'page': 2},
      );

      expect(value, {'value': 42});
      expect(captured?.path, '/api/example');
      expect(captured?.queryParameters, {'page': 2});
      expect(captured?.headers['Authorization'], 'Bearer session-token');
    },
  );

  test(
    'preserves error code and request id and clears an invalid session',
    () async {
      final storage = const FlutterSecureStorage();
      final client = ApiClient(storage, baseUrl: 'https://api.example.test');
      client.dio.httpClientAdapter = CallbackAdapter(
        (_) => _jsonResponse(401, {
          'success': false,
          'data': null,
          'request_id': 'req_auth',
          'error': {
            'code': 'AUTHENTICATION_REQUIRED',
            'message': 'expired',
            'retryable': false,
          },
        }),
      );

      await expectLater(
        client.get('/api/private'),
        throwsA(
          isA<ApiFailure>()
              .having((error) => error.code, 'code', 'AUTHENTICATION_REQUIRED')
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.requestId, 'requestId', 'req_auth'),
        ),
      );
      expect(await storage.read(key: sessionIdStorageKey), isNull);
      expect(await storage.read(key: sessionExpiresAtStorageKey), isNull);
    },
  );
}

ResponseBody _jsonResponse(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class CallbackAdapter implements HttpClientAdapter {
  CallbackAdapter(this.callback);

  final ResponseBody Function(RequestOptions options) callback;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => callback(options);

  @override
  void close({bool force = false}) {}
}
