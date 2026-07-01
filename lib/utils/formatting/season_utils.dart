import '../../models/season_meta.dart';
import 'snapshot_types.dart';

class WeekRange {
  final DateTime start;
  final DateTime end;
  const WeekRange({required this.start, required this.end});
}

/// Sentinel season id for matches that fall outside every known season window.
/// Must match `kOtherSplitId` in `ranked_period.dart` so the stored column and
/// the picker's "Other" bucket line up.
const String kOtherSeasonId = '__other__';

/// The season/split id whose window contains [endTime], or [kOtherSeasonId] when
/// no known season covers it. A match belongs to the season its *end* time falls
/// in — the same rule the ranked views use to bucket matches.
String seasonIdForEndTime(DateTime endTime, Iterable<SeasonMeta> seasons) {
  for (final s in seasons) {
    if (!endTime.isBefore(s.start) && endTime.isBefore(s.end)) return s.id;
  }
  return kOtherSeasonId;
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
int currentWeekIndex(List<WeekRange> weeks) {
  if (weeks.isEmpty) return 0;
  final now = DateTime.now();
  for (var i = 0; i < weeks.length; i++) {
    if (!now.isBefore(weeks[i].start) && now.isBefore(weeks[i].end)) return i;
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

/// RP gained during [week].
///
/// Baseline = last snapshot before [week.start], or the first snapshot inside
/// the week if there is no prior data.
/// Top = [currentRp] when this is the live week (non-null), otherwise the last
/// snapshot inside the week.
/// Returns 0 for empty weeks, null when there is no data at all.
int? weekDelta(
  List<StatSnapshot> all,
  WeekRange week, {
  int? currentRp,
}) {
  final before = all.where((s) => s.timestamp.isBefore(week.start)).toList();
  final inWeek = snapshotsForWeek(all, week);

  final int? baseline;
  if (before.isNotEmpty) {
    baseline = before.last.rp;
  } else if (inWeek.isNotEmpty) {
    baseline = inWeek.first.rp;
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

/// RP gained this week, considering the current season and snapshots.
///
/// If a ranked season exists, computes the delta for the current week within
/// that season. Otherwise falls back to a 24-hour delta.
int? computeWeekDelta(
  List<StatSnapshot> snaps,
  SeasonMeta? season,
  int currentRp,
) {
  if (season != null) {
    final weeks = computeWeeks(season);
    if (weeks.isNotEmpty) {
      final idx = currentWeekIndex(weeks);
      return weekDelta(snaps, weeks[idx], currentRp: currentRp);
    }
  }
  return computeDelta(snaps, currentRp);
}
