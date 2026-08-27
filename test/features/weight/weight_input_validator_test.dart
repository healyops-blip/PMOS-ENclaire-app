import 'package:flutter_test/flutter_test.dart';
import 'package:pmos_enclaire/features/weight/domain/weight_input_validator.dart';

void main() {
  test('matches backend weight range and decimal precision', () {
    expect(validateWeightInput(''), '请输入体重');
    expect(validateWeightInput('abc'), '请输入有效数字');
    expect(validateWeightInput('63.55'), '最多保留一位小数');
    expect(validateWeightInput('19.9'), '体重需在 20.0–300.0 kg 之间');
    expect(validateWeightInput('300.1'), '体重需在 20.0–300.0 kg 之间');
    expect(validateWeightInput('20.0'), isNull);
    expect(validateWeightInput('63'), isNull);
    expect(validateWeightInput('300.0'), isNull);
  });
}
