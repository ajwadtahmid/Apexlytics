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

/// Sentinel id for the synthetic "Lifetime" bucket — every split combined.
/// Never stored on a row; it maps to a null season scope (all splits) in the
/// SQL aggregate queries.
const kLifetimeSplitId = '__lifetime__';

/// Whether [splitId] is the synthetic Lifetime scope (aggregated in SQL, no
/// per-match load).
bool isLifetimeSplit(String? splitId) => splitId == kLifetimeSplitId;

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

/// Builds the split picker from per-split ranked *counts* (not the matches
/// themselves) so the dropdown can render without hydrating any history — the
/// key to scoping match loads to one split at a time. [rankedCounts] comes from
/// `RankedHistoryStore.rankedSeasonCounts` (already folds NULL season ids into
/// [kUnknownSplitId]); [seasons] supplies display metadata.
///
/// Ordered newest-first by season start (a newer season/split has a later
/// start), splits with missing metadata after those, and the "Unknown" bucket
/// always last.
List<RankedSplitBucket> buildSplitBuckets(
  Map<String, int> rankedCounts,
  Map<String, SeasonMeta> seasons,
) {
  final real = <RankedSplitBucket>[];
  var hasUnknown = false;

  for (final entry in rankedCounts.entries) {
    if (entry.value <= 0) continue;
    if (entry.key == kUnknownSplitId) {
      hasUnknown = true;
      continue;
    }
    real.add(
      RankedSplitBucket(
        id: entry.key,
        // Metadata may be momentarily missing (e.g. the local season cache was
        // cleared after this id was assigned) — fall back to the raw id rather
        // than lose the bucket entirely.
        displayName: seasons[entry.key]?.displayName ?? entry.key,
        season: seasons[entry.key],
      ),
    );
  }

  real.sort((a, b) {
    final sa = a.season?.start;
    final sb = b.season?.start;
    if (sa != null && sb != null) return sb.compareTo(sa); // newest first
    if (sa == null && sb == null) return b.id.compareTo(a.id);
    return sa == null ? 1 : -1; // splits with known metadata first
  });

  if (hasUnknown) {
    real.add(
      const RankedSplitBucket(id: kUnknownSplitId, displayName: 'Unknown'),
    );
  }

  // Offer Lifetime only when it aggregates more than one bucket — with a single
  // split it would just duplicate that split.
  if (real.length >= 2) {
    real.insert(
      0,
      const RankedSplitBucket(id: kLifetimeSplitId, displayName: 'Lifetime'),
    );
  }
  return real;
}

/// The split id that a [selectedId] resolves to: itself when it's a real bucket
/// (Lifetime included), otherwise the newest *real* split. Lifetime is never the
/// default — it's opt-in via the picker. Empty string when there are no splits.
/// Callers use this to decide *which* split's matches to load before building
/// the view.
String effectiveSplitId(List<RankedSplitBucket> splits, String? selectedId) {
  if (splits.isEmpty) return '';
  if (splits.any((b) => b.id == selectedId)) return selectedId!;
  return splits
      .firstWhere((b) => b.id != kLifetimeSplitId, orElse: () => splits.first)
      .id;
}

/// The 7-day week windows for [bucket]'s split, or empty when the split has no
/// season metadata (the Unknown bucket).
List<WeekRange> weeksForBucket(RankedSplitBucket bucket) =>
    bucket.season != null ? computeWeeks(bucket.season!) : const <WeekRange>[];

List<RankedMatch> matchesInWeek(List<RankedMatch> matches, WeekRange week) =>
    matches
        .where(
          (m) =>
              !m.endTime.isBefore(week.start) && m.endTime.isBefore(week.end),
        )
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

/// Resolves the [RankedView] from the pre-built [splits] (the picker) and the
/// already-scoped [splitMatches] for the effective split — i.e. exactly one
/// split's rows, loaded via `RankedHistoryStore.getBySeason`, not the whole
/// history. [selectedSplitId] should already be the effective id (see
/// [effectiveSplitId]); an invalid one falls back to the newest split, and an
/// out-of-range [weekIndex] falls back to All.
RankedView resolveRankedView({
  required List<RankedSplitBucket> splits,
  required List<RankedMatch> splitMatches,
  String? selectedSplitId,
  int weekIndex = -1,
}) {
  if (splits.isEmpty) return RankedView.empty;

  final effId = effectiveSplitId(splits, selectedSplitId);
  final bucket = splits.firstWhere((b) => b.id == effId);
  final weeks = weeksForBucket(bucket);
  final effWeek = (weekIndex >= 0 && weekIndex < weeks.length) ? weekIndex : -1;

  // [splitMatches] already belongs to this split, so ranked/history split is
  // just the pubs filter — no per-match season check needed.
  final ranked = splitMatches.where((m) => m.isRanked).toList();
  final filtered = effWeek < 0 ? ranked : matchesInWeek(ranked, weeks[effWeek]);
  final history = effWeek < 0
      ? splitMatches
      : matchesInWeek(splitMatches, weeks[effWeek]);

  return RankedView(
    splits: splits,
    effectiveSplitId: effId,
    weeks: weeks,
    weekIndex: effWeek,
    filtered: filtered,
    history: history,
  );
}
