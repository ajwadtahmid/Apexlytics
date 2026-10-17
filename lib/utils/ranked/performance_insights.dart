import 'ranked_aggregates.dart';

/// Plain-language reading of a before/after trend.
enum TrendVerdict {
  improving('Improving'),
  steady('Steady'),
  declining('Declining');

  final String label;
  const TrendVerdict(this.label);
}

/// A per-game change smaller than this reads as "steady" rather than a trend.
const kRpSteadyBand = 1.0;
const kKillsSteadyBand = 0.1;
const kDamageSteadyBand = 20.0;

/// The same for win rate (a fraction: 2 points), game length (seconds: half a
/// minute) and games per session.
const kWinRateSteadyBand = 0.02;
const kGameLengthSteadyBand = 30.0;
const kSessionSizeSteadyBand = 0.5;

/// A short note for an RP trend whose direction and sign disagree: losing
/// less RP is "improving" but the average is still a loss, and the reverse.
String? rpCaveat(TrendVerdict verdict, double recentAvgRp) =>
    verdict == TrendVerdict.improving && recentAvgRp < 0
    ? 'still losing RP'
    : verdict == TrendVerdict.declining && recentAvgRp > 0
    ? 'still gaining RP'
    : null;

TrendVerdict trendVerdict(double delta, {required double steadyBand}) =>
    delta.abs() < steadyBand
    ? TrendVerdict.steady
    : delta > 0
    ? TrendVerdict.improving
    : TrendVerdict.declining;

/// How many of the latest sessions the trends can look at, and the one chosen
/// when nothing has been picked.
const kTrendWindowPresets = [5, 10, 25, 50];
const kDefaultTrendWindow = 5;

/// Saved in place of a count to mean every session.
const kTrendWindowAll = 0;

/// The counts on offer for [sessionCount] sessions: those with twice as many
/// sessions behind them, so the latest N can be set against the N before.
List<int> trendWindowChoices(int sessionCount) => [
  for (final n in kTrendWindowPresets)
    if (n * 2 <= sessionCount) n,
];

/// What a saved choice means for [sessionCount] sessions: how many to plot
/// ([size], null for all of them) and how many to compare against the same
/// number before ([compare], 0 for no comparison).
///
/// A saved count that is too big for these sessions becomes the largest that
/// fits. With too few sessions for any, everything is plotted and the default is
/// kept as the comparison, so the page can say how many it needs.
({int? size, int compare}) resolveTrendWindow(int saved, int sessionCount) {
  final choices = trendWindowChoices(sessionCount);
  if (choices.isEmpty) return (size: null, compare: kDefaultTrendWindow);
  if (saved == kTrendWindowAll) return (size: null, compare: 0);
  final fits = choices.where((n) => n <= saved);
  final n = fits.isEmpty ? choices.first : fits.last;
  return (size: n, compare: n);
}

/// Coarse parts of the day, so a handful of games per hour adds up to
/// something worth reading.
enum DayPart {
  morning('Morning', '5 AM – 12 PM'),
  afternoon('Afternoon', '12 – 5 PM'),
  evening('Evening', '5 – 10 PM'),
  night('Night', '10 PM – 5 AM');

  final String label;
  final String hours;
  const DayPart(this.label, this.hours);
}

DayPart dayPartOfHour(int hour) => hour >= 5 && hour < 12
    ? DayPart.morning
    : hour >= 12 && hour < 17
    ? DayPart.afternoon
    : hour >= 17 && hour < 22
    ? DayPart.evening
    : DayPart.night;

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// One "best / toughest time to play" line.
class PlayInsight {
  final String heading; // e.g. "Best day"
  final String name; // e.g. "Saturday"
  final String? detail; // e.g. "5 – 10 PM"
  final double avgRp;
  final int games;
  const PlayInsight({
    required this.heading,
    required this.name,
    this.detail,
    required this.avgRp,
    required this.games,
  });
}

/// How many games a day or part of the day needs for its insight to be solid,
/// and for a light player's fallback.
const kPlayInsightGames = 10;
const kPlayInsightLowSampleGames = 5;

/// Best and toughest day of the week and part of the day, by average RP per
/// game. A slot needs at least [minGames] games to count, and a pair is only
/// reported when the two differ by at least [minGap] RP per game — otherwise
/// there is no real pattern to point at.
List<PlayInsight> playTimeInsights({
  required List<HourBucket> hourBuckets,
  required List<WeekdayBucket> weekdayBuckets,
  int minGames = kPlayInsightGames,
  double minGap = 1.0,
}) {
  final days = <int, ({int games, int netRp})>{
    for (final b in weekdayBuckets) b.weekday: (games: b.games, netRp: b.netRp),
  };
  final parts = <DayPart, ({int games, int netRp})>{};
  for (final b in hourBuckets) {
    final p = dayPartOfHour(b.hourLocal);
    final cur = parts[p] ?? (games: 0, netRp: 0);
    parts[p] = (games: cur.games + b.games, netRp: cur.netRp + b.netRp);
  }

  return [
    ..._bestAndWorst<int>(
      days,
      minGames: minGames,
      minGap: minGap,
      bestHeading: 'Best day',
      worstHeading: 'Toughest day',
      nameOf: (d) => _weekdayNames[d - 1],
    ),
    ..._bestAndWorst<DayPart>(
      parts,
      minGames: minGames,
      minGap: minGap,
      bestHeading: 'Best time of day',
      worstHeading: 'Toughest time of day',
      nameOf: (p) => p.label,
      detailOf: (p) => p.hours,
    ),
  ];
}

