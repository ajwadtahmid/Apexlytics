import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatNumber, formatDuration;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/surface_card.dart';

/// Top-of-Overview card: current tier + RP, net RP for the window, and the
/// headline totals + per-game averages for the selected period.
class RankedSummaryHeader extends StatelessWidget {
  final RankedSummary summary;

  const RankedSummaryHeader({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final netPositive = summary.netRp >= 0;
    final netColor = netPositive ? AppTheme.green : AppTheme.red;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (summary.latestRankImg.isNotEmpty) ...[
                CachedNetworkImage(
                  imageUrl: summary.latestRankImg,
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const SizedBox(width: 36),
                ),
                const SizedBox(width: AppTheme.sm),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current RP',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                  Text(
                    formatNumber(summary.currentRp),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: netColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  '${netPositive ? '+' : ''}${formatNumber(summary.netRp)} RP',
                  style: TextStyle(
                    color: netColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.xs),
          Text(
            '${summary.games} ranked games',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: AppTheme.md),
          Wrap(
            spacing: AppTheme.sm,
            runSpacing: AppTheme.sm,
            children: [
              StatDisplay(label: 'Games', value: '${summary.games}'),
              StatDisplay(
                  label: 'Total Kills', value: formatNumber(summary.totalKills)),
              StatDisplay(
                  label: 'Avg Kills', value: summary.avgKills.toStringAsFixed(1)),
              StatDisplay(
                  label: 'Total Dmg', value: formatNumber(summary.totalDamage)),
              StatDisplay(
                  label: 'Avg Dmg',
                  value: formatNumber(summary.avgDamage.round())),
              StatDisplay(
                  label: 'Total Time',
                  value: formatDuration(summary.totalLengthSecs)),
              StatDisplay(
                  label: 'Avg Time',
                  value: formatDuration(summary.avgGameLengthSecs.round())),
            ],
          ),
        ],
      ),
    );
  }
}
