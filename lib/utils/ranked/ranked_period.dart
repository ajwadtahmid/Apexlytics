/// Pure logic for slicing ranked history by split → week.
///
/// A `SeasonMeta` in this app already represents a season *split* (id
/// `br_ranked_s29_s1` → "S29 Split 1"), and `computeWeeks` divides one into
/// 7-day weeks. Each match is placed into a split by its end timestamp; matches
/// outside every known split fall into a single "Other" bucket.
library;

import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../formatting/season_utils.dart';

/// Catch-all bucket id for matches whose split metadata isn't known.
const kOtherSplitId = '__other__';

class RankedSplitBucket {
  final String id; // SeasonMeta.id, or [kOtherSplitId]
  final String displayName; // "S29 Split 1" or "Other"
  final SeasonMeta? season; // null for the "Other" bucket

  const RankedSplitBucket({
    required this.id,
    required this.displayName,
    this.season,
  });
}

SeasonMeta? _seasonFor(RankedMatch m, Iterable<SeasonMeta> seasons) {
  for (final s in seasons) {
    if (!m.endTime.isBefore(s.start) && m.endTime.isBefore(s.end)) return s;
  }
  return null;
}

/// Splits (with at least one ranked match) newest-first, plus an "Other" bucket
/// appended last if any match falls outside every known split.
List<RankedSplitBucket> splitBuckets(
  List<RankedMatch> matches,
  Map<String, SeasonMeta> seasons,
) {
  final withSeason = <String, SeasonMeta>{};
  final newest = <String, DateTime>{};
  var hasOther = false;

  for (final m in matches.where((m) => m.isRanked)) {
    final s = _seasonFor(m, seasons.values);
    final id = s?.id ?? kOtherSplitId;
    if (s != null) {
      withSeason[id] = s;
    } else {
      hasOther = true;
    }
    final cur = newest[id];
    if (cur == null || m.endTime.isAfter(cur)) newest[id] = m.endTime;
  }

  final buckets = withSeason.entries
      .map((e) => RankedSplitBucket(
            id: e.key,
            displayName: e.value.displayName,
            season: e.value,
          ))
      .toList()
    ..sort((a, b) => newest[b.id]!.compareTo(newest[a.id]!));

  if (hasOther) {
    buckets.add(const RankedSplitBucket(id: kOtherSplitId, displayName: 'Other'));
  }
  return buckets;
}

/// Matches belonging to [bucket]'s split window. With [rankedOnly] (default)
/// only ranked matches are returned (for aggregates); pass false to include
/// pubs and every other match in the window (for the History tab).
List<RankedMatch> matchesInSplit(
  List<RankedMatch> matches,
  RankedSplitBucket bucket,
  Map<String, SeasonMeta> seasons, {
  bool rankedOnly = true,
}) {
  final pool = rankedOnly ? matches.where((m) => m.isRanked) : matches;
  if (bucket.season == null) {
    return pool.where((m) => _seasonFor(m, seasons.values) == null).toList();
  }
  final s = bucket.season!;
  return pool
      .where((m) => !m.endTime.isBefore(s.start) && m.endTime.isBefore(s.end))
      .toList();
}

List<RankedMatch> matchesInWeek(List<RankedMatch> matches, WeekRange week) =>
    matches
        .where((m) =>
            !m.endTime.isBefore(week.start) && m.endTime.isBefore(week.end))
        .toList();

/// Resolved view of the ranked period: which splits are available, the
/// effective split/week selection (defaulting to the current split, all weeks),
/// and the matches that selection yields.
class RankedView {
  final List<RankedSplitBucket> splits;
  final String effectiveSplitId;
  final List<WeekRange> weeks;
  final int weekIndex; // -1 = All weeks
  final List<RankedMatch> filtered; // ranked only — drives the aggregates
  final List<RankedMatch> history; // all matches in the period — History tab

  const RankedView({
    required this.splits,
    required this.effectiveSplitId,
    required this.weeks,
    required this.weekIndex,
    required this.filtered,
    required this.history,
  });

  bool get isEmpty => splits.isEmpty;

  static const empty = RankedView(
    splits: [],
    effectiveSplitId: '',
    weeks: [],
    weekIndex: -1,
    filtered: [],
    history: [],
  );
}

/// Resolves the [RankedView] for a [splitId]/[weekIndex] selection. An invalid
/// or null split defaults to the newest (current) split; an out-of-range week
/// defaults to All.
RankedView resolveRankedView(
  List<RankedMatch> matches,
  Map<String, SeasonMeta> seasons, {
  String? splitId,
  int weekIndex = -1,
}) {
  final buckets = splitBuckets(matches, seasons);
  if (buckets.isEmpty) return RankedView.empty;

  final effId =
      buckets.any((b) => b.id == splitId) ? splitId! : buckets.first.id;
  final bucket = buckets.firstWhere((b) => b.id == effId);
  final weeks =
      bucket.season != null ? computeWeeks(bucket.season!) : <WeekRange>[];
  final effWeek =
      (weekIndex >= 0 && weekIndex < weeks.length) ? weekIndex : -1;

  // Ranked-only matches drive the aggregates…
  final rankedSplit = matchesInSplit(matches, bucket, seasons);
  final filtered =
      effWeek < 0 ? rankedSplit : matchesInWeek(rankedSplit, weeks[effWeek]);

  // …while History keeps everything in the same period (pubs included).
  final allSplit = matchesInSplit(matches, bucket, seasons, rankedOnly: false);
  final history =
      effWeek < 0 ? allSplit : matchesInWeek(allSplit, weeks[effWeek]);

  return RankedView(
    splits: buckets,
    effectiveSplitId: effId,
    weeks: weeks,
    weekIndex: effWeek,
    filtered: filtered,
    history: history,
  );
}
