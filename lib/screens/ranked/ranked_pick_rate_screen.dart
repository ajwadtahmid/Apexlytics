import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/legend_asset_image.dart';
import '../../widgets/surface_card.dart';

/// Self-contained entry point for the Pick Rate chart: a single tappable row
/// that pushes the full-screen scatter plot. The only thing a caller needs to
/// wire in; nothing else in the ranked breakdown depends on this feature.
class RankedPickRateEntry extends StatelessWidget {
  final RankedSummary summary;
  final List<LegendBreakdown> legends;
  const RankedPickRateEntry({
    super.key,
    required this.summary,
    required this.legends,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                RankedPickRateScreen(summary: summary, legends: legends),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(
                Icons.bubble_chart_outlined,
                size: 18,
                color: AppTheme.accent,
              ),
              SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  'Pick Rate',
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

enum _Quadrant { core, trap, hiddenGem, bench }

extension on _Quadrant {
  String get label => switch (this) {
    _Quadrant.core => 'Core',
    _Quadrant.trap => 'Comfort trap',
    _Quadrant.hiddenGem => 'Hidden gem',
    _Quadrant.bench => 'Bench',
  };

  Color get color => switch (this) {
    _Quadrant.core => AppTheme.green,
    _Quadrant.trap => AppTheme.orange,
    _Quadrant.hiddenGem => AppTheme.blue,
    _Quadrant.bench => AppTheme.muted,
  };
}

/// High pick rate (at/above an even split across the legends shown, i.e.
/// 1/count) crossed with RP at/above [rpBaseline]. An even-share pick-rate
/// baseline means legends played roughly equally sit together near the line
/// instead of being torn apart by rank order the way a sample median would —
/// a median always cuts the pool in half regardless of how close together the
/// actual values are. [rpBaseline] is 0 by default; a toggle lets it become
/// the player's own scope average instead, so a uniformly bad split doesn't
/// paint every legend as a comfort trap.
_Quadrant _quadrantOf(
  double pickRate,
  double avgRp,
  double equalShareRate,
  double rpBaseline,
) {
  final highPick = pickRate >= equalShareRate;
  final positive = avgRp >= rpBaseline;
  if (highPick && positive) return _Quadrant.core;
  if (highPick && !positive) return _Quadrant.trap;
  if (!highPick && positive) return _Quadrant.hiddenGem;
  return _Quadrant.bench;
}

/// Full-screen scatter plot: pick rate (× of games in scope) against average
/// RP/game, one dot per legend, colored by which of the four
/// pick-rate/RP-sign quadrants it falls in. Tapping a dot fills in the detail
/// card below the chart rather than opening a popup, so several legends can be
/// compared in a row without dismissing anything.
class RankedPickRateScreen extends StatefulWidget {
  final RankedSummary summary;
  final List<LegendBreakdown> legends;
  const RankedPickRateScreen({
    super.key,
    required this.summary,
    required this.legends,
  });

  @override
  State<RankedPickRateScreen> createState() => _RankedPickRateScreenState();
}

class _RankedPickRateScreenState extends State<RankedPickRateScreen> {
  bool _showAll = false;
  bool _useOwnAverageBaseline = false;
  bool _tableView = false;
  LegendBreakdown? _selected;

  @override
  Widget build(BuildContext context) {
    final total = widget.summary.games;
    final pool = _showAll
        ? widget.legends
        : widget.legends.where((l) => l.games >= kMinGamesForInsight).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Rate'),
        actions: [
          IconButton(
            icon: Icon(
              _tableView
                  ? Icons.bubble_chart_outlined
                  : Icons.table_rows_outlined,
            ),
            tooltip: _tableView ? 'Show chart' : 'Show table',
            onPressed: () => setState(() => _tableView = !_tableView),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customize',
            onPressed: () => _showCustomizeSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: total == 0 || pool.isEmpty
            ? _EmptyState(
                showingAll: _showAll,
                onShowAll: () => setState(() => _showAll = true),
              )
            : _tableView
            ? _LegendStatsTable(pool: pool, totalGames: total)
            : _buildBody(pool, total),
      ),
    );
  }

  void _showCustomizeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      builder: (_) => _CustomizeSheet(
        showAll: _showAll,
        useOwnAverage: _useOwnAverageBaseline,
        ownAverage: widget.summary.avgRpPerGame,
        onShowAllChanged: (v) => setState(() {
          _showAll = v;
          _selected = null;
        }),
        onUseOwnAverageChanged: (v) =>
            setState(() => _useOwnAverageBaseline = v),
      ),
    );
  }

  Widget _buildBody(List<LegendBreakdown> pool, int total) {
    final pickRateOf = {for (final l in pool) l.legend: l.games / total};
    final equalShareRate = 1 / pool.length;
    final rpBaseline = _useOwnAverageBaseline
        ? widget.summary.avgRpPerGame
        : 0.0;
    final maxAbsRp = pool
        .map((l) => l.avgRpPerGame.abs())
        .fold(10.0, (a, b) => a > b ? a : b);
    final yBound = maxAbsRp * 1.2;
    // Pick rate rarely approaches 100% once a player rotates between more than
    // one legend, so a fixed 0–100 domain leaves most of the chart empty.
    // Scale to the widest pick rate actually in the pool instead, same as the
    // RP axis above.
    final maxPickRatePct = pickRateOf.values
        .map((r) => r * 100)
        .fold(10.0, (a, b) => a > b ? a : b);
    final xBound = maxPickRatePct * 1.2;

    final spots = [
      for (final l in pool)
        ScatterSpot(
          pickRateOf[l.legend]! * 100,
          l.avgRpPerGame,
          dotPainter: FlDotCirclePainter(
            radius: 7,
            color: _quadrantOf(
              pickRateOf[l.legend]!,
              l.avgRpPerGame,
              equalShareRate,
              rpBaseline,
            ).color,
          ),
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 260,
            child: ScatterChart(
              ScatterChartData(
                minX: 0,
                maxX: xBound,
                minY: -yBound,
                maxY: yBound,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                scatterSpots: spots,
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, _) => Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, _) => Text(
                        '${value.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ),
                scatterTouchData: ScatterTouchData(
                  handleBuiltInTouches: false,
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    final index = response?.touchedSpot?.spotIndex;
                    if (index == null) return;
                    setState(() => _selected = pool[index]);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.md),
          const _QuadrantKey(),
          const SizedBox(height: AppTheme.md),
          _SelectedDetail(
            legend: _selected,
            pickRate: _selected == null ? null : pickRateOf[_selected!.legend],
          ),
        ],
      ),
    );
  }
}

/// Both chart settings, kept out of the main screen so someone who just wants
/// to glance at their pick-rate spread never sees a toggle at all. Mirrors the
/// state up via callbacks (into [_RankedPickRateScreenState]) while also
/// tracking it locally so its own switches update immediately without
/// waiting for the underlying chart to rebuild.
class _CustomizeSheet extends StatefulWidget {
  final bool showAll;
  final bool useOwnAverage;
  final double ownAverage;
  final ValueChanged<bool> onShowAllChanged;
  final ValueChanged<bool> onUseOwnAverageChanged;

