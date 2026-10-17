import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/trend_window_provider.dart';
import '../../widgets/trend_arrow.dart';
import '../../utils/formatting/format.dart' show formatNumber, formatPercent, formatShortDate, formatSigned, formatSignedInt, plural;
import '../../utils/ranked/performance_insights.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/segmented_capsule.dart';
import '../../widgets/sheet_handle.dart';
import '../../widgets/surface_card.dart';
import '../../utils/ranked/slot_compare.dart';
import 'widgets/ranked_slot_chart.dart';
import '../../widgets/nav_entry_card.dart';

/// How many sessions the smoothed line averages over, and up to how many
/// plotted sessions each gets a dot.
const _kSmoothing = 3;
const _kDotsUpTo = 12;

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
    return NavEntryCard(
      icon: Icons.schedule,
      title: 'Performance Trends',
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedTimeBreakdownScreen(
              hourBuckets: hourBuckets,
              weekdayBuckets: weekdayBuckets,
              sessions: sessions,
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
class RankedTimeBreakdownScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final play = playTimeInsightsWithFallback(
      hourBuckets: hourBuckets,
      weekdayBuckets: weekdayBuckets,
    );
    // The counts of sessions on offer, and what the saved choice means for them.
    final choices = trendWindowChoices(sessions.length);
    final window = resolveTrendWindow(
      ref.watch(trendWindowProvider),
      sessions.length,
    );
    final headline = performanceHeadline(
      sessions: sessions,
      insights: play.insights,
      window: window.compare,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Trends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How to read this',
            onPressed: () => _showInfoSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            if (choices.isNotEmpty) ...[
              _SessionsShown(
                choices: choices,
                selected: window.size,
                onChanged: (n) => ref.read(trendWindowProvider.notifier).set(n),
              ),
              const SizedBox(height: AppTheme.md),
            ],
            if (headline != null) ...[
              _Headline(headline),
              const SizedBox(height: AppTheme.md),
            ],
            if (sessions.length >= 2) ...[
              _SessionSparklines(sessions: sessions, window: window),
              const SizedBox(height: AppTheme.lg),
            ],
            _PlayTimeInsights(
              insights: play.insights,
              lowSample: play.lowSample,
            ),
            RankedSlotChart.hours(a: hourSlots(hourBuckets)),
            const SizedBox(height: AppTheme.md),
            RankedSlotChart.days(a: weekdaySlots(weekdayBuckets)),
          ],
        ),
      ),
    );
  }
}

void _showInfoSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: AppTheme.md),
            const Text(
              'Performance Trends',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.md),
            for (final line in [
              'Sessions shown sets the headline and the trends: the latest '
                  'sessions against the same number before them. A count is '
                  'offered once you have twice as many sessions. All gives the '
                  'average over every session instead.',
              'When you play best and the hour and day charts use every game in '
                  'this period, whichever count is chosen.',
              'The light line over each chart averages every session with the '
                  'two before it, so one big night does not swing it.',
              'Game length and games per session are said as up or down: '
                  'neither is better or worse as it rises.',
              'In the hour and day charts, bars with under '
                  '$kMinGamesForInsight games are faded in the RP per game '
                  'view. Best and toughest times need $kPlayInsightGames games '
                  '(or $kPlayInsightLowSampleGames, shown as a hint, for newer '
                  'players).',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.sm),
                child: Text(line, style: AppTheme.captionLarge),
              ),
          ],
        ),
      ),
    ),
  );
}

/// How many of the latest sessions the headline and trends look at.
class _SessionsShown extends StatelessWidget {
  /// The counts on offer; "All" is always there as well.
  final List<int> choices;

  /// The count chosen, or null for all of them.
  final int? selected;
  final ValueChanged<int> onChanged;
  const _SessionsShown({
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Flexible(
          child: Text(
            'Sessions shown',
            overflow: TextOverflow.ellipsis,
            style: AppTheme.captionLarge,
          ),
        ),
        const Spacer(),
        SegmentedCapsule(
          options: [for (final n in choices) '$n', 'All'],
          selected: selected == null
              ? choices.length
              : choices.indexOf(selected!),
          onChanged: (i) =>
              onChanged(i < choices.length ? choices[i] : kTrendWindowAll),
        ),
      ],
    );
  }
}

/// The page in a sentence: how RP per game is moving, and when the player does
/// best.
class _Headline extends StatelessWidget {
  final PerformanceHeadline headline;
  const _Headline(this.headline);

