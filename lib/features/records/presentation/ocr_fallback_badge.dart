import 'package:flutter/material.dart';

class OcrFallbackBadge extends StatelessWidget {
  const OcrFallbackBadge({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('ocr-fallback-badge'),
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 10 : 14,
      vertical: compact ? 6 : 10,
    ),
    decoration: BoxDecoration(
      color: Colors.amber.shade100,
      border: Border.all(color: Colors.amber.shade700),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(Icons.science_outlined, size: 18, color: Colors.amber.shade900),
        const SizedBox(width: 8),
        const Flexible(
          child: Text(
            '演示兜底结果 · 非实时模型识别，仍需逐项人工确认',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