  const _CustomizeSheet({
    required this.showAll,
    required this.useOwnAverage,
    required this.ownAverage,
    required this.onShowAllChanged,
    required this.onUseOwnAverageChanged,
  });

  @override
  State<_CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<_CustomizeSheet> {
  late bool _showAll;
  late bool _useOwnAverage;

  @override
  void initState() {
    super.initState();
    _showAll = widget.showAll;
    _useOwnAverage = widget.useOwnAverage;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customize',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.md),
            _OptionRow(
              title: 'Minimum games',
              subtitle: _showAll
                  ? "Showing every legend you've played"
                  : 'Showing legends with at least $kMinGamesForInsight games',
              value: _showAll,
              onChanged: (v) {
                setState(() => _showAll = v);
                widget.onShowAllChanged(v);
              },
            ),
            const SizedBox(height: AppTheme.md),
            _OptionRow(
              title: 'What counts as "good"',
              subtitle: _useOwnAverage
                  ? 'Comparing against your average this scope '
                        '(${widget.ownAverage >= 0 ? '+' : ''}'
                        '${widget.ownAverage.toStringAsFixed(1)} RP/game)'
                  : 'Comparing against 0 RP/game — turn on to compare '
                        "against your own average instead, so a rough split "
                        "doesn't paint every legend as a comfort trap",
              value: _useOwnAverage,
              onChanged: (v) {
                setState(() => _useOwnAverage = v);
                widget.onUseOwnAverageChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OptionRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppTheme.sm),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _QuadrantKey extends StatelessWidget {
  const _QuadrantKey();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTheme.md,
      runSpacing: 6,
      children: [for (final q in _Quadrant.values) _KeyChip(q)],
    );
  }
}

class _KeyChip extends StatelessWidget {
  final _Quadrant quadrant;
  const _KeyChip(this.quadrant);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: quadrant.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          quadrant.label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _SelectedDetail extends StatelessWidget {
  final LegendBreakdown? legend;
  final double? pickRate;
  const _SelectedDetail({required this.legend, required this.pickRate});

  @override
  Widget build(BuildContext context) {
    final l = legend;
    if (l == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.md),
        child: Center(
          child: Text(
            'Tap a legend to see details',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
        ),
      );
    }
    final rate = pickRate ?? 0;
    final positive = l.avgRpPerGame >= 0;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: SizedBox(
              width: 40,
              height: 40,
              child: LegendAssetImage(
                imageKey: legendImageKey(l.legend),
                displayName: l.legend,
                fallbackFontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.legend,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(rate * 100).toStringAsFixed(1)}% pick rate · '
                  '${(l.winRate * 100).toStringAsFixed(0)}% win rate · '
                  '${l.games} games',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${l.avgRpPerGame.toStringAsFixed(1)} RP/game',
            style: TextStyle(
              color: positive ? AppTheme.green : AppTheme.red,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Table alternative to the scatter chart: one row per legend, sorted by pick
/// rate descending, showing pick rate, win rate, and avg RP gain/loss side by
/// side — for a precise read of the same pool the chart plots.
class _LegendStatsTable extends StatelessWidget {
  final List<LegendBreakdown> pool;
  final int totalGames;

  const _LegendStatsTable({required this.pool, required this.totalGames});

  @override
  Widget build(BuildContext context) {
    final sorted = [...pool]..sort((a, b) => b.games.compareTo(a.games));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.md),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.sm),
              child: Row(
                children: [
                  Expanded(flex: 2, child: SizedBox()),
                  Expanded(
                    child: Text(
                      'GAMES',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'PICK',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'WIN',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'RP/GAME',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.surface2, height: 1),
            for (final l in sorted)
              _LegendStatsRow(legend: l, totalGames: totalGames),
          ],
        ),
      ),
    );
  }
}

class _LegendStatsRow extends StatelessWidget {
  final LegendBreakdown legend;
  final int totalGames;

  const _LegendStatsRow({required this.legend, required this.totalGames});

  @override
  Widget build(BuildContext context) {
    final pickRate = totalGames == 0 ? 0.0 : legend.games / totalGames;
    final positive = legend.avgRpPerGame >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              legend.legend,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              '${legend.games}',
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              '${(pickRate * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              '${(legend.winRate * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              '${positive ? '+' : ''}${legend.avgRpPerGame.toStringAsFixed(1)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: positive ? AppTheme.green : AppTheme.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool showingAll;
  final VoidCallback onShowAll;
  const _EmptyState({required this.showingAll, required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Not enough ranked games yet to show a pick rate chart.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            if (!showingAll) ...[
              const SizedBox(height: AppTheme.sm),
              TextButton(
                onPressed: onShowAll,
                child: const Text('Show all legends'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