  @override
  Widget build(BuildContext context) {
    final trend = headline.trend;
    final timing = headline.timing;
    final verdict = headline.verdict;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            height: 1.35,
          ),
          children: [
            if (trend != null)
              TextSpan(
                text: trend,
                style: TextStyle(
                  // A steady trend isn't good or bad, so it keeps the text colour.
                  color: headline.average != null
                      ? AppTheme.signColor(headline.average! >= 0)
                      : verdict == null || verdict == TrendVerdict.steady
                      ? AppTheme.textPrimary
                      : _verdictColor(verdict),
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (trend != null && timing != null) const TextSpan(text: '. '),
            if (timing != null) TextSpan(text: timing),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

/// RP/Kills/Damage per-game averages across the latest sessions, oldest to
/// newest, each with a line chart and a smoothed line over it. [window] says how
/// many sessions to plot and how many each side of the before/after averages
/// covers (none, with every session plotted). The date range covered and the
/// averages are spelled out explicitly — a bare line and a delta don't say what
/// changed or over what period.
class _SessionSparklines extends StatelessWidget {
  final List<RankedSession> sessions;
  final ({int? size, int compare}) window;
  const _SessionSparklines({required this.sessions, required this.window});

  @override
  Widget build(BuildContext context) {
    final size = window.size;
    // Newest-first, same order sessionize() returns.
    final shown = size == null ? sessions : sessions.take(size).toList();
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
                style: AppTheme.cardTitle,
              ),
              const SizedBox(width: AppTheme.sm),
              // Flexible, so a narrow screen or larger text shortens the range
              // instead of overflowing the row.
              Flexible(
                child: Text(
                  '${formatShortDate(oldest)} – ${formatShortDate(newest)}'
                  ' · ${shown.length} sessions',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.captionSmall,
                ),
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
            colorBySign: true,
            reference: 0,
            sessions: sessions,
            shown: shown,
            compare: window.compare,
          ),
          const SizedBox(height: AppTheme.lg),
          _SparklineRow(
            label: 'Win rate',
            measure: 'win rate',
            unit: 'results',
            steadyBand: kWinRateSteadyBand,
            valuesOf: (s) => s.wins,
            gamesOf: (s) => s.wins + s.losses,
            formatValue: (v) => formatPercent(v, decimals: 0),
            formatDelta: (v) =>
                '${v >= 0 ? '+' : '-'}${(v.abs() * 100).toStringAsFixed(1)} pts',
            // Half the games won: the line between winning more than losing
            // and the reverse.
            reference: 0.5,
            sessions: sessions,
            shown: shown,
            compare: window.compare,
          ),
          const SizedBox(height: AppTheme.lg),
          _SparklineRow(
            label: 'Kills per game',
            unit: 'kills',
            steadyBand: kKillsSteadyBand,
            valuesOf: (s) => s.totalKills,
            gamesOf: (s) => s.killsGames,
            formatValue: (v) => v.toStringAsFixed(1),
            formatDelta: formatSigned,
            sessions: sessions,
            shown: shown,
            compare: window.compare,
          ),
          const SizedBox(height: AppTheme.lg),
          _SparklineRow(
            label: 'Damage per game',
            unit: 'damage',
            steadyBand: kDamageSteadyBand,
            valuesOf: (s) => s.totalDamage,
            gamesOf: (s) => s.damageGames,
            formatValue: (v) => formatNumber(v.round()),
            formatDelta: (v) => formatSignedInt(v.round()),
            sessions: sessions,
            shown: shown,
            compare: window.compare,
          ),
          const SizedBox(height: AppTheme.lg),
          // Neither of these is better or worse as it rises, so they say up
          // and down and keep to one colour.
          _SparklineRow(
            label: 'Game length',
            measure: 'game length',
            unit: 'lengths',
            neutral: true,
            steadyBand: kGameLengthSteadyBand,
            valuesOf: (s) => s.totalLengthSecs,
            gamesOf: (s) => s.totalLengthSecs == 0 ? 0 : s.games,
            formatValue: _length,
            formatDelta: (v) => '${v >= 0 ? '+' : '-'}${_length(v.abs())}',
            sessions: sessions,
            shown: shown,
            compare: window.compare,
          ),
          const SizedBox(height: AppTheme.lg),
          _SparklineRow(
            label: 'Games per session',
            measure: 'games per session',
            unit: 'games',
            neutral: true,
            steadyBand: kSessionSizeSteadyBand,
            valuesOf: (s) => s.games,
            // Each session counts once, however many games it held.
            gamesOf: (s) => 1,
            formatValue: (v) => v.toStringAsFixed(1),
            formatDelta: formatSigned,
            sessions: sessions,
            shown: shown,
            compare: window.compare,
          ),
        ],
      ),
    );
  }
}

