import 'ranked_aggregates.dart';

/// Where a legend sits on the pick rate chart: how much it is played against
/// how well it does.
enum PickRateQuadrant {
  core('Core'),
  trap('Comfort trap'),
  hiddenGem('Hidden gem'),
  bench('Bench');

  final String label;
  const PickRateQuadrant(this.label);
}

/// High pick rate (at/above [equalShareRate]) crossed with RP at/above
/// [rpBaseline]. An even-share pick-rate baseline means legends played roughly
/// equally sit together near the line instead of being torn apart by rank order
/// the way a sample median would — a median always cuts the pool in half
/// regardless of how close together the actual values are. [rpBaseline] is 0 by
/// default; a toggle lets it become the player's own scope average instead, so a
/// uniformly bad split doesn't paint every legend as a comfort trap.
PickRateQuadrant quadrantOf(
  double pickRate,
  double avgRp,
  double equalShareRate,
  double rpBaseline,
) {
  final highPick = pickRate >= equalShareRate;
  final positive = avgRp >= rpBaseline;
  if (highPick && positive) return PickRateQuadrant.core;
  if (highPick && !positive) return PickRateQuadrant.trap;
  if (!highPick && positive) return PickRateQuadrant.hiddenGem;
  return PickRateQuadrant.bench;
}

/// A legend worth pointing out above the chart.
typedef PickRateTakeaway = ({
  PickRateQuadrant quadrant,
  LegendBreakdown legend,
  double pickRate,
});

/// The comfort trap and the hidden gem of [pool], when there is one of each: the
/// most-played legend that does worse than [rpBaseline], and the best-performing
/// one that is played less than an even share. A legend needs at least
/// [kMinGamesForInsight] games to be named, so a handful of games never
/// decides. Empty when neither exists.
List<PickRateTakeaway> pickRateTakeaways({
  required List<LegendBreakdown> pool,
  required int totalGames,
  required double equalShareRate,
  required double rpBaseline,
}) {
  if (totalGames == 0) return const [];
  LegendBreakdown? trap;
  LegendBreakdown? gem;
  for (final l in pool) {
    if (l.games < kMinGamesForInsight) continue;
    switch (quadrantOf(
      l.games / totalGames,
      l.avgRpPerGame,
      equalShareRate,
      rpBaseline,
    )) {
      case PickRateQuadrant.trap:
        if (trap == null || _moreGames(l, trap)) trap = l;
      case PickRateQuadrant.hiddenGem:
        if (gem == null || _better(l, gem)) gem = l;
      case PickRateQuadrant.core || PickRateQuadrant.bench:
        break;
    }
  }
  return [
    if (trap != null)
      (
        quadrant: PickRateQuadrant.trap,
        legend: trap,
        pickRate: trap.games / totalGames,
      ),
    if (gem != null)
      (
        quadrant: PickRateQuadrant.hiddenGem,
        legend: gem,
        pickRate: gem.games / totalGames,
      ),
  ];
}

/// The legends the chart and table show: all of them, or only those with at
/// least [kMinGamesForInsight] games, whose averages are steady enough to read.
List<LegendBreakdown> pickRatePool(
  List<LegendBreakdown> legends, {
  required bool showAll,
}) => showAll
    ? legends
    : [
        for (final l in legends)
          if (l.games >= kMinGamesForInsight) l,
      ];

/// How many legends in [pool] would change quadrant if the RP line moved from
/// 0 to [ownAverage] (or back: the count is the same either way).
int legendsMovedByBaseline(
  List<LegendBreakdown> pool, {
  required int totalGames,
  required double equalShareRate,
  required double ownAverage,
}) {
  var moved = 0;
  for (final l in pool) {
    final rate = totalGames == 0 ? 0.0 : l.games / totalGames;
    if (quadrantOf(rate, l.avgRpPerGame, equalShareRate, 0) !=
        quadrantOf(rate, l.avgRpPerGame, equalShareRate, ownAverage)) {
      moved++;
    }
  }
  return moved;
}

/// The maps one legend does best and worst on, among those with at least
/// [kMinGamesForInsight] games. The worst is null unless two or more maps
/// qualify and it really is below the best. Ties go to the map with more games.
({LegendMapCell? best, LegendMapCell? worst}) legendBestWorstMap(
  List<LegendMapCell> cells,
) {
  final enough =
      [
        for (final c in cells)
          if (c.games >= kMinGamesForInsight) c,
      ]..sort((a, b) {
        final byRp = b.avgRpPerGame.compareTo(a.avgRpPerGame);
        return byRp != 0 ? byRp : b.games.compareTo(a.games);
      });
  if (enough.isEmpty) return (best: null, worst: null);
  final best = enough.first;
  // Several maps can share the lowest RP per game; the first of them in the
  // sorted order is the one with the most games.
  final lowest = enough.firstWhere(
    (c) => c.avgRpPerGame == enough.last.avgRpPerGame,
  );
  final worst = enough.length >= 2 && lowest.avgRpPerGame < best.avgRpPerGame
      ? lowest
      : null;
  return (best: best, worst: worst);
}

/// More games, then the name, so the pick doesn't depend on list order.
bool _moreGames(LegendBreakdown a, LegendBreakdown b) =>
    a.games != b.games ? a.games > b.games : a.legend.compareTo(b.legend) < 0;

/// Higher RP per game, then more games, then the name.
bool _better(LegendBreakdown a, LegendBreakdown b) {
  final c = a.avgRpPerGame.compareTo(b.avgRpPerGame);
  return c != 0 ? c > 0 : _moreGames(a, b);
}
