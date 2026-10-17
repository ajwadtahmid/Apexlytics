import 'ranked_aggregates.dart';

/// A column the Pick Rate table can be ordered by.
enum LegendSort {
  legend,
  pick,
  win,
  rpPerGame,
  netRp,
  kills,
  damage;

  /// Whether tapping the header first puts the biggest value on top. Names read
  /// A to Z first.
  bool get startsDescending => this != legend;
}

/// [legends] ordered by [sort]. A legend with no kills or damage reading goes
/// last in either direction, since "no reading" is neither the most nor the
/// least. Ties go to the more played legend, then the name, so the order never
/// depends on the list it came in.
List<LegendBreakdown> sortLegends(
  List<LegendBreakdown> legends,
  LegendSort sort, {
  required bool descending,
}) {
  num? valueOf(LegendBreakdown l) => switch (sort) {
    LegendSort.legend => null,
    LegendSort.pick => l.games,
    LegendSort.win => l.winRate,
    LegendSort.rpPerGame => l.avgRpPerGame,
    LegendSort.netRp => l.totalRp,
    LegendSort.kills => l.avgKills,
    LegendSort.damage => l.avgDamage,
  };

  int byName(LegendBreakdown a, LegendBreakdown b) =>
      a.legend.compareTo(b.legend);
  int tieBreak(LegendBreakdown a, LegendBreakdown b) =>
      a.games != b.games ? b.games.compareTo(a.games) : byName(a, b);

  return [...legends]..sort((a, b) {
    if (sort == LegendSort.legend) {
      return descending ? byName(b, a) : byName(a, b);
    }
    final x = valueOf(a);
    final y = valueOf(b);
    if (x == null || y == null) {
      if (x == y) return tieBreak(a, b);
      return x == null ? 1 : -1;
    }
    final c = descending ? y.compareTo(x) : x.compareTo(y);
    return c != 0 ? c : tieBreak(a, b);
  });
}
