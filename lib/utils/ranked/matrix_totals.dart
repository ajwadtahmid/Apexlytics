import 'ranked_aggregates.dart';

/// The name a total cell carries in place of a legend or a map, so a tap on it
/// can tell which side it adds up.
const kMatrixAll = 'All';

/// How the Legend × Map grid orders its rows and columns.
enum MatrixSort {
  mostPlayed('Most played'),
  bestRp('Best RP'),
  alphabetical('A–Z');

  final String label;
  const MatrixSort(this.label);
}

/// Each legend's and each map's figures added up over the grid's cells.
class MatrixTotals {
  /// Per legend across every map; [LegendMapCell.mapName] is [kMatrixAll].
  final Map<String, LegendMapCell> byLegend;

  /// Per map across every legend; [LegendMapCell.legend] is [kMatrixAll].
  final Map<String, LegendMapCell> byMap;

  /// Everything in the grid.
  final LegendMapCell grand;

  const MatrixTotals({
    required this.byLegend,
    required this.byMap,
    required this.grand,
  });
}

/// The row, column and overall totals of [cells]. They add up exactly the games
/// the grid shows, so a legend's total is its row and a map's total its column.
MatrixTotals matrixTotals(List<LegendMapCell> cells) {
  final legendGames = <String, int>{};
  final legendRp = <String, int>{};
  final mapGames = <String, int>{};
  final mapRp = <String, int>{};
  var games = 0;
  var rp = 0;
  for (final c in cells) {
    legendGames[c.legend] = (legendGames[c.legend] ?? 0) + c.games;
    legendRp[c.legend] = (legendRp[c.legend] ?? 0) + c.totalRp;
    mapGames[c.mapName] = (mapGames[c.mapName] ?? 0) + c.games;
    mapRp[c.mapName] = (mapRp[c.mapName] ?? 0) + c.totalRp;
    games += c.games;
    rp += c.totalRp;
  }
  return MatrixTotals(
    byLegend: {
      for (final l in legendGames.keys)
        l: LegendMapCell(
          legend: l,
          mapName: kMatrixAll,
          games: legendGames[l]!,
          totalRp: legendRp[l]!,
        ),
    },
    byMap: {
      for (final m in mapGames.keys)
        m: LegendMapCell(
          legend: kMatrixAll,
          mapName: m,
          games: mapGames[m]!,
          totalRp: mapRp[m]!,
        ),
    },
    grand: LegendMapCell(
      legend: kMatrixAll,
      mapName: kMatrixAll,
      games: games,
      totalRp: rp,
    ),
  );
}

/// The legends (or maps) in [totals], keyed by name, in the order of [sort].
///
/// Best RP puts those with at least [kMinGamesForInsight] games first, best
/// first, so one lucky game can't top the list; the rest follow, most played
/// first. Ties go to the more played, then the name.
List<String> orderedMatrixNames(
  Map<String, LegendMapCell> totals,
  MatrixSort sort,
) {
  int byGames(String a, String b) {
    final c = totals[b]!.games.compareTo(totals[a]!.games);
    return c != 0 ? c : a.compareTo(b);
  }

  int byBestRp(String a, String b) {
    final x = totals[a]!;
    final y = totals[b]!;
    final xEnough = x.games >= kMinGamesForInsight;
    final yEnough = y.games >= kMinGamesForInsight;
    if (xEnough != yEnough) return xEnough ? -1 : 1;
    if (!xEnough) return byGames(a, b);
    final c = y.avgRpPerGame.compareTo(x.avgRpPerGame);
    return c != 0 ? c : byGames(a, b);
  }

  return totals.keys.toList()..sort(switch (sort) {
    MatrixSort.mostPlayed => byGames,
    MatrixSort.bestRp => byBestRp,
    MatrixSort.alphabetical => (a, b) => a.compareTo(b),
  });
}
