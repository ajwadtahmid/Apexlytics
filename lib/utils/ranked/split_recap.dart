import 'dart:math' as math;
import '../../models/ranked_match.dart';
import 'best_metric.dart';
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

  /// The best legend and map under the [BestMetric] the recap was built with,
  /// among those with at least [kMinGamesForInsight] games; null when none has
  /// played enough.
  final LegendBreakdown? bestLegend;
  final MapBreakdown? bestMap;

  /// What [bestLegend] and [bestMap] are best at, for the screen and the card
  /// to say.
  final BestMetric metric;

  /// The play session that gained the most RP.
  final RankedSession? bestSession;
  final int longestWinStreak;
  final int totalKills;

  /// Games whose kills upstream reported: with none, [totalKills] is unknown
  /// rather than zero.
  final int killsGames;

  /// Damage over the period, and the games that reported it, as for kills.
  final int totalDamage;
  final int damageGames;
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
    required this.metric,
    required this.bestSession,
    required this.longestWinStreak,
    required this.totalKills,
    required this.killsGames,
    required this.totalDamage,
    required this.damageGames,
    required this.playSecs,
  });

  bool get isEmpty => games == 0;

  /// Wins over wins plus losses, as a fraction; a game that moved no RP is
  /// neither. Null when there were none of either.
  double? get winRate => wins + losses == 0 ? null : wins / (wins + losses);

  /// RP gained per game over the period, 0 with no games.
  double get avgRpPerGame => games == 0 ? 0 : netRp / games;
}

SplitRecap splitRecap(
  List<RankedMatch> matches, {
  BestMetric metric = kDefaultBestMetric,
}) {
  final ranked = rankedOnly(matches);
  final summary = summarize(ranked);

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
    bestLegend: rankByMetric(
      legendBreakdowns(ranked),
      metric,
      nameOf: (l) => l.legend,
    ).firstOrNull,
    bestMap: rankByMetric(
      mapBreakdowns(ranked),
      metric,
      nameOf: (m) => m.displayName,
    ).firstOrNull,
    metric: metric,
    bestSession: sessions.firstOrNull,
    longestWinStreak: personalRecords(ranked).bestWinStreak,
    totalKills: summary.totalKills,
    killsGames: summary.killsGames,
    totalDamage: summary.totalDamage,
    damageGames: summary.damageGames,
    playSecs: summary.totalLengthSecs,
  );
}
