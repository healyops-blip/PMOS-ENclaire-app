import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';

class PomiLineChart extends StatelessWidget {
  const PomiLineChart({
    required this.values,
    required this.labels,
    this.color = PomiColors.primary,
    this.minY,
    this.maxY,
    this.normalLow,
    this.normalHigh,
    this.height = 170,
    super.key,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final double? minY;
  final double? maxY;
  final double? normalLow;
  final double? normalHigh;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final calculatedMin = values.reduce((a, b) => a < b ? a : b);
    final calculatedMax = values.reduce((a, b) => a > b ? a : b);
    final spread = (calculatedMax - calculatedMin).abs();
    final chartMin = minY ?? calculatedMin - (spread == 0 ? 1 : spread * 0.22);
    final chartMax = maxY ?? calculatedMax + (spread == 0 ? 1 : spread * 0.22);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (values.length - 1).toDouble(),
          minY: chartMin,
          maxY: chartMax,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0x126A4C93), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (normalLow != null)
                HorizontalLine(
                  y: normalLow!,
                  color: PomiColors.success.withValues(alpha: 0.35),
                  dashArray: [4, 4],
                ),
              if (normalHigh != null)
                HorizontalLine(
                  y: normalHigh!,
                  color: PomiColors.success.withValues(alpha: 0.35),
                  dashArray: [4, 4],
                ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 34),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      labels[index],
                      style: const TextStyle(
                        color: PomiColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var index = 0; index < values.length; index++)
                  FlSpot(index.toDouble(), values[index]),
              ],
              isCurved: true,
              curveSmoothness: 0.28,
              color: color,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: color,
                  strokeColor: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.22),
                    color.withValues(alpha: 0.01),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
      ),
    );
  }
}
