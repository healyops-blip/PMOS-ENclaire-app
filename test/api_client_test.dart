import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';

void main() {
  test(
    'API client supports raw auth responses, envelopes, bearer, and 204',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        sessionIdStorageKey: 'local-session',
        sessionExpiresAtStorageKey: '2099-01-01T00:00:00Z',
      });
      const storage = FlutterSecureStorage();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      String? authorization;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/raw':
            request.response.write(jsonEncode({'session_id': 'raw-session'}));
          case '/wrapped':
            request.response.write(
              jsonEncode({
                'data': {'ok': true},
              }),
            );
          case '/me':
            authorization = request.headers.value(
              HttpHeaders.authorizationHeader,
            );
            request.response.write(jsonEncode({'uid': 'account-uid'}));
          case '/logout':
            request.response.statusCode = HttpStatus.noContent;
          case '/expired':
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.write(
              jsonEncode({
                'error': {
                  'code': 'AUTHENTICATION_REQUIRED',
                  'message': 'Authentication is required.',
                },
              }),
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final client = ApiClient(
        storage,
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      expect(await client.get('/raw'), {'session_id': 'raw-session'});
      expect(await client.get('/wrapped'), {'ok': true});
      expect(await client.get('/me'), {'uid': 'account-uid'});
      expect(authorization, 'Bearer local-session');
      expect(await client.post('/logout'), isNull);

      await expectLater(
        client.get('/expired'),
        throwsA(
          isA<ApiFailure>()
              .having((error) => error.code, 'code', 'AUTHENTICATION_REQUIRED')
              .having((error) => error.statusCode, 'statusCode', 401),
        ),
      );
      expect(await storage.read(key: sessionIdStorageKey), isNull);
      expect(await storage.read(key: sessionExpiresAtStorageKey), isNull);
    },
  );
}
