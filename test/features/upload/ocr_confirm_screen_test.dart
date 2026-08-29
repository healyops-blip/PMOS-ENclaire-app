import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/core/api_client.dart';
import 'package:pmos_enclaire/core/theme.dart';
import 'package:pmos_enclaire/features/upload/upload_screen.dart';

class _FieldErrorApiClient extends ApiClient {
  _FieldErrorApiClient() : super(const FlutterSecureStorage());

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    throw ApiFailure(
      'OCR_CONFIRMATION_INVALID',
      '报告中有项目未通过校验（如单位无法识别），请修正后重试',
      statusCode: 422,
      details: {
        'fields': [
          {
            'path': 'items.0.value',
            'code': 'LAB_VALUE_INVALID',
            'message': '数值格式无法解析。',
          },
          {
            'path': 'items.1.unit',
            'code': 'LAB_UNIT_UNSUPPORTED',
            'message': '单位不在允许范围内。',
          },
        ],
      },
    );
  }
}

void main() {
  testWidgets('confirm screen only shows the report JSON allowlisted fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPomiTheme(),
        home: const OcrConfirmScreen(
          resultId: 'result-1',
          revisionId: 'rev-1',
          materialType: 'outpatient_record',
          resultSource: 'qwen3-vl',
          draft: {
            'doc_id': 'MR00020',
            'hospital': '测试医院',
            'evidence': 'internal evidence',
            'model': 'internal model metadata',
            'examinations': [
              {
                'item_name': '体温',
                'value': '37.3',
                'unit': '℃',
                'reference_range': '36-37.5',
                'abnormal': false,
                'source_text': 'internal source text',
              },
            ],
            'medication_suggestions': <Map<String, dynamic>>[],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MR00020'), findsOneWidget);
    expect(find.text('测试医院'), findsOneWidget);
    expect(find.text('internal evidence'), findsNothing);
    expect(find.text('internal model metadata'), findsNothing);
    expect(find.text('internal source text'), findsNothing);
  });

  testWidgets('confirm screen surfaces backend field errors on each row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_FieldErrorApiClient()),
        ],
        child: MaterialApp(
          theme: buildPomiTheme(),
          home: const OcrConfirmScreen(
            resultId: 'result-1',
            revisionId: 'rev-1',
            materialType: 'lab_report',
            resultSource: 'qwen3-vl',
            draft: {
              'hospital': '测试医院',
              'examinations': [
                {'item_name': '白细胞计数', 'value': '6 ×10^9/L', 'unit': '×10^9/L'},
                {'item_name': '空腹血糖', 'value': '5', 'unit': 'x'},
              ],
              'medication_suggestions': <Map<String, dynamic>>[],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认并入库'));
    await tester.pumpAndSettle();

    // 顶部横幅列出全部出错项。
    expect(find.text('有 2 处需要修正'), findsOneWidget);
    expect(find.textContaining('数值格式无法解析'), findsWidgets);
    expect(find.textContaining('单位不在允许范围内'), findsWidgets);

    // 出错原因就地显示在对应输入框下方（errorText）。
    final decorations =
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.decoration)
            .whereType<InputDecoration>();
    expect(
      decorations.any((d) => d.labelText == '数值' && d.errorText == '数值格式无法解析。'),
      isTrue,
    );
  });
}
