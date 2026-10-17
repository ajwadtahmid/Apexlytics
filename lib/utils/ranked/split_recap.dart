import 'dart:math' as math;
import '../../models/ranked_match.dart';
import 'ranked_aggregates.dart';

/// The headline numbers of a period of ranked play, for the recap screen and
/// its shareable card. Built only from games that count toward the stats.
class SplitRecap {
  final int games;
  final int wins;
  final int losses;
  final int netRp;

  /// The highest running RP reached, and the running RP after the last game.
  final int peakRp;
  final int finalRp;

  /// The rank badge URL of the last game, for the final tier.
  final String rankImg;

  /// Highest RP per game among legends and maps with at least
  /// [kMinGamesForInsight] games; null when none has played enough.
  final LegendBreakdown? bestLegend;
  final MapBreakdown? bestMap;

  /// The play session that gained the most RP.
  final RankedSession? bestSession;
  final int longestWinStreak;
  final int totalKills;
  final int playSecs;

  const SplitRecap({
    required this.games,
    required this.wins,
    required this.losses,
    required this.netRp,
    required this.peakRp,
    required this.finalRp,
    required this.rankImg,
    required this.bestLegend,
    required this.bestMap,
    required this.bestSession,
    required this.longestWinStreak,
    required this.totalKills,
    required this.playSecs,
  });

  bool get isEmpty => games == 0;
}

SplitRecap splitRecap(List<RankedMatch> matches) {
  final ranked = rankedOnly(matches);
  final summary = summarize(ranked);

  T? best<T>(Iterable<T> all, int Function(T) games, double Function(T) rate) {
    final eligible = all.where((e) => games(e) >= kMinGamesForInsight).toList()
      ..sort((a, b) => rate(b).compareTo(rate(a)));
    return eligible.firstOrNull;
  }

  final sessions = sessionize(ranked)
    ..sort((a, b) => b.netRp.compareTo(a.netRp));

  return SplitRecap(
    games: summary.games,
    wins: summary.wins,
    losses: summary.losses,
    netRp: summary.netRp,
    peakRp: ranked.isEmpty
        ? 0
        : ranked.map((m) => m.cumulativeRp).reduce(math.max),
    finalRp: summary.currentRp,
    rankImg: summary.latestRankImg,
    bestLegend: best(
      legendBreakdowns(ranked),
      (l) => l.games,
      (l) => l.avgRpPerGame,
    ),
    bestMap: best(mapBreakdowns(ranked), (m) => m.games, (m) => m.avgRpPerGame),
    bestSession: sessions.firstOrNull,
    longestWinStreak: personalRecords(ranked).bestWinStreak,
    totalKills: summary.totalKills,
    playSecs: summary.totalLengthSecs,
  );
}