/// A game length in seconds as minutes and seconds: `14m 05s`.
String _length(double secs) {
  final total = secs.round();
  return '${total ~/ 60}m ${(total % 60).toString().padLeft(2, '0')}s';
}

class _SparklineRow extends StatelessWidget {
  final String label;

  /// What one unit of the metric is called when games are missing it, e.g.
  /// "kills".
  final String unit;

  /// The metric in a sentence about its change, e.g. "RP per game".
  final String measure;

  /// True for a metric that isn't better or worse as it rises (game length,
  /// games per session): its change is said as up or down, in one colour.
  final bool neutral;

  /// A value worth marking with a dashed line when the chart crosses it, such as
  /// 0 RP or a 50% win rate.
  final double? reference;

  /// Optional extra note for a trend, e.g. "still losing RP".
  final String? Function(TrendVerdict verdict, double recent)? caveat;
  final double steadyBand;
  final int Function(RankedSession) valuesOf;

  /// Games in a session that [valuesOf] actually covers; 0 means the session
  /// has no reading for this stat (no point is plotted for it).
  final int Function(RankedSession) gamesOf;
  final String Function(double) formatValue;

  /// Signed size of the change, e.g. "+15.0".
  final String Function(double) formatDelta;

  /// Whether a figure is green or red for a gain or a loss: right for RP, not
  /// for kills or damage.
  final bool colorBySign;

  /// Every session, newest first, for the before/after verdict.
  final List<RankedSession> sessions;

  /// The sessions to plot, newest first.
  final List<RankedSession> shown;

  /// How many sessions each side of the before/after averages covers; 0 to
  /// show the average over every session instead.
  final int compare;

  const _SparklineRow({
    required this.label,
    required this.unit,
    String? measure,
    this.neutral = false,
    this.reference,
    this.caveat,
    required this.steadyBand,
    required this.valuesOf,
    required this.gamesOf,
    required this.formatValue,
    required this.formatDelta,
    this.colorBySign = false,
    required this.sessions,
    required this.shown,
    required this.compare,
  }) : measure = measure ?? '$unit per game';

  /// How a verdict reads: "Improving" or "Up" for a metric with no good side.
  String _word(TrendVerdict verdict) => !neutral
      ? verdict.label
      : switch (verdict) {
          TrendVerdict.improving => 'Up',
          TrendVerdict.declining => 'Down',
          TrendVerdict.steady => 'Steady',
        };

  String _caveatSuffix(TrendVerdict verdict, double recent) {
    final note = caveat?.call(verdict, recent);
    return note == null ? '' : ', $note';
  }

