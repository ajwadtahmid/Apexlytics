import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/legend_constants.dart' show legendInfo;
import '../../constants/map_constants.dart' show battleRoyaleMapInfo;
import '../../models/ranked_match.dart';
import '../../providers/best_metric_provider.dart';
import '../../providers/map_provider.dart';
import '../../utils/ranked/matrix_totals.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../utils/formatting/format.dart' show formatSigned, plural;
import '../../widgets/legend_icon.dart';
import '../../widgets/nav_entry_card.dart';
import '../../widgets/segmented_capsule.dart';
import '../../widgets/info_sheet.dart';
import 'ranked_entity_history_screen.dart';
import 'widgets/ranked_best_legend_per_map.dart';

/// Self-contained entry point for the Legend × Map matrix: a single tappable
/// row that pushes the full-screen breakdown. The only thing a caller needs to
/// wire in; nothing else in Stats depends on this feature.
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

  /// Opens the games behind one cell as a history page. A total cell
  /// ([kMatrixAll] for its legend or its map) covers that whole row or column,
  /// but only games the grid itself counts, so the numbers agree.
  void _openCell(BuildContext context, LegendMapCell cell) {
    final anyLegend = cell.legend == kMatrixAll;
    final anyMap = cell.mapName == kMatrixAll;
    final games = matches.where((m) {
      final legend = legendInfo(m.legend)?.name;
      final map = battleRoyaleMapInfo(m.mapKey)?.name;
      if (legend == null || map == null) return false;
      return (anyLegend || legend == cell.legend) &&
          (anyMap || map == cell.mapName);
    }).toList()..sort((a, b) => b.endTime.compareTo(a.endTime));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title:
              '${anyLegend ? 'All legends' : cell.legend} · '
              '${anyMap ? 'All maps' : cell.mapName}',
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
          footer: RankedBestLegendPerMap(
            cells: cells,
            currentMapName: current,
            metric: ref.watch(bestMetricProvider),
          ),
        ),
      ),
    );
  }
}

void _showInfoSheet(BuildContext context) => showInfoSheet(
  context,
  title: 'Legend × Map',
  lines: [
    'Each cell is one legend on one map: games played on top, and '
        'the average RP gained or lost per game below.',
    'A stronger colour is a bigger gain or loss. Fainter cells have '
        'under $kMinGamesForInsight games, which says little.',
    'Tap a cell to see those games.',
    'The All row and column add up each map and each legend, and '
        'tapping one shows those games.',
    'The chips above the grid order the legends and maps by games '
        'played, RP per game, or name. Best RP puts those with only a '
        'few games last.',
    'Below the grid, the best and worst legend on each map are '
        'picked from legends with $kMinGamesForInsight or more games '
        'there. The map in the live ranked rotation comes first.',
  ],
);

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

class _Matrix extends StatefulWidget {
  final List<LegendMapCell> cells;
  final Widget? footer;
  final ValueChanged<LegendMapCell>? onCellTap;
  const _Matrix({required this.cells, this.footer, this.onCellTap});

  @override
  State<_Matrix> createState() => _MatrixState();
}

class _MatrixState extends State<_Matrix> {
  MatrixSort _sort = MatrixSort.mostPlayed;

