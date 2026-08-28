import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pmos_enclaire/core/api_client.dart';

class ApiCall {
  const ApiCall({
    required this.method,
    required this.path,
    this.data,
    this.headers,
    this.queryParameters,
  });

  final String method;
  final String path;
  final Object? data;
  final Map<String, String>? headers;
  final Map<String, dynamic>? queryParameters;
}

class FakeApiClient extends ApiClient {
  FakeApiClient({required this.handler})
    : super(const FlutterSecureStorage(), baseUrl: 'https://example.invalid');

  final dynamic Function(ApiCall call) handler;
  final List<ApiCall> calls = [];

  Future<dynamic> _handle(ApiCall call) async {
    calls.add(call);
    final value = handler(call);
    return value is Future ? await value : value;
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _handle(
        ApiCall(method: 'GET', path: path, queryParameters: queryParameters),
      );

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) => _handle(
    ApiCall(method: 'POST', path: path, data: data, headers: headers),
  );

  @override
  Future<dynamic> put(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) =>
      _handle(ApiCall(method: 'PUT', path: path, data: data, headers: headers));

  @override
  Future<dynamic> delete(String path, {Object? data}) =>
      _handle(ApiCall(method: 'DELETE', path: path, data: data));
}
