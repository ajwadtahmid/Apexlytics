import 'dart:math' as math;
import '../../constants/legend_constants.dart' show canonicalLegendName;
import '../../models/ranked_match.dart';
import 'ranked_aggregates.dart';
import 'session_overview.dart';

/// The best calendar day: the games played on it, newest first, and the RP they
/// netted.
typedef DayRecord = ({DateTime day, int netRp, List<RankedMatch> matches});

/// The local calendar day that netted the most RP, by the day each game ended.
/// [matches] should already be the ranked games that count toward the stats.
/// Ties go to the day with more games, then the later one. Null with no games.
DayRecord? bestDay(List<RankedMatch> matches) {
  final byDay = <DateTime, List<RankedMatch>>{};
  for (final m in matches) {
    final end = m.endTime.toLocal();
    (byDay[DateTime(end.year, end.month, end.day)] ??= []).add(m);
  }
  DayRecord? best;
  for (final e in byDay.entries) {
    final net = e.value.fold<int>(0, (a, m) => a + m.effectiveRpChange);
    final better =
        best == null ||
        net > best.netRp ||
        (net == best.netRp &&
            (e.value.length > best.matches.length ||
                (e.value.length == best.matches.length &&
                    e.key.isAfter(best.day))));
    if (better) {
      best = (
        day: e.key,
        netRp: net,
        matches: [...e.value]..sort((a, b) => b.endTime.compareTo(a.endTime)),
      );
    }
  }
  return best;
}

/// Whether [day] is made up of exactly the games of [session], so that showing
/// both would say the same thing twice. False when there is no session.
bool dayIsSession(DayRecord day, RankedSession? session) {
  if (session == null || session.matches.length != day.matches.length) {
    return false;
  }
  final ids = {for (final m in session.matches) m.id};
  return day.matches.every((m) => ids.contains(m.id));
}

/// The session that lasted longest, first game's start to last game's end. Ties
/// go to the one with more games, then the more recent. Null with no sessions.
RankedSession? longestSession(List<RankedSession> sessions) {
  RankedSession? best;
  for (final s in sessions) {
    final better =
        best == null ||
        s.duration > best.duration ||
        (s.duration == best.duration &&
            (s.games > best.games ||
                (s.games == best.games && s.start.isAfter(best.start))));
    if (better) best = s;
  }
  return best;
}

/// A session that fell below where it started and finished above it: its
/// lowest point ([low], at most -1), where it ended ([net], at least 1) and the
/// climb between them ([recovered]).
typedef Comeback = ({RankedSession session, int low, int net, int recovered});

/// The session with the biggest climb from its lowest point to its end, among
/// those that started by losing RP and still finished ahead. Ties go to the one
/// with more games, then the more recent. Null when no session did both.
Comeback? biggestComeback(List<RankedSession> sessions) {
  Comeback? best;
  for (final s in sessions) {
    final path = sessionRpPath(s);
    final low = path.reduce(math.min);
    final net = path.last;
    if (low >= 0 || net <= 0) continue;
    final recovered = net - low;
    final better =
        best == null ||
        recovered > best.recovered ||
        (recovered == best.recovered &&
            (s.games > best.session.games ||
                (s.games == best.session.games &&
                    s.start.isAfter(best.session.start))));
    if (better) {
      best = (session: s, low: low, net: net, recovered: recovered);
    }
  }
  return best;
}

/// The legend that earned the most RP across [matches], for a card's portrait.
/// Ties go to the one with more games, then the name. Null with no games.
String? topLegendByRp(List<RankedMatch> matches) {
  if (matches.isEmpty) return null;
  final rp = <String, int>{};
  final games = <String, int>{};
  for (final m in matches) {
    final name = canonicalLegendName(m.legend);
    rp[name] = (rp[name] ?? 0) + m.effectiveRpChange;
    games[name] = (games[name] ?? 0) + 1;
  }
  final names = rp.keys.toList()
    ..sort((a, b) {
      final byRp = rp[b]!.compareTo(rp[a]!);
      if (byRp != 0) return byRp;
      final byGames = games[b]!.compareTo(games[a]!);
      return byGames != 0 ? byGames : a.compareTo(b);
    });
  return names.first;
}
