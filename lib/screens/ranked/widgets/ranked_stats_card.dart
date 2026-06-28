import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatDuration, formatNumber;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/surface_card.dart';

/// Match-stat aggregates for the ranked window — averages plus season totals,
/// laid out as a centered chip grid.
class RankedStatsCard extends StatelessWidget {
  final RankedSummary summary;
  const RankedStatsCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final avgRp = s.avgRpPerGame;

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
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppTheme.sm,
            runSpacing: AppTheme.sm,
            children: [
              StatDisplay(
                label: 'Avg RP',
                value: '${avgRp >= 0 ? '+' : ''}${avgRp.toStringAsFixed(1)}',
              ),
              StatDisplay(label: 'Games', value: '${s.games}'),
              StatDisplay(
                  label: 'Avg Kills', value: s.avgKills.toStringAsFixed(1)),
              StatDisplay(label: 'Kills', value: formatNumber(s.totalKills)),
              StatDisplay(
                  label: 'Avg Dmg', value: formatNumber(s.avgDamage.round())),
              StatDisplay(label: 'Dmg', value: formatNumber(s.totalDamage)),
              StatDisplay(
                  label: 'Avg Time',
                  value: formatDuration(s.avgGameLengthSecs.round())),
              StatDisplay(
                  label: 'Time', value: formatDuration(s.totalLengthSecs)),
            ],
          ),
        ],
      ),
    );
  }
}