  @override
  Widget build(BuildContext context) {
    // Oldest → newest within the shown window, for a left-to-right chart.
    final plot = shown.reversed.toList();
    final points = <double?>[
      for (final s in plot) gamesOf(s) == 0 ? null : valuesOf(s) / gamesOf(s),
    ];
    final plotted = points.nonNulls.toList();
    final smooth = movingAverage([
      for (final s in plot) (total: valuesOf(s), games: gamesOf(s)),
    ], window: _kSmoothing);
    // A smoothed line needs a few sessions to say anything.
    final showSmooth = plot.length > _kSmoothing && smooth.nonNulls.length > 1;

    final every = compare == 0;
    final trend = every
        ? null
        : sessionTrend(
            sessions,
            totalOf: valuesOf,
            gamesOf: gamesOf,
            window: compare,
          );
    // With every session in view there is no before and after: just the average.
    final totalGames = sessions.fold(0, (n, s) => n + gamesOf(s));
    final overall = totalGames == 0
        ? null
        : sessions.fold(0, (n, s) => n + valuesOf(s)) / totalGames;
    final verdict = trend == null
        ? null
        : trendVerdict(trend.delta, steadyBand: steadyBand);
    final inView = [...plotted, if (showSmooth) ...smooth.nonNulls];
    final minY = inView.isEmpty ? 0.0 : inView.reduce((a, b) => a < b ? a : b);
    final maxY = inView.isEmpty ? 0.0 : inView.reduce((a, b) => a > b ? a : b);
    // A flat window (every point equal) needs artificial padding, else
    // fl_chart's min==max range renders nothing.
    final pad = (maxY - minY).abs() < 0.01 ? 1.0 : (maxY - minY) * 0.15;
    Color figure(double v) =>
        colorBySign ? AppTheme.signColor(v >= 0) : AppTheme.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!every && trend != null && verdict != null)
              _TrendChange(
                verdict: verdict,
                neutral: neutral,
                previous: formatValue(trend.previous),
                recent: formatValue(trend.recent),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: AppTheme.captionSmall,
            children: [
              if (every)
                TextSpan(
                  text: overall == null
                      ? 'Not enough games with $unit reported.'
                      : 'Average over all ${plural(sessions.length, 'session')}: '
                            '${formatValue(overall)} $measure',
                )
              else if (trend == null || verdict == null)
                TextSpan(
                  text: sessions.length < compare * 2
                      ? 'Play at least ${compare * 2} sessions to see a '
                            'trend.'
                      : 'Not enough games with $unit reported to show a '
                            'trend.',
                )
              else ...[
                TextSpan(
                  text: verdict == TrendVerdict.steady
                      ? 'Steady:'
                      : '${_word(verdict)}: ${formatDelta(trend.delta)}',
                  style: TextStyle(
                    color: neutral && verdict != TrendVerdict.steady
                        ? AppTheme.textPrimary
                        : _verdictColor(verdict),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: verdict == TrendVerdict.steady
                      ? ' about the same as your $compare sessions before'
                      : ' $measure vs your $compare sessions '
                            'before${_caveatSuffix(verdict, trend.recent)}',
                ),
              ],
            ],
          ),
        ),
        if (plotted.isNotEmpty) ...[
          const SizedBox(height: AppTheme.sm),
          SizedBox(
            height: 72,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    // A value worth marking, when the chart crosses it: where RP
                    // turns from a gain into a loss, or a win rate passes half.
                    if (reference != null &&
                        minY < reference! &&
                        maxY > reference!)
                      HorizontalLine(
                        y: reference!,
                        color: AppTheme.muted.withValues(alpha: 0.5),
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.surface2,
                    getTooltipItems: (touched) => touched.map((s) {
                      // Only the session's own line speaks, not the smoothed one.
                      if (s.barIndex != 0) return null;
                      final idx = s.x.isNaN
                          ? 0
                          : s.x.toInt().clamp(0, plot.length - 1);
                      final value = points[idx];
                      if (value == null) return null;
                      return LineTooltipItem(
                        '${formatValue(value)} · '
                        '${formatShortDate(plot[idx].start)}',
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
                    // Sessions with no reading are skipped, not plotted as 0;
                    // x stays the session index so the tooltip lookup holds.
                    spots: [
                      for (final (i, v) in points.indexed)
                        if (v != null) FlSpot(i.toDouble(), v),
                    ],
                    color: AppTheme.accent,
                    barWidth: 2,
                    dotData: FlDotData(show: plot.length <= _kDotsUpTo),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppTheme.accent.withAlpha(25),
                    ),
                  ),
                  if (showSmooth)
                    LineChartBarData(
                      spots: [
                        for (final (i, v) in smooth.indexed)
                          if (v != null) FlSpot(i.toDouble(), v),
                      ],
                      color: AppTheme.textPrimary.withValues(alpha: 0.8),
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    style: AppTheme.captionSmall,
                    children: [
                      const TextSpan(text: 'Latest session '),
                      TextSpan(
                        text: formatValue(plotted.last),
                        style: TextStyle(
                          color: figure(plotted.last),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showSmooth) ...[
                const SizedBox(width: AppTheme.sm),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: AppTheme.captionSmall,
                      children: [
                        const TextSpan(text: 'Last $_kSmoothing averaged '),
                        TextSpan(
                          text: formatValue(smooth.nonNulls.last),
                          style: TextStyle(
                            color: figure(smooth.nonNulls.last),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
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

  /// A metric with no good side: the arrow and new value stay one colour.
  final bool neutral;
  final String previous;
  final String recent;
  const _TrendChange({
    required this.verdict,
    this.neutral = false,
    required this.previous,
    required this.recent,
  });

  @override
  Widget build(BuildContext context) {
    final color = neutral ? AppTheme.textPrimary : _verdictColor(verdict);
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
/// nothing until there are enough games to say anything fair; for a player with
/// few games it uses a lower bar and says so.
class _PlayTimeInsights extends StatelessWidget {
  final List<PlayInsight> insights;
  final bool lowSample;
  const _PlayTimeInsights({required this.insights, required this.lowSample});

  @override
  Widget build(BuildContext context) {
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
              style: AppTheme.cardTitle,
            ),
            const SizedBox(height: 2),
            Text(
              lowSample
                  ? 'Not many games yet, so this uses days and times with at '
                        'least $kPlayInsightLowSampleGames. Treat it as a hint.'
                  : 'Based on average RP per game, for days and times with at '
                        'least $kPlayInsightGames games.',
              style: AppTheme.captionSmall,
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
                  style: AppTheme.captionSmall,
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
                style: AppTheme.captionSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
