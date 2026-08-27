import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';

void main() {
  test(
    'loads the profile and completes onboarding with optimistic version',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    ..._profile,
                    if (options.method == 'PUT') 'onboarding_completed': true,
                  },
                  'request_id': 'req_test',
                  'error': null,
                },
              ),
            );
          },
        ),
      );
      final repository = FastApiPatientProfileRepository(
        PomiApiClient(dio: dio),
      );

      final result = await repository.update(
        PatientProfileInput(
          nickname: 'Pomi User',
          birthDate: DateTime(1996, 6, 18),
          nextVisitDate: null,
          completeOnboarding: true,
        ),
      );

      expect(result.onboardingCompleted, isTrue);
      expect(requests.map((request) => request.method), ['GET', 'PUT']);
      expect(
        DateTime.parse(requests.last.data['updated_at'] as String),
        DateTime.parse(_profile['updated_at'] as String),
      );
      expect(requests.last.data['next_visit_date'], isNull);
      expect(requests.last.data['complete_onboarding'], isTrue);
    },
  );
}

const _profile = <String, dynamic>{
  'patient_id': 'b97458cb-9af8-4565-af94-4dce6e033034',
  'nickname': null,
  'birth_date': null,
  'gender': null,
  'height_cm': null,
  'diagnosis_year': null,
  'primary_condition': null,
  'next_visit_date': null,
  'health_goal': null,
  'onboarding_completed': false,
  'onboarding_completed_at': null,
  'created_at': '2026-08-27T04:00:00+00:00',
  'updated_at': '2026-08-27T04:00:00+00:00',
};
