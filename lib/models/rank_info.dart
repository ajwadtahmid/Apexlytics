import 'dart:ui';
import '../constants/rank_constants.dart';
import '../models/player_stats.dart';
import '../utils/formatting/rank_utils.dart' show rankIndex;

class RankInfo {
  final String label;
  final Color color;
  final String? nextLabel;
  final int? rpToNext;
  final String? tier;

  const RankInfo({
    required this.label,
    required this.color,
    this.nextLabel,
    this.rpToNext,
    this.tier,
  });

  factory RankInfo.from(PlayerStats s) {
    if (s.rank == kApexPredatorRank) {
      return const RankInfo(label: kApexPredatorRank, color: kPredatorColor);
    }
    final idx = rankIndex(s.rankScore);
    final division = kRankLadder[idx];
    final String? nextLabel = idx < kRankLadder.length - 1
        ? kRankLadder[idx + 1].label
        : null;
    final int? rpToNext = idx < kRankLadder.length - 1
        ? kRankLadder[idx + 1].rp - s.rankScore
        : null;
    return RankInfo(
      label: division.label,
      color: division.color,
      nextLabel: nextLabel,
      rpToNext: rpToNext,
      tier: division.tier,
    );
  }
}
