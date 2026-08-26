import 'package:dio/dio.dart';

class PomiApiClient {
  PomiApiClient({
    String baseUrl = 'https://api.healy1012-ops.top/api',
    Dio? dio,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 30),
               headers: const {'Accept': 'application/json'},
             ),
           );

  final Dio dio;

  void useSession(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) {
      dio.options.headers.remove('X-Session-ID');
    } else {
      dio.options.headers['X-Session-ID'] = sessionId;
    }
  }
}
