import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/player_stats.dart';
import '../../../models/ranked_match.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/formatting/format.dart'
    show
        formatAvgDamage,
        formatAvgKills,
        formatNumber,
        formatDuration,
        formatSigned,
        formatSignedInt,
        formatTotalOrNone, plural;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/storage/legend_stats_storage.dart';
import '../../../utils/theme.dart';
import '../../../widgets/legend_header.dart';
import '../../../widgets/legend_trackers_sheet.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/trend_lines.dart';
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
  Future<void> Function() onRefresh, {
  List<RankedMatch>? sessionPool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LegendDetailSheet(
      breakdown: breakdown,
      matchesFor: matchesFor,
      onRefresh: onRefresh,
      sessionPool: sessionPool,
    ),
  );
}

/// Opens a legend's [games] (newest first) as a history page, with a toggle to
/// group them by map.
void openLegendHistory(
  BuildContext context,
  LegendBreakdown breakdown,
  List<RankedMatch> games,
  Future<void> Function() onRefresh, {
  List<RankedMatch>? sessionPool,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RankedEntityHistoryScreen(
        title: breakdown.legend,
        subtitle:
            '${plural(breakdown.games, 'ranked game')} · '
            '${formatSigned(breakdown.avgRpPerGame)} RP/game',
        matches: games,
        onRefresh: onRefresh,
        groupLabel: 'map',
        grouping: MatchGrouping.byMap,
        sessionPool: sessionPool,
      ),
    ),
  );
}

/// Detail sheet for a legend: the full stat set the Legends tab shows per
/// row, plus a "View all history" button that resolves this legend's matches
/// and pushes the same [RankedEntityHistoryScreen] drill-down the Legends tab
/// uses. "All Trackers" resolves the persisted career [LegendStat] for this
/// legend — a pure read of what [mergeLegendStats] already wrote during the
/// normal My Stats flow, so opening this never re-triggers that merge — and
/// opens the same trackers sheet the All Trackers list uses; hidden when no
/// matching stat exists. Labeled "Trackers" (not "All Trackers", the Overview
/// button that opens every legend's trackers) since this one is scoped to a
/// single legend.
class _LegendDetailSheet extends ConsumerStatefulWidget {
  final LegendBreakdown breakdown;
  final Future<List<RankedMatch>> Function(String legend) matchesFor;
  final Future<void> Function() onRefresh;

  /// The scope's full history, for the history page's sessions.
  final List<RankedMatch>? sessionPool;

  const _LegendDetailSheet({
    required this.breakdown,
    required this.matchesFor,
    required this.onRefresh,
    this.sessionPool,
  });

  @override
  ConsumerState<_LegendDetailSheet> createState() => _LegendDetailSheetState();
}

class _LegendDetailSheetState extends ConsumerState<_LegendDetailSheet> {
  LegendBreakdown get breakdown => widget.breakdown;
  Future<void> Function() get onRefresh => widget.onRefresh;

  /// The legend's matches and their trends, loaded once (not per rebuild).
  late final Future<({List<RankedMatch> matches, EntityTrends trends})> _loaded =
      widget.matchesFor(breakdown.legend).then(
        (matches) => (matches: matches, trends: entityTrends(matches)),
      );

  Future<void> _viewHistory(BuildContext context) async {
    // Copy: keep the loaded list in the order the trends used.
    final games = [...(await _loaded).matches]
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (!context.mounted) return;
    openLegendHistory(
      context,
      breakdown,
      games,
      onRefresh,
      sessionPool: widget.sessionPool,
    );
  }

  void _viewTrackers(BuildContext context, LegendStat stat) {
    showLegendTrackersSheet(context, stat);
  }

  @override
  Widget build(BuildContext context) {
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
            LegendHeader(name: breakdown.legend),
            const SizedBox(height: AppTheme.md),
            Column(
              children: [
                StatGrid(
                  rows: [
                    [
                      WinLossStat(
                        wins: breakdown.wins,
                        losses: breakdown.losses,
                      ),
                      StatDisplay(
                        label: 'Games',
                        centered: true,
                        value: formatNumber(breakdown.games),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppTheme.sm),
                StatTable(
                  rows: [
                    StatTableRow(
                      label: 'RP',
                      avg: formatSigned(breakdown.avgRpPerGame),
                      total: formatSignedInt(breakdown.totalRp),
                      avgColor: AppTheme.signColor(breakdown.avgRpPerGame >= 0),
                      totalColor: AppTheme.signColor(breakdown.totalRp >= 0),
                    ),
                    StatTableRow(
                      label: 'Kills',
                      avg: formatAvgKills(breakdown.avgKills),
                      total: formatTotalOrNone(
                        breakdown.totalKills,
                        breakdown.killsGames,
                      ),
                    ),
                    StatTableRow(
                      label: 'Damage',
                      avg: formatAvgDamage(breakdown.avgDamage),
                      total: formatTotalOrNone(
                        breakdown.totalDamage,
                        breakdown.damageGames,
                      ),
                    ),
                    StatTableRow(
                      label: 'Time',
                      avg: formatDuration(breakdown.avgLengthSecs.round()),
                      total: formatDuration(breakdown.totalLengthSecs),
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
