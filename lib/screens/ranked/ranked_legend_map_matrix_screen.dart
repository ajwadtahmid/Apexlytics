import 'package:flutter/material.dart';
import '../../models/ranked_match.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';

/// Self-contained entry point for the Legend × Map matrix: a single tappable
/// row that pushes the full-screen breakdown. The only thing a caller needs to
/// wire in; nothing else in the ranked breakdown depends on this feature.
class RankedLegendMapMatrixEntry extends StatelessWidget {
  final List<RankedMatch> matches;
  const RankedLegendMapMatrixEntry({super.key, required this.matches});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedLegendMapMatrixScreen(matches: matches),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(Icons.grid_view_rounded, size: 18, color: AppTheme.accent),
              SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  'Legend × Map',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen grid of games/avg RP per (legend, map) pair for this scope.
/// Rows and columns are only the legends/maps that were actually played —
/// see [legendMapBreakdowns] for the exact inclusion rule.
class RankedLegendMapMatrixScreen extends StatelessWidget {
  final List<RankedMatch> matches;
  const RankedLegendMapMatrixScreen({super.key, required this.matches});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legend × Map')),
      body: SafeArea(
        child: RankedLegendMapMatrixView(cells: legendMapBreakdowns(matches)),
      ),
    );
  }
}

/// The grid itself, reused by [RankedLegendMapMatrixScreen] (from in-memory
/// matches) and the split-comparison tab (from a precomputed SQL breakdown for
/// a split that may not be the one currently loaded).
class RankedLegendMapMatrixView extends StatelessWidget {
  final List<LegendMapCell> cells;
  const RankedLegendMapMatrixView({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    return cells.isEmpty ? const _EmptyState() : _Matrix(cells: cells);
  }
}

class _Matrix extends StatelessWidget {
  final List<LegendMapCell> cells;
  const _Matrix({required this.cells});

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
          const Padding(
            padding: EdgeInsets.only(bottom: AppTheme.md),
            child: Text(
              'Ranked games broken down by legend and map.\n'
              'Each cell: games played on top, avg RP gain/loss per game on '
              'bottom.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
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
                      _ValueCell(cellFor(legend, mapName)),
                  ],
                ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        label,
        textAlign: TextAlign.center,
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        legend,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final LegendMapCell? cell;
  const _ValueCell(this.cell);

  @override
  Widget build(BuildContext context) {
    final c = cell;
    if (c == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Center(
          child: Text(
            '–',
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ),
      );
    }
    final positive = c.avgRpPerGame >= 0;
    final color = AppTheme.signColor(positive);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
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
              '${positive ? '+' : ''}${c.avgRpPerGame.toStringAsFixed(1)}',
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
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
          style: TextStyle(color: AppTheme.muted, fontSize: 13),
        ),
      ),
    );
  }
}
