import 'package:dio/dio.dart';
import 'package:pmos_enclaire/core/network/pomi_api_client.dart';

class MedicalOrderDraft {
  MedicalOrderDraft({
    required this.index,
    required this.drugName,
    required this.specification,
    required this.dosageValue,
    required this.dosageUnit,
    required this.frequency,
    required this.course,
    required this.route,
    required this.instructions,
    required this.rawOrderText,
    required this.orderDate,
    this.explicitlyStopped = false,
    this.confirmed = false,
  });

  final int index;
  String drugName;
  String specification;
  String dosageValue;
  String dosageUnit;
  String frequency;
  String course;
  String route;
  String instructions;
  String rawOrderText;
  String orderDate;
  bool explicitlyStopped;
  bool confirmed;

  bool get isValid =>
      drugName.trim().isNotEmpty &&
      (num.tryParse(dosageValue) ?? 0) > 0 &&
      dosageUnit.trim().isNotEmpty &&
      frequency.trim().isNotEmpty &&
      rawOrderText.trim().isNotEmpty &&
      DateTime.tryParse(orderDate) != null;

  Map<String, dynamic> toJson() => {
    'index': index,
    'confirmed': confirmed,
    'drug_name': drugName.trim(),
    'specification': specification.trim().isEmpty ? null : specification.trim(),
    'dosage_value': num.tryParse(dosageValue),
    'dosage_unit': dosageUnit.trim(),
    'frequency': frequency.trim(),
    'course': course.trim().isEmpty ? null : course.trim(),
    'route': route.trim().isEmpty ? null : route.trim(),
    'instructions': instructions.trim().isEmpty ? null : instructions.trim(),
    'order_date': orderDate,
    'raw_order_text': rawOrderText.trim(),
    'explicitly_stopped': explicitlyStopped,
  };

  static List<MedicalOrderDraft> fromDraft(Map<String, dynamic> draft) {
    final date = draft['order_date']?.toString() ?? '';
    final items = (draft['medications'] as List? ?? const []);
    return List.generate(items.length, (index) {
      final item = Map<String, dynamic>.from(items[index] as Map);
      return MedicalOrderDraft(
        index: index,
        drugName: item['drug_name']?.toString() ?? '',
        specification: item['specification']?.toString() ?? '',
        dosageValue: item['dosage_value']?.toString() ?? '',
        dosageUnit: item['dosage_unit']?.toString() ?? '',
        frequency: item['frequency']?.toString() ?? '',
        course: item['course']?.toString() ?? '',
        route: item['route']?.toString() ?? '',
        instructions: item['instructions']?.toString() ?? '',
        rawOrderText: item['raw_order_text']?.toString() ?? '',
        orderDate: date,
        explicitlyStopped: item['explicitly_stopped'] as bool? ?? false,
      );
    });
  }
}

class ReconciliationItem {
  ReconciliationItem({
    required this.id,
    required this.suggestion,
    required this.oldMedication,
    required this.newOrder,
    required this.matchBasis,
    this.decision,
  });

  final String id;
  final String suggestion;
  final Map<String, dynamic>? oldMedication;
  final Map<String, dynamic>? newOrder;
  final Map<String, dynamic> matchBasis;
  String? decision;

  String get oldLabel => oldMedication?['drug_name']?.toString() ?? '无旧用药';
  String get newLabel => newOrder?['drug_name']?.toString() ?? '新医嘱未出现';
}

class MedicationReconciliationDraft {
  const MedicationReconciliationDraft({
    required this.id,
    required this.status,
    required this.ruleVersion,
    required this.items,
  });

  final String id;
  final String status;
  final String ruleVersion;
  final List<ReconciliationItem> items;

  factory MedicationReconciliationDraft.fromJson(Map<String, dynamic> json) =>
      MedicationReconciliationDraft(
        id: json['id'] as String,
        status: json['status'] as String,
        ruleVersion: json['rule_version'] as String,
        items: (json['items'] as List).map((raw) {
          final item = Map<String, dynamic>.from(raw as Map);
          return ReconciliationItem(
            id: item['id'] as String,
            suggestion: item['suggestion'] as String,
            oldMedication: item['old_medication'] == null
                ? null
                : Map<String, dynamic>.from(item['old_medication'] as Map),
            newOrder: item['new_medical_order'] == null
                ? null
                : Map<String, dynamic>.from(item['new_medical_order'] as Map),
            matchBasis: Map<String, dynamic>.from(item['match_basis'] as Map),
            decision: item['user_decision'] as String?,
          );
        }).toList(),
      );
}

abstract interface class MedicalOrderGateway {
  Future<void> confirmMedicalOrder(
    String taskId,
    List<MedicalOrderDraft> items,
  );
  Future<MedicationReconciliationDraft> createReconciliation(String taskId);
  Future<MedicationReconciliationDraft> executeReconciliation(
    MedicationReconciliationDraft reconciliation,
  );
}

class FastApiMedicalOrderGateway implements MedicalOrderGateway {
  FastApiMedicalOrderGateway(this.client);
  final PomiApiClient client;

  @override
  Future<void> confirmMedicalOrder(
    String taskId,
    List<MedicalOrderDraft> items,
  ) async {
    try {
      await client.dio.post<Map<String, dynamic>>(
        '/ocr/tasks/$taskId/confirm',
        data: {'items': items.map((item) => item.toJson()).toList()},
      );
    } on DioException catch (error) {
      throw OrderReviewException(_message(error));
    }
  }

  @override
  Future<MedicationReconciliationDraft> createReconciliation(
    String taskId,
  ) async {
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/medication-reconciliations',
        data: {'ocr_task_id': taskId},
      );
      return MedicationReconciliationDraft.fromJson(_data(response.data));
    } on DioException catch (error) {
      throw OrderReviewException(_message(error));
    }
  }

  @override
  Future<MedicationReconciliationDraft> executeReconciliation(
    MedicationReconciliationDraft reconciliation,
  ) async {
    try {
      final response = await client.dio.put<Map<String, dynamic>>(
        '/medication-reconciliations/${reconciliation.id}',
        data: {
          'decisions': reconciliation.items.map((item) {
            final stopped = item.suggestion == 'stopped';
            return {
              'item_id': item.id,
              'decision': item.decision,
              if (stopped && item.decision == 'accept') ...{
                'stop_date': DateTime.now().toIso8601String().split('T').first,
                'stop_source': 'written_order',
              },
            };
          }).toList(),
        },
      );
      return MedicationReconciliationDraft.fromJson(_data(response.data));
    } on DioException catch (error) {
      throw OrderReviewException(_message(error));
    }
  }

  static Map<String, dynamic> _data(Map<String, dynamic>? envelope) =>
      Map<String, dynamic>.from(envelope?['data'] as Map);

  static String _message(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      return (body['error'] as Map)['message']?.toString() ?? '提交失败';
    }
    return '网络连接中断，请稍后重试。';
  }
}

class OrderReviewException implements Exception {
  const OrderReviewException(this.message);
  final String message;

  @override
  String toString() => message;
}
