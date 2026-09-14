import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatNumber, formatDuration, formatSigned;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/win_loss_stat.dart';
import '../ranked_entity_history_screen.dart';
import 'match_history_items.dart' show MatchGrouping;

/// Opens the shared map detail sheet — used by both the Overview
/// Best/Worst Map cards and the Maps tab rows, so the two surfaces stay
/// identical rather than drifting into separate implementations.
Future<void> showMapDetailSheet(
  BuildContext context,
  MapBreakdown map,
  Future<List<RankedMatch>> Function(String mapKey) matchesFor,
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
    builder: (_) =>
        _MapDetailSheet(map: map, matchesFor: matchesFor, onRefresh: onRefresh),
  );
}

/// Detail sheet for a map: the full stat set the Maps tab shows per row, plus
/// a "View all history" button that resolves this map's matches and pushes
/// the same [RankedEntityHistoryScreen] drill-down the Maps tab uses.
class _MapDetailSheet extends StatelessWidget {
  final MapBreakdown map;
  final Future<List<RankedMatch>> Function(String mapKey) matchesFor;
  final Future<void> Function() onRefresh;

  const _MapDetailSheet({
    required this.map,
    required this.matchesFor,
    required this.onRefresh,
  });

  Future<void> _viewHistory(BuildContext context) async {
    final games = await matchesFor(map.mapKey)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: map.displayName,
          subtitle:
              '${map.games} ranked games · ${formatSigned(map.avgRpPerGame)} RP/game',
          matches: games,
          onRefresh: onRefresh,
          groupLabel: 'legend',
          grouping: MatchGrouping(
            keyOf: (m) => m.legend,
            nameOf: (m) => m.legend,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = battleRoyaleMapAsset(map.mapKey);
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
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: SizedBox(
                    width: 72,
                    height: 44,
                    child: asset != null
                        ? Image.asset(
                            asset,
                            fit: BoxFit.cover,
                            cacheWidth: 400,
                            errorBuilder: (_, _, _) =>
                                Container(color: AppTheme.surface2),
                          )
                        : Container(color: AppTheme.surface2),
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Text(
                  map.displayName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
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
                  value: formatSigned(map.avgRpPerGame),
                  valueColor: map.avgRpPerGame >= 0
                      ? AppTheme.green
                      : AppTheme.red,
                ),
                StatDisplay(
                  label: 'Total RP',
                  value: formatSigned(map.totalRp.toDouble()),
                  valueColor: map.totalRp >= 0 ? AppTheme.green : AppTheme.red,
                ),
                WinLossStat(wins: map.wins, losses: map.losses),
                StatDisplay(
                  label: 'Total Kills',
                  value: formatNumber(map.totalKills),
                ),
                StatDisplay(
                  label: 'Avg Kills',
                  value: map.avgKills.toStringAsFixed(1),
                ),
                StatDisplay(
                  label: 'Total Dmg',
                  value: formatNumber(map.totalDamage),
                ),
                StatDisplay(
                  label: 'Avg Dmg',
                  value: formatNumber(map.avgDamage.round()),
                ),
                StatDisplay(
                  label: 'Total Time',
                  value: formatDuration(map.totalLengthSecs),
                ),
                StatDisplay(
                  label: 'Avg Time',
                  value: formatDuration(map.avgLengthSecs.round()),
                ),
                StatDisplay(label: 'Games', value: '${map.games}'),
              ],
            ),
            const SizedBox(height: AppTheme.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _viewHistory(context),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('History'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
