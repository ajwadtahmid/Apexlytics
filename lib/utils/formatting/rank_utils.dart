import 'dart:ui';
import '../../constants/rank_constants.dart';
import '../../models/player_stats.dart';

/// Returns the index into [kRankLadder] for the given [rankPoints].
int rankIndex(int rankPoints) {
  for (var i = kRankLadder.length - 1; i >= 0; i--) {
    if (rankPoints >= kRankLadder[i].rp) return i;
  }
  return 0;
}

/// Returns the display label for [stats.rank], using the Apex Predator
/// constant when the rank string matches it.
String rankLabel(PlayerStats stats) => stats.rank == kApexPredatorRank
    ? kApexPredatorRank
    : kRankLadder[rankIndex(stats.rankScore)].label;

/// Returns the color associated with [stats.rank].
Color rankColor(PlayerStats stats) {
  if (stats.rank == kApexPredatorRank) return kPredatorColor;
  return kRankLadder[rankIndex(stats.rankScore)].color;
}

/// Returns the asset path for the rank icon associated with [stats.rank].
String rankAssetPath(PlayerStats stats) {
  if (stats.rank == kApexPredatorRank) return 'assets/ranks/apex_predator.webp';
  return kRankLadder[rankIndex(stats.rankScore)].assetPath;
}

/// Returns the asset path for a rank tier given predator status and rank index.
///
/// [tierIndex] is clamped into [kRankLadder]'s range: callers are expected to
/// pass a [rankIndex]-derived value, but this is a public helper next to
/// [kPredatorGoalIndex] — a sentinel stored in prefs the same way real ladder
/// indices are — so an out-of-range value must degrade, not throw.
String rankAssetPathByTier(bool isPredator, int tierIndex) {
  if (isPredator) return 'assets/ranks/apex_predator.webp';
  return kRankLadder[tierIndex.clamp(0, kRankLadder.length - 1)].assetPath;
}

/// Tiers bundled as `assets/ranks/<tier>.webp`.
const _bundledRankTiers = {
  'bronze',
  'silver',
  'gold',
  'platinum',
  'diamond',
  'master',
};

/// The bundled badge for a rank image URL (`…/platinum3.png`), or null for an unbundled
/// tier or unusable URL. Only the file name is read, so nothing is fetched; the division
/// is dropped.
String? rankAssetPathFromImageUrl(String url) {
  final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
  if (segments.isEmpty) return null;
  final file = segments.last;
  final dot = file.lastIndexOf('.');
  // `platinum3.png` → `platinum`; `apex_predator.png` → `apexpredator`.
  final tier = (dot > 0 ? file.substring(0, dot) : file)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z]'), '');
  if (tier == 'apexpredator' || tier == 'predator') {
    return 'assets/ranks/apex_predator.webp';
  }
  return _bundledRankTiers.contains(tier) ? 'assets/ranks/$tier.webp' : null;
}
