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
String rankLabel(PlayerStats stats) =>
    stats.rank == kApexPredatorRank
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
String rankAssetPathByTier(bool isPredator, int tierIndex) {
  if (isPredator) return 'assets/ranks/apex_predator.webp';
  return kRankLadder[tierIndex].assetPath;
}
