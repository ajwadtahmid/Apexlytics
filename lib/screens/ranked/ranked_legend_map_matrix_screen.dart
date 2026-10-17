import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/legend_constants.dart' show legendInfo;
import '../../constants/map_constants.dart' show battleRoyaleMapInfo;
import '../../models/ranked_match.dart';
import '../../providers/map_provider.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../utils/formatting/format.dart' show formatSigned, plural;
import '../../widgets/legend_icon.dart';
import '../../widgets/nav_entry_card.dart';
import '../../widgets/sheet_handle.dart';
import 'ranked_entity_history_screen.dart';
import 'widgets/ranked_best_legend_per_map.dart';

/// Self-contained entry point for the Legend × Map matrix: a single tappable
/// row that pushes the full-screen breakdown. The only thing a caller needs to
/// wire in; nothing else in the ranked breakdown depends on this feature.
class RankedLegendMapMatrixEntry extends StatelessWidget {
  final List<RankedMatch> matches;

  /// For the history a cell opens: reloading it, and the scope's full history
  /// its sessions are found over.
  final Future<void> Function()? onRefresh;
  final List<RankedMatch>? sessionPool;
  const RankedLegendMapMatrixEntry({
    super.key,
    required this.matches,
    this.onRefresh,
    this.sessionPool,
  });

  @override
  Widget build(BuildContext context) {
    return NavEntryCard(
      icon: Icons.grid_view_rounded,
      title: 'Legend × Map',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RankedLegendMapMatrixScreen(
            matches: matches,
            onRefresh: onRefresh,
            sessionPool: sessionPool,
          ),
        ),
      ),
    );
  }
}

/// Full-screen grid of games/avg RP per (legend, map) pair for this scope.
/// Rows and columns are only the legends/maps that were actually played —
/// see [legendMapBreakdowns] for the exact inclusion rule.
class RankedLegendMapMatrixScreen extends ConsumerWidget {
  final List<RankedMatch> matches;

  /// See [RankedLegendMapMatrixEntry].
  final Future<void> Function()? onRefresh;
  final List<RankedMatch>? sessionPool;
  const RankedLegendMapMatrixScreen({
    super.key,
    required this.matches,
    this.onRefresh,
    this.sessionPool,
  });

  /// Opens the games behind one cell as a history page.
  void _openCell(BuildContext context, LegendMapCell cell) {
    final games =
        matches
            .where(
              (m) =>
                  legendInfo(m.legend)?.name == cell.legend &&
                  battleRoyaleMapInfo(m.mapKey)?.name == cell.mapName,
            )
            .toList()
          ..sort((a, b) => b.endTime.compareTo(a.endTime));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: '${cell.legend} · ${cell.mapName}',
          subtitle:
              '${plural(cell.games, 'ranked game')} · '
              '${formatSigned(cell.avgRpPerGame)} RP/game',
          matches: games,
          onRefresh: onRefresh ?? () async {},
          sessionPool: sessionPool,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cells = legendMapBreakdowns(matches);
    // Without the live rotation (loading or offline) nothing is marked.
    final current = ref
        .watch(mapRotationProvider)
        .asData
        ?.value
        .data
        .rankedCurrent
        .map;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legend × Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How to read this',
            onPressed: () => _showInfoSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: RankedLegendMapMatrixView(
          cells: cells,
          onCellTap: (cell) => _openCell(context, cell),
          footer: RankedBestLegendPerMap(cells: cells, currentMapName: current),
        ),
      ),
    );
  }
}

