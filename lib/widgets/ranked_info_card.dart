import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../constants/rank_constants.dart';
import '../models/season_meta.dart';
import '../providers/predator_provider.dart';
import '../utils/formatting/format.dart';
import '../utils/formatting/season_utils.dart' show splitContext;
import '../utils/formatting/rank_utils.dart' show rankIndex, rankAssetPathByTier;
import '../utils/theme.dart';
import 'surface_card.dart';

class RankedInfoCard extends ConsumerWidget {
  final int myRp;
  final String platform;

  /// Drives the split context line; null hides that row.
  final SeasonMeta? season;

  const RankedInfoCard({
    super.key,
    required this.myRp,
    required this.platform,
    this.season,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splitLabel = splitContextLabel(splitContext(season));
    final predAsync = ref.watch(predatorProvider);
    final predVal = predAsync.when(
      data: (result) => result.data.forPlatform(platform)?.minRp,
      loading: () => null,
      error: (e, _) => null,
    );

    final isPred = predVal != null && myRp >= predVal;
    final idx = rankIndex(myRp);
    final current = kRankLadder[idx];
    final currentColor = isPred ? kPredatorColor : current.color;
    final currentLabel = isPred ? kApexPredatorRank : current.label;

    int? nextRp;
    String? nextLabel;
    if (!isPred) {
      if (idx < kRankLadder.length - 1) {
        nextRp = kRankLadder[idx + 1].rp;
        nextLabel = kRankLadder[idx + 1].label;
      } else if (predVal != null) {
        // Player is at Master: show progress toward Predator if the threshold is available.
        nextRp = predVal;
        nextLabel = kApexPredatorRank;
      }
      // If at Master and predVal is null (Predator threshold unavailable), nextRp/nextLabel
      // remain null and the progress bar won't be shown.
    }

    final curRp = current.rp;
    final progress = nextRp != null && nextRp > curRp
        ? ((myRp - curRp) / (nextRp - curRp)).clamp(0.0, 1.0)
        : 1.0;
    // Clamp to [0, bracket range] so data anomalies (negative RP) don't
    // produce a gap larger than the entire bracket.
    final gap = nextRp != null ? (nextRp - myRp).clamp(0, nextRp - curRp) : 0;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      border: Border.all(color: currentColor.withAlpha(60)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppTheme.rankIconSize,
                height: AppTheme.rankIconSize,
                decoration: BoxDecoration(
                  color: currentColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.asset(
                  rankAssetPathByTier(isPred, idx),
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, trace) => Center(
                    child: Text(
                      isPred ? 'PR' : (current.division ?? 'M'),
                      style: TextStyle(
                        color: currentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentLabel,
                    style: TextStyle(
                      color: currentColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${formatNumber(myRp)} RP',
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!isPred && nextRp != null) ...[
            const SizedBox(height: AppTheme.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppTheme.surface2,
                color: currentColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatNumber(curRp)} RP',
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${formatNumber(gap)} RP to $nextLabel',
                  style: TextStyle(
                    color: currentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${formatNumber(nextRp)} RP',
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ] else if (isPred)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.sm),
              child: Text(
                'Top 750 on ${ApiConstants.labelFor(platform)}',
                style: const TextStyle(color: kPredatorColor, fontSize: 13),
              ),
            ),
          if (splitLabel.isNotEmpty) ...[
            const SizedBox(height: AppTheme.sm),
            Text(
              splitLabel,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
