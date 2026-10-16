import '../../../constants/legend_constants.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/ranked/ranked_aggregates.dart' show kSessionGap, sessionNumbers;

/// How to bucket matches when not grouping by session. [keyOf] decides which
/// section a match belongs to; [nameOf] is that section's display title.
class MatchGrouping {
  final String Function(RankedMatch) keyOf;
  final String Function(RankedMatch) nameOf;
  const MatchGrouping({required this.keyOf, required this.nameOf});

  /// One section per map. Keyed canonically, like every aggregate: a match
  /// whose map was corrected by hand is stored as `olympus` where a synced one
  /// is `olympus_rotation`, and a raw key would split them into two sections
  /// with the same title.
  static final byMap = MatchGrouping(
    keyOf: (m) => canonicalMapKey(m.mapKey),
    nameOf: (m) => battleRoyaleMapName(m.mapKey),
  );

  /// One section per legend, keyed canonically for the same reason as [byMap].
  static final byLegend = MatchGrouping(
    keyOf: (m) => canonicalLegendName(m.legend),
    nameOf: (m) => canonicalLegendName(m.legend),
  );
}

// ── Item model ──────────────────────────────────────────────────────────────

sealed class HistoryItem {}

/// One play session: games separated from the next session by more than
/// [kSessionGap]. A session may cross midnight; its header shows the day it
/// started.
class SessionHeaderItem extends HistoryItem {
  /// Names this session in the collapsed set; stable as newer games arrive.
  final String key;

  /// First game's start and last game's end, over the games listed.
  final DateTime start;
  final DateTime end;
  final int netRp;
  final bool hasRanked;
  final int games;
  final bool isFirst;

  /// Decided ranked games (effective RP above / below zero) and the average RP
  /// over the ranked games played; null avg when the session had none.
  final int wins;
  final int losses;
  final double? avgRp;

  /// Totals over the session's counted games (excluded matches skipped, like
  /// every other stat rollup). Kills/damage skip games that didn't report them.
  final int kills;
  final int damage;

  /// Counted games that reported kills / damage; zero means "no reading", not
  /// a total of 0.
  final int killsGames;
  final int damageGames;
  final int playSecs;
  SessionHeaderItem({
    required this.key,
    required this.start,
    required this.end,
    required this.netRp,
    required this.hasRanked,
    required this.games,
    required this.isFirst,
    this.wins = 0,
    this.losses = 0,
    this.avgRp,
    this.kills = 0,
    this.damage = 0,
    this.killsGames = 0,
    this.damageGames = 0,
    this.playSecs = 0,
  });
}

/// Marks where the calendar day changes inside a session that runs past
/// midnight. The list is newest first, so [later] is the day of the rows above
/// the divider and [earlier] the day of the rows below it.
class DayDividerItem extends HistoryItem {
  final DateTime later;
  final DateTime earlier;
  DayDividerItem({required this.later, required this.earlier});
}

class GroupHeaderItem extends HistoryItem {
  final String name;
  final int games;
  final int netRp;

  /// Net RP per counted ranked game, as in a session header. Null if none count.
  final double? avgRp;
  final bool isFirst;
  GroupHeaderItem({
    required this.name,
    required this.games,
    required this.netRp,
    required this.avgRp,
    required this.isFirst,
  });
}

class SessionBreakItem extends HistoryItem {
  final int gapSecs;
  SessionBreakItem(this.gapSecs);
}

class MatchItem extends HistoryItem {
  final RankedMatch match;
  MatchItem(this.match);
}

/// Default (and incremental) number of matches shown in session-grouped
/// history before scrolling near the bottom loads the next page. Chosen so a
/// typical week's worth of games renders up front, while a multi-thousand-
/// match history stays cheap to flatten and lay out.
const int kHistoryPageSize = 50;

/// Which session each match belongs to, found over [pool] (newest first).
class _Sessions {
  final Map<String, int> indexOf = {};

  /// Per session, the id of its earliest game: a name that stays put as newer
  /// games join the session.
  final List<String> keys = [];

  _Sessions(List<RankedMatch> pool) {
    final numbers = sessionNumbers(pool);
    for (var i = 0; i < pool.length; i++) {
      if (numbers[i] == keys.length) {
        keys.add(pool[i].id);
      } else {
        keys[numbers[i]] = pool[i].id;
      }
      indexOf[pool[i].id] = numbers[i];
    }
  }

  int of(RankedMatch m) => indexOf[m.id] ?? -1;
}

/// Extends [limit] to the end of the session the cut lands in, so a session
/// header's totals cover all its games.
List<RankedMatch> _extendToSessionBoundary(
  List<RankedMatch> matches,
  int limit,
  _Sessions sessions,
) {
  if (limit >= matches.length) return matches;
  final session = sessions.of(matches[limit - 1]);
  var end = limit;
  while (end < matches.length && sessions.of(matches[end]) == session) {
    end++;
  }
  return matches.sublist(0, end);
}

