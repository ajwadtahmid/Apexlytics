import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart'
    show formatDuration, formatNumber, formatSigned, formatSignedInt;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/surface_card.dart';
import '../../../widgets/win_loss_stat.dart';

/// Match-stat aggregates for the ranked window, grouped into RP/record,
/// combat, and playtime sections — same convention as the drill-down sheets.
class RankedStatsCard extends StatelessWidget {
  final RankedSummary summary;
  const RankedStatsCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final avgRp = s.avgRpPerGame;
    final avgRpColor = avgRp >= 0 ? AppTheme.green : AppTheme.red;
    final netRpColor = s.netRp >= 0 ? AppTheme.green : AppTheme.red;

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
          GroupedStatChips(
            alignment: WrapAlignment.center,
            groups: [
              [
                StatDisplay(
                  label: 'Avg RP',
                  value: formatSigned(avgRp),
                  valueColor: avgRpColor,
                ),
                StatDisplay(
                  label: 'Total RP',
                  value: formatSignedInt(s.netRp),
                  valueColor: netRpColor,
                ),
                WinLossStat(wins: s.wins, losses: s.losses),
                StatDisplay(label: 'Games', value: '${s.games}'),
              ],
              [
                StatDisplay(
                  label: 'Avg Kills',
                  value: s.avgKills.toStringAsFixed(1),
                ),
                StatDisplay(label: 'Kills', value: formatNumber(s.totalKills)),
                StatDisplay(
                  label: 'Avg Dmg',
                  value: formatNumber(s.avgDamage.round()),
                ),
                StatDisplay(label: 'Dmg', value: formatNumber(s.totalDamage)),
              ],
              [
                StatDisplay(
                  label: 'Avg Time',
                  value: formatDuration(s.avgGameLengthSecs.round()),
                ),
                StatDisplay(
                  label: 'Time',
                  value: formatDuration(s.totalLengthSecs),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
