import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/trend_arrow.dart';
import '../../utils/formatting/format.dart' show formatSigned, formatNumber;
import '../../utils/ranked/performance_insights.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import 'widgets/ranked_day_of_week_chart.dart';
import 'widgets/ranked_time_of_day_chart.dart';

/// How many of the most recent sessions the sparklines plot.
const _kSparklineSessions = 10;

/// How many of the most recent sessions form each side of the before/after
/// averages shown next to each sparkline.
const _kTrendWindow = 5;

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
            _PlayTimeInsights(
              hourBuckets: hourBuckets,
              weekdayBuckets: weekdayBuckets,
            ),
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
            label: 'RP per game',
            unit: 'RP',
            caveat: rpCaveat,
            steadyBand: kRpSteadyBand,
            valuesOf: (s) => s.netRp,
            gamesOf: (s) => s.games,
            formatValue: (v) => formatSigned(v),
            formatDelta: formatSigned,
            sessions: sessions,
          ),
          const SizedBox(height: AppTheme.md),
          _SparklineRow(
            label: 'Kills per game',
            unit: 'kills',
            steadyBand: kKillsSteadyBand,
            valuesOf: (s) => s.totalKills,
            gamesOf: (s) => s.games,
            formatValue: (v) => v.toStringAsFixed(1),
            formatDelta: formatSigned,
            sessions: sessions,
          ),
          const SizedBox(height: AppTheme.md),
          _SparklineRow(
            label: 'Damage per game',
            unit: 'damage',
            steadyBand: kDamageSteadyBand,
            valuesOf: (s) => s.totalDamage,
            gamesOf: (s) => s.games,
            formatValue: (v) => v.toStringAsFixed(0),
            formatDelta: (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            sessions: sessions,
          ),
        ],
      ),
    );
  }
}

class _SparklineRow extends StatelessWidget {
  final String label;

  /// What one unit of the metric is called in the sentence, e.g. "kills".
  final String unit;

  /// Optional extra note for a trend, e.g. "still losing RP".
  final String? Function(TrendVerdict verdict, double recent)? caveat;
  final double steadyBand;
  final int Function(RankedSession) valuesOf;
  final int Function(RankedSession) gamesOf;
  final String Function(double) formatValue;

  /// Signed size of the change, e.g. "+15.0".
  final String Function(double) formatDelta;
  final List<RankedSession> sessions;

  const _SparklineRow({
    required this.label,
    required this.unit,
    this.caveat,
    required this.steadyBand,
    required this.valuesOf,
    required this.gamesOf,
    required this.formatValue,
    required this.formatDelta,
    required this.sessions,
  });

  String _caveatSuffix(TrendVerdict verdict, double recent) {
    final note = caveat?.call(verdict, recent);
    return note == null ? '' : ', $note';
  }

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
    final verdict = trend == null
        ? null
        : trendVerdict(trend.delta, steadyBand: steadyBand);
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
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trend != null && verdict != null)
              _TrendChange(
                verdict: verdict,
                previous: formatValue(trend.previous),
                recent: formatValue(trend.recent),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            children: [
              if (trend == null || verdict == null)
                const TextSpan(
                  text:
                      'Play at least ${_kTrendWindow * 2} sessions to see a '
                      'trend.',
                )
              else ...[
                TextSpan(
                  text: verdict == TrendVerdict.steady
                      ? 'Steady:'
                      : '${verdict.label}: ${formatDelta(trend.delta)}',
                  style: TextStyle(
                    color: _verdictColor(verdict),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: verdict == TrendVerdict.steady
                      ? ' about the same as your $_kTrendWindow sessions before'
                      : ' $unit per game vs your $_kTrendWindow sessions '
                            'before${_caveatSuffix(verdict, trend.recent)}',
                ),
              ],
            ],
          ),
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

Color _verdictColor(TrendVerdict v) => switch (v) {
  TrendVerdict.improving => AppTheme.green,
  TrendVerdict.steady => AppTheme.muted,
  TrendVerdict.declining => AppTheme.red,
};

/// Top-right of a sparkline row: the old value, the trend icon, then the new
/// value, the last two coloured by the verdict.
class _TrendChange extends StatelessWidget {
  final TrendVerdict verdict;
  final String previous;
  final String recent;
  const _TrendChange({
    required this.verdict,
    required this.previous,
    required this.recent,
  });

  @override
  Widget build(BuildContext context) {
    final color = _verdictColor(verdict);
    final delta = switch (verdict) {
      TrendVerdict.improving => 1.0,
      TrendVerdict.steady => 0.0,
      TrendVerdict.declining => -1.0,
    };
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        children: [
          TextSpan(
            text: previous,
            style: const TextStyle(color: AppTheme.muted),
          ),
          trendArrow(
            trendIcon(delta),
            color,
            size: 16,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          TextSpan(
            text: recent,
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }
}

/// Best and toughest day / time of day to play, in plain words. Renders
/// nothing until there are enough games to say anything fair.
class _PlayTimeInsights extends StatelessWidget {
  final List<HourBucket> hourBuckets;
  final List<WeekdayBucket> weekdayBuckets;
  const _PlayTimeInsights({
    required this.hourBuckets,
    required this.weekdayBuckets,
  });

  @override
  Widget build(BuildContext context) {
    final insights = playTimeInsights(
      hourBuckets: hourBuckets,
      weekdayBuckets: weekdayBuckets,
    );
    if (insights.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.md),
      child: SurfaceCard(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WHEN YOU PLAY BEST',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.muted,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Based on average RP per game, for days and times with at '
              'least 10 games.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
            const SizedBox(height: AppTheme.sm),
            for (final i in insights) _InsightRow(i),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final PlayInsight insight;
  const _InsightRow(this.insight);

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.signColor(insight.avgRp >= 0);
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.heading,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                Text(
                  insight.detail == null
                      ? insight.name
                      : '${insight.name} (${insight.detail})',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${formatSigned(insight.avgRp)} RP/game',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${formatNumber(insight.games)} games',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
