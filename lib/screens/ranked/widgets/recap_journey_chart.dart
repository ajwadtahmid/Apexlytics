import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../utils/ranked/recap_journey.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// The climb of a period as one read-only line: where it started, where it
/// peaked and where it finished, marked on the line and named underneath. It is
/// the recap's picture of the period, not the Overview's chart: nothing to pick
/// or touch.
class RecapJourneyChart extends StatelessWidget {
  final Journey journey;
  const RecapJourneyChart({super.key, required this.journey});

  static const _startColor = AppTheme.muted;
  static const _peakColor = AppTheme.medalGold;
  static const _finishColor = AppTheme.accent;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final last = j.points.length - 1;
    final low = j.points.map((p) => p.rp).reduce((a, b) => a < b ? a : b);
    final high = j.peakRp;
    // A little room above and below, and some height for a flat period.
    final pad = ((high - low) * 0.12).clamp(5, double.infinity).toDouble();

    Color? colorAt(int index) {
      if (index == 0) return _startColor;
      if (index == last) return _finishColor;
      if (j.peakIsDistinct && index == j.peakIndex) return _peakColor;
      return null;
    }

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed height, so the picture is the same whatever the text size.
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: j.points.last.game.toDouble().clamp(1, double.infinity),
                minY: low - pad,
                maxY: high + pad,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (final p in j.points)
                        FlSpot(p.game.toDouble(), p.rp.toDouble()),
                    ],
                    color: _finishColor,
                    barWidth: 2.5,
                    isCurved: false,
                    belowBarData: BarAreaData(
                      show: true,
                      color: _finishColor.withAlpha(28),
                    ),
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, bar) =>
                          colorAt(bar.spots.indexOf(spot)) != null,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 5,
                            color: colorAt(index) ?? _finishColor,
                            strokeWidth: 2,
                            strokeColor: AppTheme.surface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          Wrap(
            spacing: AppTheme.lg,
            runSpacing: AppTheme.xs,
            children: [
              _Mark(color: _startColor, label: 'Start', rp: j.startRp),
              if (j.peakIsDistinct)
                _Mark(color: _peakColor, label: 'Peak', rp: j.peakRp),
              _Mark(color: _finishColor, label: 'Finish', rp: j.finishRp),
            ],
          ),
        ],
      ),
    );
  }
}

/// A coloured dot, the name of a point on the line and its RP.
class _Mark extends StatelessWidget {
  final Color color;
  final String label;
  final int rp;
  const _Mark({required this.color, required this.label, required this.rp});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label ', style: AppTheme.caption),
        Text(
          formatNumber(rp),
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
