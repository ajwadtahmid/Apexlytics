import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart'
    show formatDuration, formatNumber, formatSigned, formatSignedInt;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/surface_card.dart';
import '../../../widgets/win_loss_stat.dart';

/// Match-stat aggregates for the ranked window, as a record row plus an
/// Avg | Total table; the drill-down sheets use a 2-column chip grid instead.
class RankedStatsCard extends StatelessWidget {
  final RankedSummary summary;
  const RankedStatsCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final avgRp = s.avgRpPerGame;
    final avgRpColor = AppTheme.signColor(avgRp >= 0);
    final netRpColor = AppTheme.signColor(s.netRp >= 0);

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STATS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.muted,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          StatGrid(
            rows: [
              [
                WinLossStat(wins: s.wins, losses: s.losses, centered: true),
                StatDisplay(
                  label: 'Games',
                  centered: true,
                  value: formatNumber(s.games),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTheme.sm),
          StatTable(
            rows: [
              StatTableRow(
                label: 'RP',
                avg: formatSigned(avgRp),
                total: formatSignedInt(s.netRp),
                avgColor: avgRpColor,
                totalColor: netRpColor,
              ),
              StatTableRow(
                label: 'Kills',
                avg: s.avgKills.toStringAsFixed(1),
                total: formatNumber(s.totalKills),
              ),
              StatTableRow(
                label: 'Damage',
                avg: formatNumber(s.avgDamage.round()),
                total: formatNumber(s.totalDamage),
              ),
              StatTableRow(
                label: 'Time',
                avg: formatDuration(s.avgGameLengthSecs.round()),
                total: formatDuration(s.totalLengthSecs),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
