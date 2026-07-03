/// Pure logic for slicing ranked history by split → week.
///
/// A `SeasonMeta` in this app already represents a season *split* (id
/// `br_ranked_s29_s1` → "S29 Split 1"), and `computeWeeks` divides one into
/// 7-day weeks. Each match is placed into a split by its persisted
/// [RankedMatch.seasonId] — set once by the local history store and never
/// re-derived here — so grouping is stable even when the caller's [seasons]
/// map is momentarily stale or incomplete. Matches with no known split fall
/// into a single "Unknown" bucket.
library;

import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../formatting/season_utils.dart';

/// Catch-all bucket id for matches whose split metadata isn't known. Shares
/// its value with [kUnknownSeasonId] — the store and this UI-facing bucketing
/// must agree on what "unknown" looks like on disk.
const kUnknownSplitId = kUnknownSeasonId;

class RankedSplitBucket {
  final String id; // SeasonMeta.id, or [kUnknownSplitId]
  final String displayName; // "S29 Split 1" or "Unknown"
  final SeasonMeta? season; // null for the "Unknown" bucket

  const RankedSplitBucket({
    required this.id,
    required this.displayName,
    this.season,
  });
}

/// Splits (with at least one ranked match) newest-first, plus an "Unknown"
/// bucket appended last if any match has no classified split.
List<RankedSplitBucket> splitBuckets(
  List<RankedMatch> matches,
  Map<String, SeasonMeta> seasons,
) {
  final ids = <String, DateTime>{}; // id -> newest match end time
  var hasOther = false;

  for (final m in matches.where((m) => m.isRanked)) {
    final id = m.seasonId ?? kUnknownSplitId;
    if (id == kUnknownSplitId) {
      hasOther = true;
    } else {
      final cur = ids[id];
      if (cur == null || m.endTime.isAfter(cur)) ids[id] = m.endTime;
    }
  }

  final buckets = ids.entries
      .map((e) => RankedSplitBucket(
            id: e.key,
            // Metadata may be momentarily missing (e.g. the local season
            // cache was cleared after this id was assigned) — fall back to
            // the raw id rather than lose the bucket entirely.
            displayName: seasons[e.key]?.displayName ?? e.key,
            season: seasons[e.key],
          ))
      .toList()
    ..sort((a, b) => ids[b.id]!.compareTo(ids[a.id]!));

  if (hasOther) {
    buckets.add(const RankedSplitBucket(id: kUnknownSplitId, displayName: 'Unknown'));
  }
  return buckets;
}

/// Matches belonging to [bucket]'s split, by their persisted [seasonId].
/// With [rankedOnly] (default) only ranked matches are returned (for
/// aggregates); pass false to include pubs and every other match (for the
/// History tab).
List<RankedMatch> matchesInSplit(
  List<RankedMatch> matches,
  RankedSplitBucket bucket, {
  bool rankedOnly = true,
}) {
  final pool = rankedOnly ? matches.where((m) => m.isRanked) : matches;
  return pool.where((m) => (m.seasonId ?? kUnknownSplitId) == bucket.id).toList();
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
  final rankedSplit = matchesInSplit(matches, bucket);
  final filtered =
      effWeek < 0 ? rankedSplit : matchesInWeek(rankedSplit, weeks[effWeek]);

  // …while History keeps everything in the same period (pubs included).
  final allSplit = matchesInSplit(matches, bucket, rankedOnly: false);
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
