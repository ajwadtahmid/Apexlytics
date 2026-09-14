import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// When the player performs best: a bar per active local day-of-week. Bar
/// height shows how often that day is played; colour shows whether RP is net
/// gained (green) or lost (red) on that day. Takes precomputed [buckets] so it
/// works off either an in-memory split's matches or the SQL Lifetime scope —
/// the latter never hydrates full matches, just a lightweight
/// start-time/RP projection.
class RankedDayOfWeekChart extends StatelessWidget {
  final List<WeekdayBucket> buckets;
  const RankedDayOfWeekChart({super.key, required this.buckets});

  @override
  Widget build(BuildContext context) {
    if (buckets.length < 2) return const SizedBox.shrink();

    final maxGames = buckets
        .map((b) => b.games)
        .reduce((a, b) => a > b ? a : b);

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Performance by Day',
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
                        '${_weekdayLabel(b.weekday)}\n'
                        '${b.games} games\n'
                        '$sign${b.avgRpPerGame.toStringAsFixed(1)} RP/game',
                        const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
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
                            _weekdayLabel(buckets[i].weekday),
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 9,
                            ),
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
                        width: 18,
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

  /// DateTime.weekday (1=Monday..7=Sunday) → 3-letter label.
  static String _weekdayLabel(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
}