List<PlayInsight> _bestAndWorst<K>(
  Map<K, ({int games, int netRp})> slots, {
  required int minGames,
  required double minGap,
  required String bestHeading,
  required String worstHeading,
  required String Function(K) nameOf,
  String Function(K)? detailOf,
}) {
  final eligible = slots.entries.where((e) => e.value.games >= minGames);
  if (eligible.length < 2) return const [];
  double avg(MapEntry<K, ({int games, int netRp})> e) =>
      e.value.netRp / e.value.games;
  final sorted = eligible.toList()..sort((a, b) => avg(b).compareTo(avg(a)));
  final best = sorted.first;
  final worst = sorted.last;
  if (avg(best) - avg(worst) < minGap) return const [];
  PlayInsight insight(
    String heading,
    MapEntry<K, ({int games, int netRp})> e,
  ) => PlayInsight(
    heading: heading,
    name: nameOf(e.key),
    detail: detailOf?.call(e.key),
    avgRp: avg(e),
    games: e.value.games,
  );
  return [insight(bestHeading, best), insight(worstHeading, worst)];
}

/// [playTimeInsights] at the usual sample size, or, when that finds nothing
/// because the player hasn't played much, at a lower one. [lowSample] says which,
/// so the lines can be shown as a hint rather than a finding.
({List<PlayInsight> insights, bool lowSample}) playTimeInsightsWithFallback({
  required List<HourBucket> hourBuckets,
  required List<WeekdayBucket> weekdayBuckets,
}) {
  final solid = playTimeInsights(
    hourBuckets: hourBuckets,
    weekdayBuckets: weekdayBuckets,
  );
  if (solid.isNotEmpty) return (insights: solid, lowSample: false);
  final thin = playTimeInsights(
    hourBuckets: hourBuckets,
    weekdayBuckets: weekdayBuckets,
    minGames: kPlayInsightLowSampleGames,
  );
  return (insights: thin, lowSample: thin.isNotEmpty);
}

/// One sentence on how the player is doing and when they do best: how RP per
/// game moved over the latest [window] sessions against the ones before, and the
/// best day and part of the day. Either part may be missing.
class PerformanceHeadline {
  /// "Up 4.1 RP per game over your last 5 sessions", or null without a trend.
  final String? trend;
  final TrendVerdict? verdict;

  /// The average RP per game, when [trend] is that rather than a change.
  final double? average;

  /// "You do best on Fridays, in the evening", or null without insights.
  final String? timing;
  const PerformanceHeadline({
    this.trend,
    this.verdict,
    this.average,
    this.timing,
  });
}

/// The headline for [sessions] (newest first) and [insights], or null when
/// there is neither a trend nor a best time to report. With a [window] of 0 the
/// trend is the average over every session rather than a change.
PerformanceHeadline? performanceHeadline({
  required List<RankedSession> sessions,
  required List<PlayInsight> insights,
  int window = kDefaultTrendWindow,
}) {
  final everyGame = sessions.fold(0, (n, s) => n + s.games);
  final average = window == kTrendWindowAll && everyGame > 0
      ? sessions.fold(0, (n, s) => n + s.netRp) / everyGame
      : null;
  final trend = window == kTrendWindowAll
      ? null
      : sessionTrend(
          sessions,
          totalOf: (s) => s.netRp,
          gamesOf: (s) => s.games,
          window: window,
        );
  final verdict = trend == null
      ? null
      : trendVerdict(trend.delta, steadyBand: kRpSteadyBand);
  final String? trendText = average != null
      ? 'Averaging ${_signed(average)} RP per game over all '
            '${sessions.length} sessions'
      : trend == null || verdict == null
      ? null
      : switch (verdict) {
          TrendVerdict.improving =>
            'Up ${trend.delta.abs().toStringAsFixed(1)} RP per game over your '
                'last $window sessions',
          TrendVerdict.declining =>
            'Down ${trend.delta.abs().toStringAsFixed(1)} RP per game over '
                'your last $window sessions',
          TrendVerdict.steady => 'Steady over your last $window sessions',
        };

  PlayInsight? named(String heading) =>
      insights.where((i) => i.heading == heading).firstOrNull;
  final day = named('Best day');
  final part = named('Best time of day');
  final timing = switch ((day, part)) {
    (final d?, final p?) => 'You do best on ${d.name}s, ${_inThe(p.name)}',
    (final d?, null) => 'You do best on ${d.name}s',
    (null, final p?) => 'You do best ${_inThe(p.name)}',
    _ => null,
  };

  if (trendText == null && timing == null) return null;
  return PerformanceHeadline(
    trend: trendText,
    verdict: verdict,
    average: average,
    timing: timing,
  );
}

String _signed(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';

/// "in the evening", "at night".
String _inThe(String part) =>
    part == DayPart.night.label ? 'at night' : 'in the ${part.toLowerCase()}';

/// One session's total and the games it covers, for [movingAverage]. A session
/// with no [games] has no reading.
typedef SessionReading = ({int total, int games});

/// A per-game average that smooths [readings] (oldest first): each point is the
/// total over the games of itself and the [window] - 1 before it, divided by
/// those games, so one big night doesn't swing it. Null where the session has
/// no reading of its own.
List<double?> movingAverage(List<SessionReading> readings, {int window = 3}) {
  return [
    for (var i = 0; i < readings.length; i++)
      if (readings[i].games == 0)
        null
      else
        () {
          var total = 0, games = 0;
          for (var j = i - window + 1; j <= i; j++) {
            if (j < 0) continue;
            total += readings[j].total;
            games += readings[j].games;
          }
          return total / games;
        }(),
  ];
}
