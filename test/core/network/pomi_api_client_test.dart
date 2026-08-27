import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';

void main() {
  test('uses the backend Bearer session header and clears it', () {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    final client = PomiApiClient(dio: dio);

    client.useSession('session-secret');
    expect(dio.options.headers['Authorization'], 'Bearer session-secret');
    expect(dio.options.headers.containsKey('X-Session-ID'), isFalse);

    client.useSession(null);
    expect(dio.options.headers.containsKey('Authorization'), isFalse);
  });
}
