import '../formatting/format.dart'
    show formatNumber, formatPercent, formatSigned, formatSignedInt;
import 'ranked_tally.dart';

/// What makes one legend or map better than another. The order is the one the
/// picker lists them in.
enum BestMetric {
  totalRp('Total RP', 'total RP'),
  avgRp('Avg RP', 'avg RP'),
  winRate('Win rate', 'win rate'),
  avgKills('Avg Kills', 'avg kills'),
  totalKills('Total Kills', 'total kills'),
  avgDamage('Avg Damage', 'avg damage'),
  totalDamage('Total Damage', 'total damage');

  const BestMetric(this.label, this.phrase);

  /// How the picker and its pill name it.
  final String label;

  /// The same, to read inside a sentence or after a title ("Best legend and
  /// map by total RP").
  final String phrase;

  /// Whether the figure can be negative, and so reads as a gain or a loss.
  /// Kills, damage and win rate can't be, so they are not coloured as one.
  bool get isRp => this == avgRp || this == totalRp;

  /// [value] (as [valueOf] gives it) written for a pill: `+80.1 /game`,
  /// `+561 RP`, `2.8 kills/game`, `1,204 kills`, `521 dmg/game`, `23,760 dmg`,
  /// `62% win rate`.
  String formatValue(double value) => switch (this) {
    avgRp => '${formatSigned(value)} /game',
    totalRp => '${formatSignedInt(value.round())} RP',
    avgKills => '${value.toStringAsFixed(1)} kills/game',
    totalKills => '${formatNumber(value.round())} kills',
    avgDamage => '${formatNumber(value.round())} dmg/game',
    totalDamage => '${formatNumber(value.round())} dmg',
    winRate => '${formatPercent(value, decimals: 0)} win rate',
  };

  /// [formatValue] for a line of text, where a bare "/game" would not say what
  /// is being averaged.
  String formatInline(double value) =>
      this == avgRp ? '${formatSigned(value)} RP/game' : formatValue(value);

  /// [tally]'s figure under this measure, or null when it has none to give:
  /// no games, no game that reported kills or damage (not the same as a
  /// reported 0), or no game that moved RP either way for a win rate.
  double? valueOf(RankedTally tally) {
    if (tally.games == 0) return null;
    final decided = tally.wins + tally.losses;
    return switch (this) {
      avgRp => tally.avgRpPerGame,
      totalRp => tally.totalRp.toDouble(),
      avgKills => tally.avgKills,
      totalKills => tally.killsGames == 0 ? null : tally.totalKills.toDouble(),
      avgDamage => tally.avgDamage,
      totalDamage =>
        tally.damageGames == 0 ? null : tally.totalDamage.toDouble(),
      winRate => decided == 0 ? null : tally.wins / decided,
    };
  }
}

/// What "best" means until the player chooses.
const kDefaultBestMetric = BestMetric.totalRp;

/// [items] that have a figure under [metric], best first. Ties go to the one
/// with more games, then to the name [nameOf] gives, so the order never depends
/// on the order they came in.
///
/// Only items with at least [kMinGamesForInsight] games are ranked, so one
/// lucky game can't crown anything. With [softGate], when none has that many
/// the rest are ranked instead of nothing.
List<T> rankByMetric<T extends RankedTally>(
  Iterable<T> items,
  BestMetric metric, {
  required String Function(T) nameOf,
  bool softGate = false,
}) {
  final valued = [
    for (final item in items)
      if (metric.valueOf(item) case final value?) (item: item, value: value),
  ];
  final enough = [
    for (final v in valued)
      if (v.item.games >= kMinGamesForInsight) v,
  ];
  final pool = enough.isEmpty && softGate ? valued : enough;
  pool.sort((a, b) {
    final byValue = b.value.compareTo(a.value);
    if (byValue != 0) return byValue;
    final byGames = b.item.games.compareTo(a.item.games);
    return byGames != 0 ? byGames : nameOf(a.item).compareTo(nameOf(b.item));
  });
  return [for (final v in pool) v.item];
}

/// The first and the weakest of [ranked] (as [rankByMetric] returns it). The
/// weakest is null unless there are two or more and it really is below the
/// best; of several equally weak, it is the one with the most games.
({T? best, T? worst}) bestAndWorst<T extends RankedTally>(
  List<T> ranked,
  BestMetric metric,
) {
  if (ranked.isEmpty) return (best: null, worst: null);
  final best = ranked.first;
  if (ranked.length < 2) return (best: best, worst: null);
  final lowest = metric.valueOf(ranked.last)!;
  if (lowest >= metric.valueOf(best)!) return (best: best, worst: null);
  return (
    best: best,
    worst: ranked.firstWhere((t) => metric.valueOf(t) == lowest),
  );
}

/// [items] ordered by [metric], biggest first, for a list the player is
/// sorting. Unlike [rankByMetric] nothing is left out for having few games; an
/// item with no figure (no kills reported, say) goes last. Ties go to the one
/// with more games, then to the name [nameOf] gives.
List<T> sortByMetric<T extends RankedTally>(
  Iterable<T> items,
  BestMetric metric, {
  required String Function(T) nameOf,
}) {
  final valued = [
    for (final item in items) (item: item, value: metric.valueOf(item)),
  ];
  valued.sort((a, b) {
    final x = a.value;
    final y = b.value;
    if (x == null || y == null) {
      if (x == y) return _byGamesThenName(a.item, b.item, nameOf);
      return x == null ? 1 : -1;
    }
    final byValue = y.compareTo(x);
    return byValue != 0 ? byValue : _byGamesThenName(a.item, b.item, nameOf);
  });
  return [for (final v in valued) v.item];
}

int _byGamesThenName<T extends RankedTally>(
  T a,
  T b,
  String Function(T) nameOf,
) {
  final byGames = b.games.compareTo(a.games);
  return byGames != 0 ? byGames : nameOf(a).compareTo(nameOf(b));
}
