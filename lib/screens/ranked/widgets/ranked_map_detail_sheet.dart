import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../providers/entity_trend_overrides_provider.dart';
import '../../../providers/entity_trend_window_provider.dart';
import '../../../utils/formatting/format.dart'
    show
        formatAvgDamage,
        formatAvgKills,
        formatNumber,
        formatDuration,
        formatSigned,
        formatSignedInt,
        formatTotalOrNone, plural;
import '../../../utils/ranked/entity_trend_window.dart';
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/map_asset_image.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/trend_lines.dart';
import '../../../widgets/trend_window_picker.dart';
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
  Future<void> Function() onRefresh, {
  List<RankedMatch>? sessionPool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MapDetailSheet(
      map: map,
      matchesFor: matchesFor,
      onRefresh: onRefresh,
      sessionPool: sessionPool,
    ),
  );
}

/// Detail sheet for a map: the full stat set the Maps tab shows per row, plus
/// a "View all history" button that resolves this map's matches and pushes
/// the same [RankedEntityHistoryScreen] drill-down the Maps tab uses.
class _MapDetailSheet extends ConsumerStatefulWidget {
  final MapBreakdown map;
  final Future<List<RankedMatch>> Function(String mapKey) matchesFor;
  final Future<void> Function() onRefresh;

  /// The scope's full history, for the history page's sessions.
  final List<RankedMatch>? sessionPool;

  const _MapDetailSheet({
    required this.map,
    required this.matchesFor,
    required this.onRefresh,
    this.sessionPool,
  });

  @override
  ConsumerState<_MapDetailSheet> createState() => _MapDetailSheetState();
}

class _MapDetailSheetState extends ConsumerState<_MapDetailSheet> {
  MapBreakdown get map => widget.map;
  Future<void> Function() get onRefresh => widget.onRefresh;

  /// The map's matches, loaded once (not per rebuild). Its trends are worked
  /// out from them as the window changes.
  final _trends = EntityTrendReadingCache();

  late final Future<List<RankedMatch>> _loaded = widget.matchesFor(map.mapKey);

  Future<void> _viewHistory(BuildContext context) async {
    // Copy: keep the loaded list in the order the trends used.
    final games = [...await _loaded]
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: map.displayName,
          subtitle:
              '${plural(map.games, 'ranked game')} · ${formatSigned(map.avgRpPerGame)} RP/game',
          matches: games,
          onRefresh: onRefresh,
          groupLabel: 'legend',
          grouping: MatchGrouping.byLegend,
          sessionPool: widget.sessionPool,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The map's own window if it has one, else the one chosen for all.
    final trendKey = mapTrendKey(map.mapKey);
    final int trendChoice =
        ref.watch(entityTrendOverridesProvider)[trendKey] ??
        ref.watch(entityTrendWindowProvider);
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
                Expanded(
                  child: Text(
                    map.displayName,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                      avg: formatAvgKills(map.avgKills),
                      total: formatTotalOrNone(map.totalKills, map.killsGames),
                    ),
                    StatTableRow(
                      label: 'Damage',
                      avg: formatAvgDamage(map.avgDamage),
                      total: formatTotalOrNone(
                        map.totalDamage,
                        map.damageGames,
                      ),
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
            FutureBuilder<List<RankedMatch>>(
              future: _loaded,
              builder: (context, snapshot) {
                final matches = snapshot.data;
                if (matches == null) return const SizedBox.shrink();
                final reading = _trends.read(matches, trendChoice);
                final window = reading.window;
                // With too few games there is nothing to compare, or to say.
                if (window == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppTheme.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: EntityTrendWindowPill(
                        overrideKey: trendKey,
                        name: map.displayName,
                        games: matches.length,
                        window: window,
                      ),
                    ),
                    TrendLines(trends: reading.trends),
                    TrendFootnote(window: window),
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
