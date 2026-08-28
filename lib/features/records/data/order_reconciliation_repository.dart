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
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(orderDate) &&
      DateTime.tryParse(orderDate) != null;

  Map<String, dynamic> toJson() => {
    'source_index': index,
    'confirmed': confirmed,
    'source_text': rawOrderText,
    'drug_name': drugName.trim(),
    'specification': specification.trim().isEmpty ? null : specification.trim(),
    'dosage_value': num.tryParse(dosageValue),
    'dosage_unit': dosageUnit.trim(),
    'frequency': frequency.trim(),
    'duration': course.trim().isEmpty ? null : course.trim(),
    'route': route.trim().isEmpty ? null : route.trim(),
    'instruction': instructions.trim().isEmpty ? null : instructions.trim(),
    'prescribed_at': orderDate,
    'explicitly_stopped': explicitlyStopped,
  };

  static List<MedicalOrderDraft> fromDraft(Map<String, dynamic> draft) {
    final date = draft['prescribed_at']?.toString() ?? '';
    final items = (draft['orders'] as List? ?? const []);
    return List.generate(items.length, (index) {
      final item = Map<String, dynamic>.from(items[index] as Map);
      return MedicalOrderDraft(
        index: index,
        drugName: item['drug_name']?.toString() ?? '',
        specification: item['specification']?.toString() ?? '',
        dosageValue: item['dosage_value']?.toString() ?? '',
        dosageUnit: item['dosage_unit']?.toString() ?? '',
        frequency: item['frequency']?.toString() ?? '',
        course: item['duration']?.toString() ?? '',
        route: item['route']?.toString() ?? '',
        instructions: item['instruction']?.toString() ?? '',
        rawOrderText: item['source_text']?.toString() ?? '',
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
    String resultId,
    String expectedRevisionId,
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
    String resultId,
    String expectedRevisionId,
    List<MedicalOrderDraft> items,
  ) async {
    try {
      await client.dio.post<Map<String, dynamic>>(
        '/ocr/tasks/$taskId/confirm',
        data: {
          'result_id': resultId,
          'expected_revision_id': expectedRevisionId,
          'items': items.map((item) => item.toJson()).toList(),
        },
      );
    } on DioException catch (error) {
      throw _exception(error);
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
      throw _exception(error);
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
                'stop_date': item.newOrder?['prescribed_at'],
                'stop_source': 'written_order',
              },
            };
          }).toList(),
        },
      );
      return MedicationReconciliationDraft.fromJson(_data(response.data));
    } on DioException catch (error) {
      throw _exception(error);
    }
  }

  static Map<String, dynamic> _data(Map<String, dynamic>? envelope) =>
      Map<String, dynamic>.from(envelope?['data'] as Map);

  static OrderReviewException _exception(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      final apiError = body['error'] as Map;
      final fieldErrors = <String, String>{};
      final details = apiError['details'];
      if (details is Map && details['fields'] is List) {
        for (final raw in details['fields'] as List) {
          if (raw is Map && raw['path'] != null && raw['message'] != null) {
            fieldErrors[raw['path'].toString()] = raw['message'].toString();
          }
        }
      }
      return OrderReviewException(
        apiError['message']?.toString() ?? '提交失败',
        fieldErrors: fieldErrors,
      );
    }
    return const OrderReviewException('网络连接中断，请稍后重试。');
  }
}

class OrderReviewException implements Exception {
  const OrderReviewException(this.message, {this.fieldErrors = const {}});
  final String message;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}
