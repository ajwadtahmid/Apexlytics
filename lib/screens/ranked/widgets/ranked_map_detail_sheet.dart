import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatNumber, formatDuration, formatSigned, formatSignedInt;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/map_asset_image.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/trend_lines.dart';
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
class _MapDetailSheet extends StatefulWidget {
  final MapBreakdown map;
  final Future<List<RankedMatch>> Function(String mapKey) matchesFor;
  final Future<void> Function() onRefresh;

  const _MapDetailSheet({
    required this.map,
    required this.matchesFor,
    required this.onRefresh,
  });

  @override
  State<_MapDetailSheet> createState() => _MapDetailSheetState();
}

class _MapDetailSheetState extends State<_MapDetailSheet> {
  MapBreakdown get map => widget.map;
  Future<void> Function() get onRefresh => widget.onRefresh;

  /// The map's matches and their trends, loaded once (not per rebuild).
  late final Future<({List<RankedMatch> matches, EntityTrends trends})> _loaded =
      widget.matchesFor(map.mapKey).then(
        (matches) => (matches: matches, trends: entityTrends(matches)),
      );

  Future<void> _viewHistory(BuildContext context) async {
    // Copy: keep the loaded list in the order the trends used.
    final games = [...(await _loaded).matches]
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
                        ? MapAssetImage(asset: asset)
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
            Column(
              children: [
                StatGrid(
                  rows: [
                    [
                      WinLossStat(
                        wins: map.wins,
                        losses: map.losses,
                        centered: true,
                      ),
                      StatDisplay(
                        label: 'Games',
                        centered: true,
                        value: formatNumber(map.games),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppTheme.sm),
                StatTable(
                  rows: [
                    StatTableRow(
                      label: 'RP',
                      avg: formatSigned(map.avgRpPerGame),
                      total: formatSignedInt(map.totalRp),
                      avgColor: AppTheme.signColor(map.avgRpPerGame >= 0),
                      totalColor: AppTheme.signColor(map.totalRp >= 0),
                    ),
                    StatTableRow(
                      label: 'Kills',
                      avg: map.avgKills.toStringAsFixed(1),
                      total: formatNumber(map.totalKills),
                    ),
                    StatTableRow(
                      label: 'Damage',
                      avg: formatNumber(map.avgDamage.round()),
                      total: formatNumber(map.totalDamage),
                    ),
                    StatTableRow(
                      label: 'Time',
                      avg: formatDuration(map.avgLengthSecs.round()),
                      total: formatDuration(map.totalLengthSecs),
                    ),
                  ],
                ),
              ],
            ),
            FutureBuilder<({List<RankedMatch> matches, EntityTrends trends})>(
              future: _loaded,
              builder: (context, snapshot) {
                final loaded = snapshot.data;
                if (loaded == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TrendLines(trends: loaded.trends),
                    const TrendFootnote(),
                  ],
                );
              },
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
