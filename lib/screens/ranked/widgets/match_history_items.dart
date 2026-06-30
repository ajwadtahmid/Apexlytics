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
  DayHeaderItem(
      {required this.day,
      required this.netRp,
      required this.hasRanked,
      required this.games,
      required this.isFirst});
}

class GroupHeaderItem extends HistoryItem {
  final String name;
  final int games;
  final int netRp;
  final bool isFirst;
  GroupHeaderItem(
      {required this.name,
      required this.games,
      required this.netRp,
      required this.isFirst});
}

class SessionBreakItem extends HistoryItem {
  final int gapSecs;
  SessionBreakItem(this.gapSecs);
}

class MatchItem extends HistoryItem {
  final RankedMatch match;
  MatchItem(this.match);
}

/// Flattens matches (newest first) into day headers, session breaks and rows.
List<HistoryItem> buildDayItems(List<RankedMatch> matches) {
  final items = <HistoryItem>[];
  DateTime? curDay;
  final dayBuckets = <List<RankedMatch>>[];
  for (final m in matches) {
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
    items.add(DayHeaderItem(
      day: DateTime(day.year, day.month, day.day),
      netRp: netRp,
      hasRanked: hasRanked,
      games: bucket.length,
      isFirst: identical(bucket, dayBuckets.first),
    ));
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
List<HistoryItem> buildGroupedItems(List<RankedMatch> matches, MatchGrouping g) {
  final byKey = <String, List<RankedMatch>>{};
  for (final m in matches) {
    byKey.putIfAbsent(g.keyOf(m), () => []).add(m);
  }

  final groups = byKey.values.map((ms) {
    final sorted = ms.toList()..sort((a, b) => b.endTime.compareTo(a.endTime));
    final netRp = sorted.fold<int>(0, (a, m) => a + m.effectiveRpChange);
    return (name: g.nameOf(sorted.first), matches: sorted, netRp: netRp);
  }).toList()
    ..sort((a, b) => b.netRp.compareTo(a.netRp));

  final items = <HistoryItem>[];
  for (final grp in groups) {
    items.add(GroupHeaderItem(
      name: grp.name,
      games: grp.matches.length,
      netRp: grp.netRp,
      isFirst: identical(grp, groups.first),
    ));
    for (final m in grp.matches) {
      items.add(MatchItem(m));
    }
  }
  return items;
}
