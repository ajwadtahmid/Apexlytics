import '../../../models/ranked_match.dart';
import '../../../utils/ranked/ranked_aggregates.dart' show kSessionGap;

/// How to bucket matches when not grouping by day. [keyOf] decides which
/// section a match belongs to; [nameOf] is that section's display title.
class MatchGrouping {
  final String Function(RankedMatch) keyOf;
  final String Function(RankedMatch) nameOf;
  const MatchGrouping({required this.keyOf, required this.nameOf});
}

// ── Item model ──────────────────────────────────────────────────────────────

sealed class HistoryItem {}

class DayHeaderItem extends HistoryItem {
  final DateTime day;
  final int netRp;
  final bool hasRanked;
  final int games;
  final bool isFirst;

  /// Decided ranked games (effective RP above / below zero) and the average RP
  /// over the ranked games played; null avg when the day had none.
  final int wins;
  final int losses;
  final double? avgRp;

  /// Totals over the day's counted games (excluded matches skipped, like every
  /// other stat rollup). Kills/damage skip games that didn't report them.
  final int kills;
  final int damage;
  final int playSecs;

  /// Average damage over the counted games that reported it; null when none did.
  final double? avgDamage;
  DayHeaderItem({
    required this.day,
    required this.netRp,
    required this.hasRanked,
    required this.games,
    required this.isFirst,
    this.wins = 0,
    this.losses = 0,
    this.avgRp,
    this.kills = 0,
    this.damage = 0,
    this.playSecs = 0,
    this.avgDamage,
  });
}

class GroupHeaderItem extends HistoryItem {
  final String name;
  final int games;
  final int netRp;
  final bool isFirst;
  GroupHeaderItem({
    required this.name,
    required this.games,
    required this.netRp,
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

/// Default (and incremental) number of matches shown in day-grouped history
/// before scrolling near the bottom loads the next page. Chosen so a typical
/// week/session's worth of games renders up front, while a multi-thousand-
/// match history stays cheap to flatten and lay out.
const int kHistoryPageSize = 50;

/// The local calendar day [m] is listed under (as in [buildDayItems]).
DateTime _dayOf(RankedMatch m) {
  final lm = m.endTime.toLocal();
  return DateTime(lm.year, lm.month, lm.day);
}

/// Extends [limit] to the end of the day the cut lands in, so a day header's totals cover
/// all its games. Session breaks only sit within a day, so none is split either.
List<RankedMatch> _extendToDayBoundary(List<RankedMatch> matches, int limit) {
  if (limit >= matches.length) return matches;
  final day = _dayOf(matches[limit - 1]);
  var end = limit;
  while (end < matches.length && _dayOf(matches[end]) == day) {
    end++;
  }
  return matches.sublist(0, end);
}

/// Flattens matches (newest first) into day headers, session breaks and rows.
///
/// When [limit] is set, only the first [limit] matches are shown — extended to
/// the end of whatever day they land in, so a day's header totals are complete.
List<HistoryItem> buildDayItems(List<RankedMatch> matches, {int? limit}) {
  final visible = limit == null
      ? matches
      : _extendToDayBoundary(matches, limit);
  final items = <HistoryItem>[];
  DateTime? curDay;
  final dayBuckets = <List<RankedMatch>>[];
  for (final m in visible) {
    final lm = m.endTime.toLocal();
    final day = DateTime(lm.year, lm.month, lm.day);
    if (curDay == null || day != curDay) {
      dayBuckets.add(<RankedMatch>[]);
      curDay = day;
    }
    dayBuckets.last.add(m);
  }

  for (final bucket in dayBuckets) {
    final netRp = bucket.fold<int>(0, (a, m) => a + m.effectiveRpChange);
    final hasRanked = bucket.any((m) => m.isRanked);
    final day = bucket.first.endTime.toLocal();
    final counted = bucket.where((m) => m.countsTowardStats).toList();
    final rankedGames = counted.where((m) => m.isRanked).length;
    items.add(
      DayHeaderItem(
        day: DateTime(day.year, day.month, day.day),
        netRp: netRp,
        hasRanked: hasRanked,
        games: bucket.length,
        isFirst: identical(bucket, dayBuckets.first),
        wins: counted.where((m) => m.effectiveRpChange > 0).length,
        losses: counted.where((m) => m.effectiveRpChange < 0).length,
        avgRp: rankedGames == 0 ? null : netRp / rankedGames,
        kills: counted.fold<int>(0, (a, m) => a + (m.kills ?? 0)),
        damage: counted.fold<int>(0, (a, m) => a + (m.damage ?? 0)),
        playSecs: counted.fold<int>(0, (a, m) => a + m.lengthSecs),
        avgDamage: counted.any((m) => m.damage != null)
            ? counted.fold<int>(0, (a, m) => a + (m.damage ?? 0)) /
                  counted.where((m) => m.damage != null).length
            : null,
      ),
    );
    for (var i = 0; i < bucket.length; i++) {
      if (i > 0) {
        // newest-first: bucket[i-1] is later than bucket[i].
        final gap = bucket[i - 1].startTime.difference(bucket[i].endTime);
        if (gap > kSessionGap) {
          items.add(SessionBreakItem(gap.inSeconds));
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
    return (name: g.nameOf(sorted.first), matches: sorted, netRp: netRp);
  }).toList()..sort((a, b) => b.netRp.compareTo(a.netRp));

  final items = <HistoryItem>[];
  for (final grp in groups) {
    items.add(
      GroupHeaderItem(
        name: grp.name,
        games: grp.matches.length,
        netRp: grp.netRp,
        isFirst: identical(grp, groups.first),
      ),
    );
    for (final m in grp.matches) {
      items.add(MatchItem(m));
    }
  }
  return items;
}
