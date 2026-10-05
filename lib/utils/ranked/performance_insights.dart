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

/// Best and toughest day of the week and part of the day, by average RP per
/// game. A slot needs at least [minGames] games to count, and a pair is only
/// reported when the two differ by at least [minGap] RP per game — otherwise
/// there is no real pattern to point at.
List<PlayInsight> playTimeInsights({
  required List<HourBucket> hourBuckets,
  required List<WeekdayBucket> weekdayBuckets,
  int minGames = 10,
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
