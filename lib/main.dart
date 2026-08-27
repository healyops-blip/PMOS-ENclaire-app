import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmos_enclaire/app/pomi_app.dart';
import 'package:pmos_enclaire/features/weight/data/weight_repository.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({this.weightRepository, super.key});

  final WeightRepository? weightRepository;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: PomiApp(weightRepository: weightRepository));
  }
}