DateTime _dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Flattens matches (newest first) into session headers with their rows, a
/// break row between sessions, and a day divider inside a session wherever it
/// crosses midnight.
///
/// Sessions are found over [sessionPool] (newest first; defaults to [matches]),
/// so a filtered list keeps the sessions the whole history has. When [limit] is
/// set, only the first [limit] matches are shown — extended to the end of the
/// session they land in, so a session's header totals are complete.
///
/// [includeBreaks] false hides break rows, for when [sessionPool] isn't the
/// whole history.
List<HistoryItem> buildSessionItems(
  List<RankedMatch> matches, {
  int? limit,
  List<RankedMatch>? sessionPool,
  bool includeBreaks = true,
}) {
  final sessions = _Sessions(sessionPool ?? matches);
  final visible = limit == null
      ? matches
      : _extendToSessionBoundary(matches, limit, sessions);

  final buckets = <List<RankedMatch>>[];
  int? current;
  for (final m in visible) {
    final s = sessions.of(m);
    if (current == null || s != current) {
      buckets.add(<RankedMatch>[]);
      current = s;
    }
    buckets.last.add(m);
  }

  final items = <HistoryItem>[];
  for (var b = 0; b < buckets.length; b++) {
    final bucket = buckets[b]; // newest first
    final start = bucket.last.startTime;
    final end = bucket.first.endTime;
    if (b > 0 && includeBreaks) {
      items.add(
        SessionBreakItem(
          buckets[b - 1].last.startTime.difference(end).inSeconds,
        ),
      );
    }

    final netRp = bucket.fold<int>(0, (a, m) => a + m.effectiveRpChange);
    final counted = bucket.where((m) => m.countsTowardStats).toList();
    final rankedGames = counted.where((m) => m.isRanked).length;
    final key = sessions.of(bucket.first);
    items.add(
      SessionHeaderItem(
        key: key < 0 ? bucket.last.id : sessions.keys[key],
        start: start,
        end: end,
        netRp: netRp,
        hasRanked: bucket.any((m) => m.isRanked),
        games: bucket.length,
        isFirst: b == 0,
        wins: counted.where((m) => m.effectiveRpChange > 0).length,
        losses: counted.where((m) => m.effectiveRpChange < 0).length,
        avgRp: rankedGames == 0 ? null : netRp / rankedGames,
        kills: counted.fold<int>(0, (a, m) => a + (m.kills ?? 0)),
        damage: counted.fold<int>(0, (a, m) => a + (m.damage ?? 0)),
        killsGames: counted.where((m) => m.kills != null).length,
        damageGames: counted.where((m) => m.damage != null).length,
        playSecs: counted.fold<int>(0, (a, m) => a + m.lengthSecs),
      ),
    );
    for (var i = 0; i < bucket.length; i++) {
      if (i > 0) {
        // newest-first: bucket[i - 1] is later than bucket[i].
        final later = _dayOf(bucket[i - 1].startTime);
        final earlier = _dayOf(bucket[i].startTime);
        if (later != earlier) {
          items.add(DayDividerItem(later: later, earlier: earlier));
        }
      }
      items.add(MatchItem(bucket[i]));
    }
  }
  return items;
}

/// Sections matches by [g], ordered by net (effective) RP descending, with
/// matches newest-first inside each section. No session breaks in this mode.
List<HistoryItem> buildGroupedItems(
  List<RankedMatch> matches,
  MatchGrouping g,
) {
  final byKey = <String, List<RankedMatch>>{};
  for (final m in matches) {
    byKey.putIfAbsent(g.keyOf(m), () => []).add(m);
  }

  final groups = byKey.values.map((ms) {
    final sorted = ms.toList()..sort((a, b) => b.endTime.compareTo(a.endTime));
    final netRp = sorted.fold<int>(0, (a, m) => a + m.effectiveRpChange);
    final rankedGames = sorted
        .where((m) => m.countsTowardStats && m.isRanked)
        .length;
    return (
      name: g.nameOf(sorted.first),
      matches: sorted,
      netRp: netRp,
      avgRp: rankedGames == 0 ? null : netRp / rankedGames,
    );
  }).toList()..sort((a, b) => b.netRp.compareTo(a.netRp));

  final items = <HistoryItem>[];
  for (final grp in groups) {
    items.add(
      GroupHeaderItem(
        name: grp.name,
        games: grp.matches.length,
        netRp: grp.netRp,
        avgRp: grp.avgRp,
        isFirst: identical(grp, groups.first),
      ),
    );
    for (final m in grp.matches) {
      items.add(MatchItem(m));
    }
  }
  return items;
}