  @override
  Widget build(BuildContext context) {
    final cells = widget.cells;
    final onCellTap = widget.onCellTap;
    final byPair = {for (final c in cells) (c.legend, c.mapName): c};
    final totals = matrixTotals(cells);
    final legendOrder = orderedMatrixNames(totals.byLegend, _sort);
    final mapOrder = orderedMatrixNames(totals.byMap, _sort);
    // With one map the All column would repeat it, and likewise one legend.
    final allColumn = mapOrder.length > 1;
    final allRow = legendOrder.length > 1;

    // The biggest swing among cells with enough games, so one lucky game
    // doesn't wash out the rest.
    final maxAbsRp = cells
        .where((c) => c.games >= kMinGamesForInsight)
        .map((c) => c.avgRpPerGame.abs())
        .fold(0.0, (a, b) => a > b ? a : b);

    Widget value(LegendMapCell? cell, String legend, String map) => _ValueCell(
      cell,
      key: ValueKey('cell|$legend|$map'),
      maxAbsRp: maxAbsRp,
      onTap: onCellTap,
    );

    final columns = mapOrder.length + (allColumn ? 2 : 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (legendOrder.length > 1 || mapOrder.length > 1) ...[
            Center(
              child: SegmentedCapsule(
                options: [for (final s in MatrixSort.values) s.label],
                selected: _sort.index,
                onChanged: (i) => setState(() => _sort = MatrixSort.values[i]),
              ),
            ),
            const SizedBox(height: AppTheme.md),
          ],
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const IntrinsicColumnWidth(),
              for (var i = 0; i < mapOrder.length; i++)
                i + 1: const FlexColumnWidth(),
              if (allColumn) ...{
                mapOrder.length + 1: const FixedColumnWidth(1),
                mapOrder.length + 2: const FlexColumnWidth(),
              },
            },
            children: [
              TableRow(
                children: [
                  const SizedBox(),
                  for (final mapName in mapOrder) _HeaderCell(mapName),
                  if (allColumn) ...[
                    const _VerticalRule(),
                    const _HeaderCell(kMatrixAll, strong: true),
                  ],
                ],
              ),
              for (final legend in legendOrder)
                TableRow(
                  children: [
                    _LegendCell(legend),
                    for (final mapName in mapOrder)
                      value(byPair[(legend, mapName)], legend, mapName),
                    if (allColumn) ...[
                      const _VerticalRule(),
                      value(totals.byLegend[legend], legend, kMatrixAll),
                    ],
                  ],
                ),
              if (allRow) ...[
                TableRow(
                  children: [
                    for (var i = 0; i < columns + 1; i++)
                      const _HorizontalRule(),
                  ],
                ),
                TableRow(
                  children: [
                    const _AllLabel(),
                    for (final mapName in mapOrder)
                      value(totals.byMap[mapName], kMatrixAll, mapName),
                    if (allColumn) ...[
                      const _VerticalRule(),
                      value(totals.grand, kMatrixAll, kMatrixAll),
                    ],
                  ],
                ),
              ],
            ],
          ),
          if (widget.footer != null) ...[
            const SizedBox(height: AppTheme.lg),
            widget.footer!,
          ],
        ],
      ),
    );
  }
}

/// The faint line that sets the All column and row apart from the grid.
final _ruleColor = AppTheme.muted.withValues(alpha: 0.35);

class _VerticalRule extends StatelessWidget {
  const _VerticalRule();

  @override
  Widget build(BuildContext context) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.fill,
      child: Center(
        child: SizedBox(
          width: 1,
          height: double.infinity,
          child: ColoredBox(color: _ruleColor),
        ),
      ),
    );
  }
}

class _HorizontalRule extends StatelessWidget {
  const _HorizontalRule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.xs),
      child: SizedBox(height: 1, child: ColoredBox(color: _ruleColor)),
    );
  }
}

/// The label at the left of the All row.
class _AllLabel extends StatelessWidget {
  const _AllLabel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppTheme.sm,
        horizontal: AppTheme.xs,
      ),
      child: Text(
        kMatrixAll,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;

  /// Brighter, for the All column.
  final bool strong;
  const _HeaderCell(this.label, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 1,
        vertical: AppTheme.sm,
      ),
      // Two-word names break at the space and shrink to fit, so a narrow
      // column shows the whole name rather than a clipped one.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label.replaceFirst(' ', '\n'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: strong ? AppTheme.textPrimary : AppTheme.muted,
            fontSize: 10,
            fontWeight: strong ? FontWeight.bold : FontWeight.w600,
          ),
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
  const _ValueCell(this.cell, {super.key, required this.maxAbsRp, this.onTap});

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
              // Scales down rather than crowding the next column when there
              // are many maps or large text.
              child: FittedBox(
                fit: BoxFit.scaleDown,
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