void _showInfoSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: AppTheme.md),
            const Text(
              'Legend × Map',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.md),
            for (final line in [
              'Each cell is one legend on one map: games played on top, and '
                  'the average RP gained or lost per game below.',
              'A stronger colour is a bigger gain or loss. Fainter cells have '
                  'under $kMinGamesForInsight games, which says little.',
              'Tap a cell to see those games.',
              'Below the grid, the best and worst legend on each map are '
                  'picked from legends with $kMinGamesForInsight or more games '
                  'there. The map in the live ranked rotation comes first.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.sm),
                child: Text(line, style: AppTheme.captionLarge),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The grid itself, reused by [RankedLegendMapMatrixScreen] (from in-memory
/// matches) and the split-comparison tab (from a precomputed SQL breakdown for
/// a split that may not be the one currently loaded).
class RankedLegendMapMatrixView extends StatelessWidget {
  final List<LegendMapCell> cells;

  /// Shown below the grid, inside the same scroll view.
  final Widget? footer;

  /// Called when a cell is tapped; cells are not tappable without it.
  final ValueChanged<LegendMapCell>? onCellTap;
  const RankedLegendMapMatrixView({
    super.key,
    required this.cells,
    this.footer,
    this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return cells.isEmpty
        ? const _EmptyState()
        : _Matrix(cells: cells, footer: footer, onCellTap: onCellTap);
  }
}

/// How strongly a cell's tint shows, 0 to 1: more for a bigger gain or loss
/// ([avgRp] against the largest, [maxAbsRp]), and kept faint for a cell with
/// under [kMinGamesForInsight] games, which says little.
@visibleForTesting
double matrixCellStrength({
  required double avgRp,
  required int games,
  required double maxAbsRp,
}) {
  final base = maxAbsRp <= 0 ? 0.0 : (avgRp.abs() / maxAbsRp).clamp(0.0, 1.0);
  final strength = 0.1 + 0.35 * base;
  return games < kMinGamesForInsight ? strength.clamp(0.0, 0.1) : strength;
}

class _Matrix extends StatelessWidget {
  final List<LegendMapCell> cells;
  final Widget? footer;
  final ValueChanged<LegendMapCell>? onCellTap;
  const _Matrix({required this.cells, this.footer, this.onCellTap});

  @override
  Widget build(BuildContext context) {
    final byLegend = <String, List<LegendMapCell>>{};
    final legendTotals = <String, int>{};
    final mapTotals = <String, int>{};
    for (final c in cells) {
      byLegend.putIfAbsent(c.legend, () => []).add(c);
      legendTotals[c.legend] = (legendTotals[c.legend] ?? 0) + c.games;
      mapTotals[c.mapName] = (mapTotals[c.mapName] ?? 0) + c.games;
    }

    // Most-played first in both directions — the rows/columns a player cares
    // about most surface without scrolling.
    final legendOrder = byLegend.keys.toList()
      ..sort((a, b) => legendTotals[b]!.compareTo(legendTotals[a]!));
    final mapOrder = mapTotals.keys.toList()
      ..sort((a, b) => mapTotals[b]!.compareTo(mapTotals[a]!));

    // The biggest swing among cells with enough games, so one lucky game
    // doesn't wash out the rest.
    final maxAbsRp = cells
        .where((c) => c.games >= kMinGamesForInsight)
        .map((c) => c.avgRpPerGame.abs())
        .fold(0.0, (a, b) => a > b ? a : b);

    LegendMapCell? cellFor(String legend, String mapName) {
      for (final c in byLegend[legend]!) {
        if (c.mapName == mapName) return c;
      }
      return null;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const IntrinsicColumnWidth(),
              for (var i = 0; i < mapOrder.length; i++)
                i + 1: const FlexColumnWidth(),
            },
            children: [
              TableRow(
                children: [
                  const SizedBox(),
                  for (final mapName in mapOrder) _HeaderCell(mapName),
                ],
              ),
              for (final legend in legendOrder)
                TableRow(
                  children: [
                    _LegendCell(legend),
                    for (final mapName in mapOrder)
                      _ValueCell(
                        cellFor(legend, mapName),
                        maxAbsRp: maxAbsRp,
                        onTap: onCellTap,
                      ),
                  ],
                ),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: AppTheme.lg), footer!],
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.xs,
        vertical: AppTheme.sm,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LegendCell extends StatelessWidget {
  final String legend;
  const _LegendCell(this.legend);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.sm,
        horizontal: AppTheme.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LegendIcon(legendName: legend, size: 16),
          const SizedBox(width: 6),
          Text(
            legend,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final LegendMapCell? cell;
  final double maxAbsRp;
  final ValueChanged<LegendMapCell>? onTap;
  const _ValueCell(this.cell, {required this.maxAbsRp, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = cell;
    if (c == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          vertical: AppTheme.sm,
          horizontal: AppTheme.xs,
        ),
        child: Center(child: Text('–', style: AppTheme.caption)),
      );
    }
    final positive = c.avgRpPerGame >= 0;
    final color = AppTheme.signColor(positive);
    final thin = c.games < kMinGamesForInsight;
    final radius = BorderRadius.circular(AppTheme.radiusSm);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.xs,
        horizontal: AppTheme.xs,
      ),
      child: Opacity(
        opacity: thin ? 0.6 : 1,
        child: Material(
          color: color.withValues(
            alpha: matrixCellStrength(
              avgRp: c.avgRpPerGame,
              games: c.games,
              maxAbsRp: maxAbsRp,
            ),
          ),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap == null ? null : () => onTap!(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Text(
                    '${c.games}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    formatSigned(c.avgRpPerGame),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: color, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppTheme.xl),
        child: Text(
          'No games with a known legend and map in this scope yet.',
          textAlign: TextAlign.center,
          style: AppTheme.captionLarge,
        ),
      ),
    );
  }
}
