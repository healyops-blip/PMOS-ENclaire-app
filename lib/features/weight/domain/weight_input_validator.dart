String? validateWeightInput(String input) {
  final value = input.trim();
  if (value.isEmpty) return '请输入体重';
  if (RegExp(r'^\d+\.\d{2,}$').hasMatch(value)) return '最多保留一位小数';
  if (!RegExp(r'^\d+(?:\.\d)?$').hasMatch(value)) return '请输入有效数字';

  final parsed = double.tryParse(value);
  if (parsed == null) return '请输入有效数字';
  if (parsed < 20 || parsed > 300) return '体重需在 20.0–300.0 kg 之间';
  return null;
}
