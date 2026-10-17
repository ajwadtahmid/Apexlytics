import '../../constants/legend_constants.dart' show canonicalLegendName;
import 'ranked_aggregates.dart';

/// A list of sessions rolled up: how many, the averages, and the best and worst.
class SessionOverview {
  final int count;
  final double avgGames;
  final double avgNetRp;
  final Duration totalTime;

  /// The session that netted the most RP.
  final RankedSession best;

  /// The one that netted the least. Null with a single session, or when none did
  /// worse than [best], so a run of identical sessions has no "worst".
  final RankedSession? worst;

  const SessionOverview({
    required this.count,
    required this.avgGames,
    required this.avgNetRp,
    required this.totalTime,
    required this.best,
    required this.worst,
  });
}

/// The roll-up of [sessions] (any order), or null when there are none. Ties on
/// net RP go to the session with more games, then the more recent.
SessionOverview? sessionOverview(List<RankedSession> sessions) {
  if (sessions.isEmpty) return null;
  int byRp(RankedSession a, RankedSession b) {
    final c = a.netRp.compareTo(b.netRp);
    if (c != 0) return c;
    final g = a.games.compareTo(b.games);
    return g != 0 ? g : a.start.compareTo(b.start);
  }

  final best = sessions.reduce((a, b) => byRp(a, b) >= 0 ? a : b);
  final lowest = sessions.reduce((a, b) => byRp(a, b) <= 0 ? a : b);
  return SessionOverview(
    count: sessions.length,
    avgGames: sessions.fold(0, (n, s) => n + s.games) / sessions.length,
    avgNetRp: sessions.fold(0, (n, s) => n + s.netRp) / sessions.length,
    totalTime: sessions.fold(Duration.zero, (t, s) => t + s.duration),
    best: best,
    worst: sessions.length > 1 && lowest.netRp < best.netRp ? lowest : null,
  );
}

/// The RP each game of [session] moved, oldest first.
List<int> sessionGameRp(RankedSession session) => [
  for (final m in session.matches.reversed) m.effectiveRpChange,
];

/// The session's running RP after each game, oldest first, starting from 0.
List<int> sessionRpPath(RankedSession session) {
  var total = 0;
  return [0, for (final rp in sessionGameRp(session)) total += rp];
}

/// The deepest fall in a session's RP: from the highest point reached ([from])
/// to the lowest one after it ([to]), both indexes into the path from
/// [sessionRpPath], so games [from] + 1 through [to] caused it. [amount] is the
/// RP lost, always above zero.
typedef SessionDrop = ({int from, int to, int amount});

/// The biggest peak-to-trough fall in [path], or null when it never falls.
SessionDrop? biggestDrop(List<int> path) {
  SessionDrop? worst;
  var peak = 0;
  for (var i = 0; i < path.length; i++) {
    if (path[i] > path[peak]) peak = i;
    final fall = path[peak] - path[i];
    if (fall > (worst?.amount ?? 0)) {
      worst = (from: peak, to: i, amount: fall);
    }
  }
  return worst;
}

/// The biggest rise in a session's RP: from the lowest point reached ([from]) to
/// the highest one after it ([to]), as indexes into the same path, so games
/// [from] + 1 through [to] made it. [amount] is the RP gained, above zero.
typedef SessionGain = ({int from, int to, int amount});

/// The biggest low-to-high rise in [path], or null when it never rises.
SessionGain? biggestGain(List<int> path) {
  SessionGain? best;
  var trough = 0;
  for (var i = 0; i < path.length; i++) {
    if (path[i] < path[trough]) trough = i;
    final rise = path[i] - path[trough];
    if (rise > (best?.amount ?? 0)) {
      best = (from: trough, to: i, amount: rise);
    }
  }
  return best;
}

/// One legend's games in a session.
typedef LegendResult = ({String legend, int games, int netRp});

/// How each legend played in [session] did, the one that gained the most RP
/// first. Ties go to the legend with more games, then the name.
List<LegendResult> sessionLegendResults(RankedSession session) {
  final games = <String, int>{};
  final rp = <String, int>{};
  for (final m in session.matches) {
    final legend = canonicalLegendName(m.legend);
    games[legend] = (games[legend] ?? 0) + 1;
    rp[legend] = (rp[legend] ?? 0) + m.effectiveRpChange;
  }
  return [
    for (final legend in games.keys)
      (legend: legend, games: games[legend]!, netRp: rp[legend]!),
  ]..sort((a, b) {
    final byRp = b.netRp.compareTo(a.netRp);
    if (byRp != 0) return byRp;
    final byGames = b.games.compareTo(a.games);
    return byGames != 0 ? byGames : a.legend.compareTo(b.legend);
  });
}
