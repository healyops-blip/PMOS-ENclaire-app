import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmos_enclaire/features/certification/data/certification_repository.dart';

final certificationRepositoryProvider = Provider<CertificationRepository>(
  (ref) => LocalCertificationRepository(),
);
