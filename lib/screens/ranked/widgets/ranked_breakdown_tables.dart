import 'package:flutter/material.dart';
import '../../../constants/ranked_map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatNumber, formatDuration;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/legend_asset_image.dart';
import '../../../widgets/stat_display.dart';
import '../../../widgets/surface_card.dart';
import '../../../widgets/win_loss_stat.dart';
import '../ranked_entity_history_screen.dart';
import 'map_rp_badge.dart';
import 'match_history_items.dart' show MatchGrouping;

enum _Sort { totalRp, games, avgRp }

const _sortLabels = {
  _Sort.totalRp: 'Total RP',
  _Sort.games: 'Games',
  _Sort.avgRp: 'Avg RP',
};

const _sortIcons = {
  _Sort.totalRp: Icons.military_tech,
  _Sort.games: Icons.tag, // sorting by *number* of games
  _Sort.avgRp: Icons.show_chart,
};

_Sort _nextSort(_Sort s) => switch (s) {
  _Sort.totalRp => _Sort.games,
  _Sort.games => _Sort.avgRp,
  _Sort.avgRp => _Sort.totalRp,
};

String _signedAvg(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';

/// Leaderboard rank chip shown beside a legend/map name. [onImage] uses a dark
/// scrim + white text so it stays legible over map artwork.
class _RankBadge extends StatelessWidget {
  final int rank;
  final bool onImage;
  const _RankBadge({required this.rank, this.onImage = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onImage ? Colors.black.withAlpha(140) : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        '#$rank',
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Legends tab ─────────────────────────────────────────────────────────────

class RankedLegendBreakdown extends StatefulWidget {
  final List<LegendBreakdown> rows;
  // The entity's ranked matches for the drill-down — resolved lazily so the
  // Lifetime tab can query one legend on tap instead of holding all history.
  final Future<List<RankedMatch>> Function(String legend) matchesFor;
  final Future<void> Function() onRefresh;

  const RankedLegendBreakdown({
    super.key,
    required this.rows,
    required this.matchesFor,
    required this.onRefresh,
  });

  @override
  State<RankedLegendBreakdown> createState() => _RankedLegendBreakdownState();
}

class _RankedLegendBreakdownState extends State<RankedLegendBreakdown> {
  _Sort _sort = _Sort.totalRp;

  @override
  Widget build(BuildContext context) {
    final rows = [...widget.rows];
    _applySort(
      rows,
      _sort,
      (r) => r.totalRp,
      (r) => r.games,
      (r) => r.avgRpPerGame,
    );

    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          _SortBar(
            selected: _sort,
            onTap: () => setState(() => _sort = _nextSort(_sort)),
          ),
          const SizedBox(height: AppTheme.sm),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.sm),
              child: _LegendCard(
                rank: i + 1,
                row: rows[i],
                onTap: () => _openHistory(context, rows[i]),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openHistory(BuildContext context, LegendBreakdown row) async {
    final games = await widget.matchesFor(row.legend)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: row.legend,
          subtitle:
              '${row.games} ranked games · ${_signedAvg(row.avgRpPerGame)} RP/game',
          matches: games,
          onRefresh: widget.onRefresh,
          groupLabel: 'map',
          grouping: MatchGrouping(
            keyOf: (m) => m.mapKey,
            nameOf: (m) => rankedMapName(m.mapKey),
          ),
        ),
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  final int rank;
  final LegendBreakdown row;
  final VoidCallback onTap;
  const _LegendCard({
    required this.rank,
    required this.row,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.surface2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Full-height portrait on the left (Stack sizes to the content child).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 96,
              child: LegendAssetImage(
                imageKey: legendImageKey(row.legend),
                displayName: row.legend,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 96),
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _RankBadge(rank: rank),
                        const SizedBox(width: AppTheme.sm),
                        Expanded(
                          child: Text(
                            row.legend,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppTheme.sm),
                        _RpPill(totalRp: row.totalRp),
                      ],
                    ),
                    const SizedBox(height: AppTheme.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: AppTheme.sm),
                            child: _AvgRpChip(avgRp: row.avgRpPerGame),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: AppTheme.sm),
                            child: WinLossStat(
                              wins: row.wins,
                              losses: row.losses,
                            ),
                          ),
                          _chip('Total Kills', formatNumber(row.totalKills)),
                          _chip('Avg Kills', row.avgKills.toStringAsFixed(1)),
                          _chip('Total Dmg', formatNumber(row.totalDamage)),
                          _chip('Avg Dmg', formatNumber(row.avgDamage.round())),
                          _chip(
                            'Total Time',
                            formatDuration(row.totalLengthSecs),
                          ),
                          _chip(
                            'Avg Time',
                            formatDuration(row.avgLengthSecs.round()),
                          ),
                          _chip('Games', '${row.games}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.only(right: AppTheme.sm),
    child: StatDisplay(label: label, value: value, highlight: highlight),
  );
}

/// Avg RP chip in the same neutral box as the other stat chips — only the
/// value itself is coloured green/red (positive/negative), not the whole box.
class _AvgRpChip extends StatelessWidget {
  final double avgRp;
  const _AvgRpChip({required this.avgRp});

  @override
  Widget build(BuildContext context) {
    final color = avgRp >= 0 ? AppTheme.green : AppTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Avg RP',
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _signedAvg(avgRp),
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _RpPill extends StatelessWidget {
  final int totalRp;
  const _RpPill({required this.totalRp});

  @override
  Widget build(BuildContext context) {
    final positive = totalRp >= 0;
    final color = positive ? AppTheme.green : AppTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        '${positive ? '+' : ''}${formatNumber(totalRp)} RP',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Maps tab ────────────────────────────────────────────────────────────────

class RankedMapBreakdown extends StatefulWidget {
  final List<MapBreakdown> rows;
  // The map's ranked matches for the drill-down — resolved lazily so the
  // Lifetime tab can query one map on tap instead of holding all history.
  final Future<List<RankedMatch>> Function(String mapKey) matchesFor;
  final Future<void> Function() onRefresh;

  const RankedMapBreakdown({
    super.key,
    required this.rows,
    required this.matchesFor,
    required this.onRefresh,
  });

  @override
  State<RankedMapBreakdown> createState() => _RankedMapBreakdownState();
}

class _RankedMapBreakdownState extends State<RankedMapBreakdown> {
  _Sort _sort = _Sort.totalRp;

  @override
  Widget build(BuildContext context) {
    final all = [...widget.rows];
    _applySort(
      all,
      _sort,
      (r) => r.totalRp,
      (r) => r.games,
      (r) => r.avgRpPerGame,
    );
    // Keep "Unknown" but always pin it to the bottom, regardless of sort.
    final known = all.where((r) => !isUnknownMapKey(r.mapKey)).toList();
    final unknown = all.where((r) => isUnknownMapKey(r.mapKey)).toList();
    final rows = [...known, ...unknown];

    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          _SortBar(
            selected: _sort,
            onTap: () => setState(() => _sort = _nextSort(_sort)),
          ),
          const SizedBox(height: AppTheme.sm),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.sm),
              child: _MapCard(
                rank: i + 1,
                row: rows[i],
                onTap: () => _openHistory(context, rows[i]),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openHistory(BuildContext context, MapBreakdown row) async {
    final games = await widget.matchesFor(row.mapKey)
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: row.displayName,
          subtitle:
              '${row.games} ranked games · ${_signedAvg(row.avgRpPerGame)} RP/game',
          matches: games,
          onRefresh: widget.onRefresh,
          groupLabel: 'legend',
          grouping: MatchGrouping(
            keyOf: (m) => m.legend,
            nameOf: (m) => m.legend,
          ),
        ),
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  final int rank;
  final MapBreakdown row;
  final VoidCallback onTap;
  const _MapCard({required this.rank, required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final positive = row.avgRpPerGame >= 0;
    final rpColor = positive ? AppTheme.green : AppTheme.red;
    final asset = rankedMapAsset(row.mapKey);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: Clip.antiAlias,
      onTap: onTap,
      child: SizedBox(
        height: 132,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              Image.asset(
                asset,
                fit: BoxFit.cover,
                cacheWidth: 800,
                errorBuilder: (_, _, _) => Container(color: AppTheme.surface2),
              )
            else
              Container(color: AppTheme.surface2),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.cardScrimTop, AppTheme.cardScrimBottom],
                ),
              ),
            ),
            Positioned(
              top: AppTheme.sm,
              right: AppTheme.sm,
              child: MapRpBadge(totalRp: row.totalRp, color: rpColor),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      _RankBadge(rank: rank, onImage: true),
                      const SizedBox(width: AppTheme.sm),
                      Flexible(
                        child: Text(
                          row.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _MapStat(
                          label: 'Avg RP',
                          value: _signedAvg(row.avgRpPerGame),
                          color: rpColor,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: AppTheme.md),
                          child: WinLossStat(
                            wins: row.wins,
                            losses: row.losses,
                            onImage: true,
                          ),
                        ),
                        _MapStat(
                          label: 'Total Kills',
                          value: formatNumber(row.totalKills),
                        ),
                        _MapStat(
                          label: 'Avg Kills',
                          value: row.avgKills.toStringAsFixed(1),
                        ),
                        _MapStat(
                          label: 'Total Dmg',
                          value: formatNumber(row.totalDamage),
                        ),
                        _MapStat(
                          label: 'Avg Dmg',
                          value: formatNumber(row.avgDamage.round()),
                        ),
                        _MapStat(
                          label: 'Total Time',
                          value: formatDuration(row.totalLengthSecs),
                        ),
                        _MapStat(
                          label: 'Avg Time',
                          value: formatDuration(row.avgLengthSecs.round()),
                        ),
                        _MapStat(label: 'Games', value: '${row.games}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MapStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared sort helpers ─────────────────────────────────────────────────────

void _applySort<T>(
  List<T> rows,
  _Sort sort,
  int Function(T) totalRp,
  int Function(T) games,
  double Function(T) avgRp,
) {
  switch (sort) {
    case _Sort.totalRp:
      rows.sort((a, b) => totalRp(b).compareTo(totalRp(a)));
    case _Sort.games:
      rows.sort((a, b) => games(b).compareTo(games(a)));
    case _Sort.avgRp:
      rows.sort((a, b) => avgRp(b).compareTo(avgRp(a)));
  }
}

/// Cycling "Sort:" pill, matching the My Stats legends sort control.
class _SortBar extends StatelessWidget {
  final _Sort selected;
  final VoidCallback onTap;
  const _SortBar({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text(
          'Sort:',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_sortIcons[selected], size: 13, color: AppTheme.accent),
                const SizedBox(width: 4),
                Text(
                  _sortLabels[selected]!,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
