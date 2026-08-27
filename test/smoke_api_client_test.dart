import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('smoke API completes onboarding and populates the dashboard', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = SmokeApiClient(const FlutterSecureStorage());

    final login = Map<String, dynamic>.from(
      await api.post(
            '/api/auth/login',
            data: {'account_name': 'preview.user', 'password': 'Password1'},
          )
          as Map,
    );
    expect(login['session_id'], 'smoke-session');
    expect((login['account'] as Map)['onboarding_completed'], isFalse);

    await api.put(
      '/api/patient/profile',
      data: {
        'nickname': '小波米',
        'birth_date': '1997-01-01',
        'diagnosis_year': 2023,
      },
    );
    await api.post(
      '/api/weights',
      data: {'measured_at': '2026-08-27T00:00:00Z', 'weight_kg': 55.0},
    );
    await api.post(
      '/api/cycles',
      data: {'start_date': '2026-08-20', 'flow_level': 'medium'},
    );
    await api.post(
      '/api/medications',
      data: {'drug_name': '肌醇', 'current_status': 'active'},
    );

    final dashboard = Map<String, dynamic>.from(
      await api.get('/api/dashboard') as Map,
    );
    expect((dashboard['profile'] as Map)['nickname'], '小波米');
    expect((dashboard['latest_weight'] as Map)['weight_kg'], 55.0);
    expect((dashboard['latest_cycle'] as Map)['start_date'], '2026-08-20');
    expect((dashboard['medications'] as List), hasLength(1));
  });
}
