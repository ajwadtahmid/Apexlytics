import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// When the player performs best: a bar per active local hour. Bar height shows
/// how often that hour is played; colour shows whether RP is net gained (green)
/// or lost (red) in that hour.
class RankedTimeOfDayChart extends StatelessWidget {
  final List<RankedMatch> matches;
  const RankedTimeOfDayChart({super.key, required this.matches});

  @override
  Widget build(BuildContext context) {
    final buckets = timeOfDayBuckets(matches);
    if (buckets.length < 2) return const SizedBox.shrink();

    final maxGames =
        buckets.map((b) => b.games).reduce((a, b) => a > b ? a : b);

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Performance by Hour',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.muted,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Bar height = games played · green = net RP gain',
            style: TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: AppTheme.md),
          SizedBox(
            height: 130,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxGames * 1.25,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.surface2,
                    getTooltipItem: (group, _, rod, _) {
                      final b = buckets[group.x];
                      final sign = b.avgRpPerGame >= 0 ? '+' : '';
                      return BarTooltipItem(
                        '${_hourLabel(b.hourLocal)}\n'
                        '${b.games} games\n'
                        '$sign${b.avgRpPerGame.toStringAsFixed(1)} RP/game',
                        const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _hourLabel(buckets[i].hourLocal),
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 9),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: buckets.asMap().entries.map((e) {
                  final b = e.value;
                  final up = b.avgRpPerGame >= 0;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: b.games.toDouble(),
                        color: up ? AppTheme.green : AppTheme.red,
                        width: 12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 24h hour → compact 12h label, e.g. 0 → "12a", 14 → "2p".
  static String _hourLabel(int hour) {
    final period = hour < 12 ? 'a' : 'p';
    var h = hour % 12;
    if (h == 0) h = 12;
    return '$h$period';
  }
}
