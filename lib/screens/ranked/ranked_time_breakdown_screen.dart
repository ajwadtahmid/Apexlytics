import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/formatting/format.dart' show formatSigned;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import 'widgets/ranked_day_of_week_chart.dart';
import 'widgets/ranked_time_of_day_chart.dart';

/// How many of the most recent sessions the sparklines plot.
const _kSparklineSessions = 10;

/// How many of the most recent sessions form each side of the before/after
/// averages shown next to each sparkline.
const _kTrendWindow = 3;

final _rangeFmt = DateFormat('MMM d');

/// Entry point for "Performance Trends": recent session-over-session
/// sparklines up top, then the existing hour-of-day/day-of-week breakdown —
/// out of the main Overview list so it doesn't compete for space with the
/// RP-focused cards there. [sessions] drives the sparklines and is expected
/// empty at Lifetime scope (sessions are a split-relative concept — Lifetime
/// never hydrates matches); the hour/day charts work at either scope.
class RankedTimeBreakdownEntry extends StatelessWidget {
  final List<HourBucket> hourBuckets;
  final List<WeekdayBucket> weekdayBuckets;
  final List<RankedSession> sessions;
  const RankedTimeBreakdownEntry({
    super.key,
    required this.hourBuckets,
    required this.weekdayBuckets,
    this.sessions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedTimeBreakdownScreen(
              hourBuckets: hourBuckets,
              weekdayBuckets: weekdayBuckets,
              sessions: sessions,
            ),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(Icons.schedule, size: 18, color: AppTheme.accent),
              SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  'Performance Trends',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Session sparklines (when available) followed by the hour-of-day and
/// day-of-week charts. The latter two take precomputed buckets, so they work
/// unchanged at split or Lifetime scope; the sparklines need [sessions] and
/// simply don't render without them.
class RankedTimeBreakdownScreen extends StatelessWidget {
  final List<HourBucket> hourBuckets;
  final List<WeekdayBucket> weekdayBuckets;
  final List<RankedSession> sessions;
  const RankedTimeBreakdownScreen({
    super.key,
    required this.hourBuckets,
    required this.weekdayBuckets,
    this.sessions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance Trends')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            if (sessions.length >= 2) ...[
              _SessionSparklines(sessions: sessions),
              const SizedBox(height: AppTheme.lg),
            ],
            RankedTimeOfDayChart(buckets: hourBuckets),
            const SizedBox(height: AppTheme.md),
            RankedDayOfWeekChart(buckets: weekdayBuckets),
          ],
        ),
      ),
    );
  }
}

/// RP/Kills/Damage per-game averages across the most recent
/// [_kSparklineSessions] sessions, oldest to newest, each with a small line
/// chart. The date range covered and the before/after averages (last
/// [_kTrendWindow] sessions vs. the [_kTrendWindow] before that) are spelled
/// out explicitly — a bare line and a delta don't say what changed or over
/// what period.
class _SessionSparklines extends StatelessWidget {
  final List<RankedSession> sessions;
  const _SessionSparklines({required this.sessions});

  @override
  Widget build(BuildContext context) {
    // Newest-first, same order sessionize() returns.
    final shown = sessions.take(_kSparklineSessions).toList();
    final oldest = shown.last.start.toLocal();
    final newest = shown.first.end.toLocal();

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RECENT TREND',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.muted,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${_rangeFmt.format(oldest)} – ${_rangeFmt.format(newest)}'
                ' · last ${shown.length} sessions',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.md),
          _SparklineRow(
            label: 'RP',
            valuesOf: (s) => s.netRp,
            gamesOf: (s) => s.games,
            formatValue: (v) => formatSigned(v),
            sessions: sessions,
          ),
          const SizedBox(height: AppTheme.md),
          _SparklineRow(
            label: 'Kills',
            valuesOf: (s) => s.totalKills,
            gamesOf: (s) => s.games,
            formatValue: (v) => v.toStringAsFixed(1),
            sessions: sessions,
          ),
          const SizedBox(height: AppTheme.md),
          _SparklineRow(
            label: 'Damage',
            valuesOf: (s) => s.totalDamage,
            gamesOf: (s) => s.games,
            formatValue: (v) => v.toStringAsFixed(0),
            sessions: sessions,
          ),
        ],
      ),
    );
  }
}

class _SparklineRow extends StatelessWidget {
  final String label;
  final int Function(RankedSession) valuesOf;
  final int Function(RankedSession) gamesOf;
  final String Function(double) formatValue;
  final List<RankedSession> sessions;

  const _SparklineRow({
    required this.label,
    required this.valuesOf,
    required this.gamesOf,
    required this.formatValue,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    // Oldest → newest within the shown window, for a left-to-right chart.
    final shown = sessions.take(_kSparklineSessions).toList().reversed.toList();
    final points = [
      for (final s in shown) gamesOf(s) == 0 ? 0.0 : valuesOf(s) / gamesOf(s),
    ];

    final trend = sessionTrend(
      sessions,
      totalOf: valuesOf,
      gamesOf: gamesOf,
      window: _kTrendWindow,
    );
    final delta = trend?.delta ?? 0;
    final deltaColor = delta > 0
        ? AppTheme.green
        : delta < 0
        ? AppTheme.red
        : AppTheme.muted;

    final minY = points.reduce((a, b) => a < b ? a : b);
    final maxY = points.reduce((a, b) => a > b ? a : b);
    // A flat window (every point equal) needs artificial padding, else
    // fl_chart's min==max range renders nothing.
    final pad = (maxY - minY).abs() < 0.01 ? 1.0 : (maxY - minY) * 0.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
            if (trend != null)
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: formatValue(trend.previous),
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                    TextSpan(
                      text: '  →  ',
                      style: TextStyle(color: deltaColor),
                    ),
                    TextSpan(
                      text: formatValue(trend.recent),
                      style: TextStyle(color: deltaColor),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: LineChart(
            LineChartData(
              minY: minY - pad,
              maxY: maxY + pad,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppTheme.surface2,
                  getTooltipItems: (touched) => touched.map((s) {
                    final idx = s.x.isNaN
                        ? 0
                        : s.x.toInt().clamp(0, shown.length - 1);
                    return LineTooltipItem(
                      '${formatValue(points[idx])} · '
                      '${_rangeFmt.format(shown[idx].start.toLocal())}',
                      const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final (i, v) in points.indexed)
                      FlSpot(i.toDouble(), v),
                  ],
                  color: AppTheme.accent,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppTheme.accent.withAlpha(25),
                  ),
                  isCurved: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
