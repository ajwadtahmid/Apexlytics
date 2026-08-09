import '../../models/season_meta.dart';
import 'snapshot_types.dart';

class WeekRange {
  final DateTime start;
  final DateTime end;
  const WeekRange({required this.start, required this.end});
}

/// Sentinel season id for matches that fall outside every known season window.
/// `kUnknownSplitId` in `ranked_period.dart` is a direct alias of this constant
/// so the stored column and the picker's "Unknown" bucket always line up.
const String kUnknownSeasonId = '__unknown__';

/// The season/split id whose window contains [endTime], or [kUnknownSeasonId] when
/// no known season covers it. A match belongs to the season its *end* time falls
/// in — the same rule the ranked views use to bucket matches.
String seasonIdForEndTime(DateTime endTime, Iterable<SeasonMeta> seasons) {
  for (final s in seasons) {
    if (!endTime.isBefore(s.start) && endTime.isBefore(s.end)) return s.id;
  }
  return kUnknownSeasonId;
}

/// Divides a season into 7-day week windows. The final window may be shorter
/// if the season length is not a multiple of 7 days — no hardcoding needed.
List<WeekRange> computeWeeks(SeasonMeta season) {
  final weeks = <WeekRange>[];
  var cursor = season.start;
  while (cursor.isBefore(season.end)) {
    final next = cursor.add(const Duration(days: 7));
    weeks.add(WeekRange(
      start: cursor,
      end: next.isAfter(season.end) ? season.end : next,
    ));
    cursor = next;
  }
  return weeks;
}

/// Index of the week [DateTime.now()] falls in, or the last week if the season
/// has ended. Returns 0 if weeks is empty.
int currentWeekIndex(List<WeekRange> weeks, {DateTime? now}) {
  if (weeks.isEmpty) return 0;
  final at = now ?? DateTime.now();
  for (var i = 0; i < weeks.length; i++) {
    if (!at.isBefore(weeks[i].start) && at.isBefore(weeks[i].end)) return i;
  }
  // Season ended — default to last week.
  return weeks.length - 1;
}

/// Snapshots whose timestamp falls within [week].
List<StatSnapshot> snapshotsForWeek(
  List<StatSnapshot> all,
  WeekRange week,
) =>
    all
        .where((s) =>
            !s.timestamp.isBefore(week.start) &&
            s.timestamp.isBefore(week.end))
        .toList();

/// Timestamp just after a reset that landed inside [week], else null. A reset in
/// an earlier week needs no handling — the pre-week baseline is already
/// post-reset.
DateTime? _resetInsideWeek(
  List<StatSnapshot> all,
  WeekRange week,
  DateTime? splitStart,
) {
  final idx = lastResetIndex(all, splitStart: splitStart);
  if (idx == null) return null;
  final at = all[idx].timestamp;
  return (!at.isBefore(week.start) && at.isBefore(week.end)) ? at : null;
}

/// RP gained during [week].
///
/// Baseline = last snapshot before [week.start], or the first snapshot inside
/// the week if there is no prior data.
/// Top = [currentRp] when this is the live week (non-null), otherwise the last
/// snapshot inside the week.
/// Returns 0 for empty weeks, null when there is no data at all.
///
/// [scopeStart] is the owning split's start; candidates before it are ignored,
/// so week 1 is never measured against the previous split's final RP. A reset
/// landing inside [week] rebases as well — [scopeStart] alone can't catch that,
/// because the API's split start runs ahead of the actual reset.
///
/// Returns 0 rather than guess a baseline from a single in-week reading. A
/// pre-week baseline in the same split is trustworthy and used as normal.
int? weekDelta(
  List<StatSnapshot> rawAll,
  WeekRange week, {
  int? currentRp,
  DateTime? scopeStart,
}) {
  final all = trustedSnapshots(rawAll);

  final resetAt = _resetInsideWeek(all, week, scopeStart);
  final DateTime? floor;
  if (scopeStart == null) {
    floor = resetAt;
  } else if (resetAt == null) {
    floor = scopeStart;
  } else {
    floor = resetAt.isAfter(scopeStart) ? resetAt : scopeStart;
  }
  bool inScope(StatSnapshot s) =>
      floor == null || !s.timestamp.isBefore(floor);

  final before = all
      .where((s) => s.timestamp.isBefore(week.start) && inScope(s))
      .toList();
  final inWeek = snapshotsForWeek(all, week).where(inScope).toList();

  final int? baseline;
  if (before.isNotEmpty) {
    baseline = before.last.rp;
  } else if (inWeek.length >= 2) {
    baseline = inWeek.first.rp;
  } else if (inWeek.isNotEmpty) {
    return 0;
  } else {
    return null;
  }

  final now = DateTime.now();
  final isLiveWeek =
      !now.isBefore(week.start) && now.isBefore(week.end) && currentRp != null;
  final top = isLiveWeek
      ? currentRp
      : (inWeek.isNotEmpty ? inWeek.last.rp : null);

  // No in-week data and not the live week — a real zero delta, not "no data".
  if (top == null) return 0;
  return top - baseline;
}

/// The week [DateTime.now()] falls in for [season] (the last week once it has
/// ended), or null when there's no season to divide.
WeekRange? currentWeekRange(SeasonMeta? season) {
  if (season == null) return null;
  final weeks = computeWeeks(season);
  if (weeks.isEmpty) return null;
  return weeks[currentWeekIndex(weeks)];
}

/// Where the player sits inside a split, derived from the API's split bounds.
class SplitContext {
  /// 1-based, clamped to [totalWeeks] once the split has ended.
  final int week;
  final int totalWeeks;

  /// [Duration.zero] once the split has ended.
  final Duration remaining;

  const SplitContext({
    required this.week,
    required this.totalWeeks,
    required this.remaining,
  });

  bool get ended => remaining == Duration.zero;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitContext &&
          week == other.week &&
          totalWeeks == other.totalWeeks &&
          remaining == other.remaining;

  @override
  int get hashCode => Object.hash(week, totalWeeks, remaining);
}

/// [SplitContext] for [season], or null when there is no season to divide.
SplitContext? splitContext(SeasonMeta? season, {DateTime? now}) {
  if (season == null) return null;
  final weeks = computeWeeks(season);
  if (weeks.isEmpty) return null;
  final at = now ?? DateTime.now();
  return SplitContext(
    week: currentWeekIndex(weeks, now: at) + 1,
    totalWeeks: weeks.length,
    remaining: at.isBefore(season.end)
        ? season.end.difference(at)
        : Duration.zero,
  );
}

/// RP gained this week, considering the current season and snapshots.
///
/// If a ranked season exists, computes the delta for the current week within
/// that season. Otherwise falls back to a 24-hour delta.
///
/// [historyNetRp] is the same week from local match history, or null when it
/// can't cover the window. It wins when available — see
/// [RankedHistoryStore.netRpInWindow] for why that source is the reliable one.
int? computeWeekDelta(
  List<StatSnapshot> snaps,
  SeasonMeta? season,
  int currentRp, {
  int? historyNetRp,
}) {
  if (season != null) {
    final weeks = computeWeeks(season);
    if (weeks.isNotEmpty) {
      if (historyNetRp != null) return historyNetRp;
      final idx = currentWeekIndex(weeks);
      return weekDelta(
        snaps,
        weeks[idx],
        currentRp: currentRp,
        scopeStart: season.start,
      );
    }
  }
  return computeDelta(snaps, currentRp);
}
