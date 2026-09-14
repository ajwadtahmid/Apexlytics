import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/legend_constants.dart';
import '../../../constants/map_constants.dart';
import '../../../models/player_stats.dart';
import '../../../models/ranked_match.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/formatting/format.dart'
    show formatNumber, formatDuration, formatSigned;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/storage/legend_stats_storage.dart';
import '../../../utils/theme.dart';
import '../../../widgets/legend_asset_image.dart';
import '../../../widgets/legend_detail_page.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/win_loss_stat.dart';
import '../ranked_entity_history_screen.dart';
import 'match_history_items.dart' show MatchGrouping;

/// Opens the shared legend detail sheet — used by both the Overview
/// Best/Worst Legend cards and the Legends tab rows, so the two surfaces stay
/// identical rather than drifting into separate implementations.
Future<void> showLegendDetailSheet(
  BuildContext context,
  LegendBreakdown breakdown,
  Future<List<RankedMatch>> Function(String legend) matchesFor,
  Future<void> Function() onRefresh,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => _LegendDetailSheet(
      breakdown: breakdown,
      matchesFor: matchesFor,
      onRefresh: onRefresh,
    ),
  );
}

/// Detail sheet for a legend: the full stat set the Legends tab shows per
/// row, plus a "View all history" button that resolves this legend's matches
/// and pushes the same [RankedEntityHistoryScreen] drill-down the Legends tab
/// uses. "All Trackers" resolves the persisted career [LegendStat] for this
/// legend — a pure read of what [mergeLegendStats] already wrote during the
/// normal My Stats flow, so opening this never re-triggers that merge — and
/// pushes the same [LegendDetailPage] My Stats uses; hidden when no matching
/// stat exists. Labeled "Trackers" (not "All Trackers", the Overview button
/// that opens every legend's trackers) since this one is scoped to a single
/// legend.
class _LegendDetailSheet extends ConsumerWidget {
  final LegendBreakdown breakdown;
  final Future<List<RankedMatch>> Function(String legend) matchesFor;
  final Future<void> Function() onRefresh;

  const _LegendDetailSheet({
    required this.breakdown,
    required this.matchesFor,
    required this.onRefresh,
  });

  Future<void> _viewHistory(BuildContext context) async {
    final games = await matchesFor(breakdown.legend)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: breakdown.legend,
          subtitle:
              '${breakdown.games} ranked games · '
              '${formatSigned(breakdown.avgRpPerGame)} RP/game',
          matches: games,
          onRefresh: onRefresh,
          groupLabel: 'map',
          grouping: MatchGrouping(
            keyOf: (m) => m.mapKey,
            nameOf: (m) => battleRoyaleMapName(m.mapKey),
          ),
        ),
      ),
    );
  }

  void _viewTrackers(BuildContext context, LegendStat stat) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LegendDetailPage(legend: stat)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = kLegendsByName[breakdown.legend.toLowerCase()];
    final uid = ref.watch(playerSettingsProvider.select((s) => s.uid));
    final prefs = ref.watch(sharedPreferencesProvider);
    final target = breakdown.legend.toLowerCase();
    LegendStat? legendStat;
    for (final s in loadLegendStats(prefs, uid: uid)) {
      if (s.name.toLowerCase() == target) {
        legendStat = s;
        break;
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: LegendAssetImage(
                      imageKey: legendImageKey(breakdown.legend),
                      displayName: breakdown.legend,
                      fallbackFontSize: 30,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        breakdown.legend,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (info != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: info.role.color.withAlpha(35),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                          ),
                          child: Text(
                            info.role.displayName,
                            style: TextStyle(
                              color: info.role.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.md),
            Wrap(
              spacing: AppTheme.sm,
              runSpacing: AppTheme.sm,
              children: [
                StatDisplay(
                  label: 'Avg RP',
                  value: formatSigned(breakdown.avgRpPerGame),
                  valueColor: breakdown.avgRpPerGame >= 0
                      ? AppTheme.green
                      : AppTheme.red,
                ),
                StatDisplay(
                  label: 'Total RP',
                  value: formatSigned(breakdown.totalRp.toDouble()),
                  valueColor: breakdown.totalRp >= 0
                      ? AppTheme.green
                      : AppTheme.red,
                ),
                WinLossStat(wins: breakdown.wins, losses: breakdown.losses),
                StatDisplay(
                  label: 'Total Kills',
                  value: formatNumber(breakdown.totalKills),
                ),
                StatDisplay(
                  label: 'Avg Kills',
                  value: breakdown.avgKills.toStringAsFixed(1),
                ),
                StatDisplay(
                  label: 'Total Dmg',
                  value: formatNumber(breakdown.totalDamage),
                ),
                StatDisplay(
                  label: 'Avg Dmg',
                  value: formatNumber(breakdown.avgDamage.round()),
                ),
                StatDisplay(
                  label: 'Total Time',
                  value: formatDuration(breakdown.totalLengthSecs),
                ),
                StatDisplay(
                  label: 'Avg Time',
                  value: formatDuration(breakdown.avgLengthSecs.round()),
                ),
                StatDisplay(label: 'Games', value: '${breakdown.games}'),
              ],
            ),
            const SizedBox(height: AppTheme.md),
            Row(
              children: [
                if (legendStat != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _viewTrackers(context, legendStat!),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: const BorderSide(color: AppTheme.accent),
                      ),
                      icon: const Icon(Icons.bar_chart, size: 18),
                      label: const Text('Trackers'),
                    ),
                  ),
                  const SizedBox(width: AppTheme.sm),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _viewHistory(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                    ),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('History'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
