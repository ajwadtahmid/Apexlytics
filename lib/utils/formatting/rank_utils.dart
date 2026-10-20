import '../../constants/rank_constants.dart';
import '../../models/player_stats.dart';

/// Returns the index into [kRankLadder] for the given [rankPoints].
int rankIndex(int rankPoints) {
  for (var i = kRankLadder.length - 1; i >= 0; i--) {
    if (rankPoints >= kRankLadder[i].rp) return i;
  }
  return 0;
}

// ── Apex Predator ───────────────────────────────────────────────────────────
//
// Every "is this player Predator?" check on RP goes through here:
//   1. Predator sits above Master: below the Master floor (the ladder's last
//      entry) nobody is one, whatever the cutoff says.
//   2. The cutoff is the live RP of the lowest Predator, from `/predator`. One
//      below the Master floor is a missing or placeholder value (parsed as 0),
//      so it counts as no cutoff, not as "everyone qualifies".
//   3. So: Predator = a usable cutoff, and RP at or above it.
// The API's own rank name (see [rankLabel]) is a separate source.

/// [cutoff] if it can be a real Predator cutoff (at or above the Master
/// floor), otherwise null.
int? usablePredatorCutoff(int? cutoff) =>
    cutoff != null && cutoff >= kRankLadder.last.rp ? cutoff : null;

/// Whether [rp] is Apex Predator given the live [cutoff] (raw, as served).
bool isApexPredatorRp(int rp, int? cutoff) {
  final usable = usablePredatorCutoff(cutoff);
  return usable != null && rp >= usable;
}

/// Returns the display label for [stats.rank], using the Apex Predator
/// constant when the rank string matches it.
String rankLabel(PlayerStats stats) =>
    rankLabelFor(stats.rank, stats.rankScore);

/// [rankLabel] from a stored rank name and RP, for a player whose full stats
/// aren't to hand.
String rankLabelFor(String rank, int rankScore) => rank == kApexPredatorRank
    ? kApexPredatorRank
    : kRankLadder[rankIndex(rankScore)].label;

/// Returns the asset path for the rank icon associated with [stats.rank].
///
/// Null when the tier has no bundled art (Rookie): show no badge.
String? rankAssetPath(PlayerStats stats) =>
    rankAssetPathFor(stats.rank, stats.rankScore);

/// [rankAssetPath] from a stored rank name and RP.
String? rankAssetPathFor(String rank, int rankScore) {
  if (rank == kApexPredatorRank) return kPredatorBadgeAsset;
  return kRankLadder[rankIndex(rankScore)].assetPath;
}

/// Returns the asset path for a rank tier given predator status and rank index.
///
/// [tierIndex] is clamped into [kRankLadder]'s range: callers are expected to
/// pass a [rankIndex]-derived value, but this is a public helper next to
/// [kPredatorGoalIndex] — a sentinel stored in prefs the same way real ladder
/// indices are — so an out-of-range value must degrade, not throw.
///
/// Null when the tier has no bundled art (Rookie): show no badge.
String? rankAssetPathByTier(bool isPredator, int tierIndex) {
  if (isPredator) return kPredatorBadgeAsset;
  return kRankLadder[tierIndex.clamp(0, kRankLadder.length - 1)].assetPath;
}

/// The bundled badge for a rank image URL (`…/platinum3.png`), or null for an unbundled
/// tier or unusable URL. Only the file name is read, so nothing is fetched. The trailing
/// number is the division, which picks that division's badge.
String? rankAssetPathFromImageUrl(String url) {
  final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
  if (segments.isEmpty) return null;
  final file = segments.last;
  final dot = file.lastIndexOf('.');
  final name = (dot > 0 ? file.substring(0, dot) : file).toLowerCase();
  // `platinum3.png` → `platinum`; `apex_predator.png` → `apexpredator`.
  final tier = name.replaceAll(RegExp(r'[^a-z]'), '');
  if (tier == 'apexpredator' || tier == 'predator') {
    return kPredatorBadgeAsset;
  }
  final division = int.tryParse(
    RegExp(r'\d+').firstMatch(name)?.group(0) ?? '',
  );
  return rankBadgePath(tier, division: division);
}
