import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ranked_match.dart';
import '../../providers/pick_rate_options_provider.dart';
import '../../utils/ranked/label_placement.dart';
import '../../utils/ranked/legend_table_sort.dart';
import '../../utils/ranked/pick_rate_quadrants.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/legend_asset_image.dart';
import '../../widgets/stat_display.dart';
import '../../widgets/surface_card.dart';
import '../../utils/formatting/format.dart'
    show
        plural,
        formatSigned,
        formatSignedInt,
        formatPercent,
        formatAvgKills,
        formatAvgDamage;
import '../../widgets/nav_entry_card.dart';
import '../../widgets/segmented_capsule.dart';
import '../../widgets/info_sheet.dart';
import 'widgets/ranked_legend_detail_sheet.dart' show openLegendHistory;

/// Self-contained entry point for the Pick Rate chart: a single tappable row
/// that pushes the full-screen scatter plot. The only thing a caller needs to
/// wire in; nothing else in the ranked breakdown depends on this feature.
class RankedPickRateEntry extends StatelessWidget {
  final RankedSummary summary;
  final List<LegendBreakdown> legends;

  /// What opening a legend's history needs; without them the legend card on the
  /// screen is not tappable.
  final Future<List<RankedMatch>> Function(String legend)? matchesFor;
  final Future<void> Function()? onRefresh;
  final List<RankedMatch>? sessionPool;
  const RankedPickRateEntry({
    super.key,
    required this.summary,
    required this.legends,
    this.matchesFor,
    this.onRefresh,
    this.sessionPool,
  });

  @override
  Widget build(BuildContext context) {
    return NavEntryCard(
      icon: Icons.bubble_chart_outlined,
      title: 'Pick Rate',
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedPickRateScreen(
              summary: summary,
              legends: legends,
              matchesFor: matchesFor,
              onRefresh: onRefresh,
              sessionPool: sessionPool,
            ),
          ),
        ),
    );
  }
}

extension on PickRateQuadrant {
  Color get color => switch (this) {
    PickRateQuadrant.core => AppTheme.green,
    PickRateQuadrant.trap => AppTheme.orange,
    PickRateQuadrant.hiddenGem => AppTheme.blue,
    PickRateQuadrant.bench => AppTheme.muted,
  };
}

/// The pick rate that counts as "high": what each legend in the pool would have
/// if the pool's games were split evenly.
///
/// Pick rates are shares of *all* games ([totalGames]), so the line is the
/// pool's share divided by [poolSize], not 1/[poolSize] (which would sit above
/// every rate once a hidden legend took some games). One division, so a legend
/// at exactly the even share compares equal.
@visibleForTesting
double equalSharePickRate({
  required int poolGames,
  required int totalGames,
  required int poolSize,
}) => poolGames / (totalGames * poolSize);

/// Full-screen scatter plot: pick rate (× of games in scope) against average
/// RP/game, one dot per legend, colored by which of the four
/// pick-rate/RP-sign quadrants it falls in. Tapping a dot fills in the detail
/// card below the chart rather than opening a popup, so several legends can be
/// compared in a row without dismissing anything.
class RankedPickRateScreen extends ConsumerStatefulWidget {
  final RankedSummary summary;
  final List<LegendBreakdown> legends;

  /// See [RankedPickRateEntry].
  final Future<List<RankedMatch>> Function(String legend)? matchesFor;
  final Future<void> Function()? onRefresh;
  final List<RankedMatch>? sessionPool;
  const RankedPickRateScreen({
    super.key,
    required this.summary,
    required this.legends,
    this.matchesFor,
    this.onRefresh,
    this.sessionPool,
  });

  @override
  ConsumerState<RankedPickRateScreen> createState() =>
      _RankedPickRateScreenState();
}

class _RankedPickRateScreenState extends ConsumerState<RankedPickRateScreen> {
  bool get _showAll => ref.watch(pickRateOptionsProvider).showAll;
  bool get _useOwnAverageBaseline =>
      ref.watch(pickRateOptionsProvider).useOwnAverage;
  bool get _tableView => ref.watch(pickRateOptionsProvider).tableView;
  LegendBreakdown? _selected;

  /// Each looked-up legend's maps, kept so reselecting it doesn't ask again.
  final Map<String, List<LegendMapCell>> _mapCells = {};

  /// Selects [legend] and, once, loads its games for the best and worst map.
  Future<void> _select(LegendBreakdown legend) async {
    setState(() => _selected = legend);
    final lookup = widget.matchesFor;
    if (lookup == null || _mapCells.containsKey(legend.legend)) return;
    final games = await lookup(legend.legend);
    if (!mounted) return;
    setState(() => _mapCells[legend.legend] = legendMapBreakdowns(games));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.summary.games;
    final pool = pickRatePool(widget.legends, showAll: _showAll);
    // What was selected may have just been filtered out.
    ref.listen(pickRateOptionsProvider, (before, now) {
      if (before?.showAll != now.showAll) setState(() => _selected = null);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Rate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customize',
            onPressed: () => _showCustomizeSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How to read this',
            onPressed: () => _showInfoSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: total == 0 || pool.isEmpty
            ? _EmptyState(
                showingAll: _showAll,
                onShowAll: () =>
                    ref.read(pickRateOptionsProvider.notifier).setShowAll(true),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.md,
                      AppTheme.sm,
                      AppTheme.md,
                      0,
                    ),
                    child: SegmentedCapsule(
                      options: const ['Chart', 'Table'],
                      selected: _tableView ? 1 : 0,
                      onChanged: (i) => ref
                          .read(pickRateOptionsProvider.notifier)
                          .setTableView(i == 1),
                    ),
                  ),
                  Expanded(
                    child: _tableView
                        ? _buildTable(pool, total)
                        : _buildBody(pool, total),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _openHistory(LegendBreakdown legend) async {
    final games = [...await widget.matchesFor!(legend.legend)]
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (!mounted) return;
    openLegendHistory(
      context,
      legend,
      games,
      widget.onRefresh ?? () async {},
      sessionPool: widget.sessionPool,
    );
  }

  void _showCustomizeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomizeSheet(
        legends: widget.legends,
        totalGames: widget.summary.games,
        ownAverage: widget.summary.avgRpPerGame,
      ),
    );
  }

  Widget _buildTable(List<LegendBreakdown> pool, int total) {
    final selected = _selected;
    return Column(
      children: [
        Expanded(
          child: _LegendStatsTable(
            pool: pool,
            totalGames: total,
            selected: selected?.legend,
            onSelect: _select,
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.md,
              0,
              AppTheme.md,
              AppTheme.md,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: SingleChildScrollView(
                child: _detail(selected.games / total),
              ),
            ),
          ),
      ],
    );
  }

  Widget _detail(double? pickRate) => _SelectedDetail(
    legend: _selected,
    pickRate: pickRate,
    maps: _selected == null ? null : _mapCells[_selected!.legend],
    onOpen: widget.matchesFor == null ? null : _openHistory,
  );

  Widget _buildBody(List<LegendBreakdown> pool, int total) {
    final pickRateOf = {for (final l in pool) l.legend: l.games / total};
    final equalShareRate = equalSharePickRate(
      poolGames: pool.fold(0, (sum, l) => sum + l.games),
      totalGames: total,
      poolSize: pool.length,
    );
    final rpBaseline = _useOwnAverageBaseline
        ? widget.summary.avgRpPerGame
        : 0.0;
    final maxAbsRp = pool
        .map((l) => l.avgRpPerGame.abs())
        .fold(10.0, (a, b) => a > b ? a : b);
    // Bounds are whole steps, so the axis ends on a labelled tick instead of
    // a stray number crowding the last one.
    final yStep = niceAxisStep(maxAbsRp * 2.2, ticks: 8);
    final yBound = (maxAbsRp * 1.1 / yStep).ceil() * yStep;
    // Pick rate rarely approaches 100% once a player rotates between more than
    // one legend, so a fixed 0–100 domain leaves most of the chart empty.
    // Scale to the widest pick rate actually in the pool instead, same as the
    // RP axis above.
    final maxPickRatePct = pickRateOf.values
        .map((r) => r * 100)
        .fold(10.0, (a, b) => a > b ? a : b);
    final xStep = niceAxisStep(maxPickRatePct * 1.1, ticks: 6);
    final xBound = (maxPickRatePct * 1.1 / xStep).ceil() * xStep;

    final spots = [
      for (final l in pool)
        ScatterSpot(
          pickRateOf[l.legend]! * 100,
          l.avgRpPerGame,
          dotPainter: FlDotCirclePainter(
            radius: 7,
            color: quadrantOf(
              pickRateOf[l.legend]!,
              l.avgRpPerGame,
              equalShareRate,
              rpBaseline,
            ).color,
          ),
        ),
    ];

    final takeaways = pickRateTakeaways(
      pool: pool,
      totalGames: total,
      equalShareRate: equalShareRate,
      rpBaseline: rpBaseline,
    );
    // Most-played first, so they get the best spots for their labels.
    final byGames = [for (final i in List.generate(pool.length, (i) => i)) i]
      ..sort((a, b) => pool[b].games.compareTo(pool[a].games));
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.3);
    final labelStyle = Theme.of(context).textTheme.bodySmall!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (takeaways.isNotEmpty) ...[
            _Takeaways(items: takeaways, onSelect: _select),
            const SizedBox(height: AppTheme.md),
          ],
          const Text('Avg RP per game', style: AppTheme.captionSmall),
          const SizedBox(height: AppTheme.xs),
          SizedBox(
            height: 260,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _GuidesPainter(
                    xBound: xBound,
                    yBound: yBound,
                    splitX: equalShareRate * 100,
                    splitY: rpBaseline,
                  ),
                ),
                ScatterChart(
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
                          interval: yStep,
                          reservedSize: _Plot.left,
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
                          interval: xStep,
                          reservedSize: _Plot.bottom,
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
                        _select(pool[index]);
                      },
                    ),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _LabelsPainter(
                      names: [for (final l in pool) l.legend],
                      points: [
                        for (final l in pool)
                          Offset(pickRateOf[l.legend]! * 100, l.avgRpPerGame),
                      ],
                      order: byGames,
                      selected: _selected?.legend,
                      xBound: xBound,
                      yBound: yBound,
                      textScaler: textScaler,
                      style: labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Center(
            child: Text('Share of your games', style: AppTheme.captionSmall),
          ),
          const SizedBox(height: AppTheme.sm),
          Text(
            'Dashed lines: an even share of games '
            '(${formatPercent(equalShareRate, decimals: 0)}) and '
            '${_useOwnAverageBaseline ? 'your average of '
                      '${formatSigned(rpBaseline)} RP per game' : '0 RP per game'}.',
            style: AppTheme.captionSmall,
          ),
          const SizedBox(height: AppTheme.md),
          const _QuadrantKey(),
          const SizedBox(height: AppTheme.md),
          _detail(_selected == null ? null : pickRateOf[_selected!.legend]),
        ],
      ),
    );
  }
}

/// A round axis step (1, 2 or 5 times a power of ten) that gives about [ticks]
/// marks over [range].
@visibleForTesting
double niceAxisStep(double range, {required int ticks}) {
  final raw = range / ticks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
  for (final m in const [1, 2, 5]) {
    if (m * magnitude >= raw) return (m * magnitude).toDouble();
  }
  return (10 * magnitude).toDouble();
}

/// Where the chart's plot area sits inside its box, and how data maps onto it:
/// the box less the room the axis numbers take on the left and bottom. The
/// guides and labels are painted on their own layers, so they need the same
/// mapping the chart itself uses.
class _Plot {
  static const left = 32.0;
  static const bottom = 22.0;

  final Rect rect;
  final double xBound;
  final double yBound;

  _Plot(Size size, this.xBound, this.yBound)
    : rect = Rect.fromLTRB(left, 0, size.width, size.height - bottom);

  /// Pixel position of pick rate [x] (percent) and RP per game [y].
  Offset at(double x, double y) => Offset(
    rect.left + x / xBound * rect.width,
    rect.bottom - (y + yBound) / (2 * yBound) * rect.height,
  );
}

/// Behind the dots: the four quadrants faintly tinted, split by dashed lines at
/// the even share of games ([splitX], percent) and the RP baseline ([splitY]).
class _GuidesPainter extends CustomPainter {
  final double xBound;
  final double yBound;
  final double splitX;
  final double splitY;

  const _GuidesPainter({
    required this.xBound,
    required this.yBound,
    required this.splitX,
    required this.splitY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _Plot(size, xBound, yBound);
    final r = plot.rect;
    final x = plot.at(splitX, 0).dx.clamp(r.left, r.right);
    final y = plot.at(0, splitY).dy.clamp(r.top, r.bottom);

    void tint(Rect area, PickRateQuadrant q) =>
        canvas.drawRect(area, Paint()..color = q.color.withValues(alpha: 0.07));
    tint(Rect.fromLTRB(x, r.top, r.right, y), PickRateQuadrant.core);
    tint(Rect.fromLTRB(x, y, r.right, r.bottom), PickRateQuadrant.trap);
    tint(Rect.fromLTRB(r.left, r.top, x, y), PickRateQuadrant.hiddenGem);
    tint(Rect.fromLTRB(r.left, y, x, r.bottom), PickRateQuadrant.bench);

    final line = Paint()
      ..color = AppTheme.muted.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    _dashed(canvas, Offset(x, r.top), Offset(x, r.bottom), line);
    _dashed(canvas, Offset(r.left, y), Offset(r.right, y), line);
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    final length = (b - a).distance;
    final step = (b - a) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      final end = d + dash > length ? length : d + dash;
      canvas.drawLine(a + step * d, a + step * end, paint);
    }
  }

  @override
  bool shouldRepaint(_GuidesPainter old) =>
      old.xBound != xBound ||
      old.yBound != yBound ||
      old.splitX != splitX ||
      old.splitY != splitY;
}

/// Over the dots: each legend's name beside its dot, on a side that doesn't
/// run into another dot or label. [points] are pick rate (percent) and RP per
/// game; [order] is the legends most worth labelling first.
class _LabelsPainter extends CustomPainter {
  final List<String> names;
  final List<Offset> points;
  final List<int> order;
  final String? selected;
  final double xBound;
  final double yBound;
  final TextScaler textScaler;

  /// The screen's text style, so the names use the same font as everything else.
  final TextStyle style;

  const _LabelsPainter({
    required this.names,
    required this.points,
    required this.order,
    required this.selected,
    required this.xBound,
    required this.yBound,
    required this.textScaler,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plot = _Plot(size, xBound, yBound);
    final texts = [
      for (final i in order)
        TextPainter(
          text: TextSpan(
            text: names[i],
            style: style.copyWith(
              color: names[i] == selected
                  ? AppTheme.textPrimary
                  : AppTheme.textPrimary.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: names[i] == selected
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          maxLines: 1,
        )..layout(),
    ];
    final spots = placeLabels(
      centers: [for (final i in order) plot.at(points[i].dx, points[i].dy)],
      sizes: [for (final t in texts) t.size],
      bounds: Offset.zero & size,
    );
    for (final (k, rect) in spots.indexed) {
      if (rect != null) texts[k].paint(canvas, rect.topLeft);
    }
  }

  @override
  bool shouldRepaint(_LabelsPainter old) =>
      old.names != names ||
      old.points != points ||
      old.selected != selected ||
      old.xBound != xBound ||
      old.yBound != yBound ||
      old.textScaler != textScaler ||
      old.style != style;
}

/// The legends worth a look, in words, above the chart. Tapping one selects it.
class _Takeaways extends StatelessWidget {
  final List<PickRateTakeaway> items;
  final ValueChanged<LegendBreakdown> onSelect;
  const _Takeaways({required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: AppTheme.sm,
      ),
      child: Column(
        children: [
          for (final t in items)
            InkWell(
              onTap: () => onSelect(t.legend),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: t.quadrant.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${t.quadrant.label}  ',
                                  style: TextStyle(
                                    color: t.quadrant.color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: t.legend.legend,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${formatPercent(t.pickRate, decimals: 0)} of your '
                            'games at ${formatSigned(t.legend.avgRpPerGame)} '
                            'RP per game',
                            style: AppTheme.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
void _showInfoSheet(BuildContext context) => showInfoSheet(
  context,
  title: 'Pick Rate',
  lines: [
    'Each dot is a legend: further right means you play it more, '
        'higher means it earns more RP per game.',
    'The dashed lines mark an even share of your games and the RP '
        'line (0, or your average in Customize). Core is played a '
        'lot and gains RP, a comfort trap is played a lot but loses '
        'RP, a hidden gem is played less but gains, and bench is '
        'played less and loses.',
    'Legends with under $kMinGamesForInsight games are left out '
        'until you choose All in Customize.',
    'Tap a dot, or a row in the table, to see that legend. Tap its '
        'card to open its games. In the table, tap a heading to '
        'sort.',
  ],
);

class _CustomizeSheet extends ConsumerWidget {
  final List<LegendBreakdown> legends;
  final int totalGames;
  final double ownAverage;

  const _CustomizeSheet({
    required this.legends,
    required this.totalGames,
    required this.ownAverage,
  });

  /// What the "Legends shown" choice does right now.
  String _shownNote(bool showAll) {
    final total = legends.length;
    final underMin = total - pickRatePool(legends, showAll: false).length;
    if (underMin == 0) {
      return "Every legend you've played has at least $kMinGamesForInsight "
          'games, so none are hidden.';
    }
    final few =
        '${plural(underMin, 'legend')} with under '
        '$kMinGamesForInsight games';
    return showAll
        ? 'Including $few. Their averages can swing a lot.'
        : 'Showing ${total - underMin} of $total. Hiding $few: too few for '
              'a steady average.';
  }

  /// What the "Good means" choice does right now, and what the other would
  /// change.
  String _goodNote(bool ownAverageLine, List<LegendBreakdown> pool) {
    final moved = pool.isEmpty || totalGames == 0
        ? 0
        : legendsMovedByBaseline(
            pool,
            totalGames: totalGames,
            equalShareRate: equalSharePickRate(
              poolGames: pool.fold(0, (sum, l) => sum + l.games),
              totalGames: totalGames,
              poolSize: pool.length,
            ),
            ownAverage: ownAverage,
          );
    final effect = moved == 0
        ? "wouldn't move any legend"
        : 'would move ${plural(moved, 'legend')}';
    final average = '${formatSigned(ownAverage)} RP per game';
    return ownAverageLine
        ? 'The dashed line sits at your average, $average. Using 0 RP '
              'instead $effect.'
        : 'The dashed line sits at 0 RP per game. Your average is $average; '
              'using it $effect.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(pickRateOptionsProvider);
    final notifier = ref.read(pickRateOptionsProvider.notifier);
    final pool = pickRatePool(legends, showAll: options.showAll);
    return SafeArea(
      child: SingleChildScrollView(
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
            _Setting(
              title: 'Legends shown',
              options: ['$kMinGamesForInsight+ games', 'All'],
              selected: options.showAll ? 1 : 0,
              onChanged: (i) => notifier.setShowAll(i == 1),
              note: _shownNote(options.showAll),
            ),
            const SizedBox(height: AppTheme.lg),
            _Setting(
              title: 'Good means',
              options: const ['Above 0 RP', 'Above my average'],
              selected: options.useOwnAverage ? 1 : 0,
              onChanged: (i) => notifier.setUseOwnAverage(i == 1),
              note: _goodNote(options.useOwnAverage, pool),
            ),
          ],
        ),
      ),
    );
  }
}

/// One setting: its name, the choices side by side, and a line on what the
/// current choice does.
class _Setting extends StatelessWidget {
  final String title;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final String note;

  const _Setting({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: AppTheme.sm),
        SegmentedCapsule(
          options: options,
          selected: selected,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppTheme.sm),
        Text(note, style: AppTheme.caption),
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
      children: [for (final q in PickRateQuadrant.values) _KeyChip(q)],
    );
  }
}

class _KeyChip extends StatelessWidget {
  final PickRateQuadrant quadrant;
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
        Text(quadrant.label, style: AppTheme.captionSmall),
      ],
    );
  }
}

class _SelectedDetail extends StatelessWidget {
  final LegendBreakdown? legend;
  final double? pickRate;

  /// The legend's games by map, once loaded; null until then or when there is
  /// no way to look them up.
  final List<LegendMapCell>? maps;

  /// Opens the legend's history; null when there is nowhere to go.
  final ValueChanged<LegendBreakdown>? onOpen;
  const _SelectedDetail({
    required this.legend,
    required this.pickRate,
    this.maps,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l = legend;
    if (l == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.md),
        child: Center(
          child: Text(
            'Tap a legend to see details',
            style: AppTheme.captionLarge,
          ),
        ),
      );
    }
    final rate = pickRate ?? 0;
    final positive = l.avgRpPerGame >= 0;
    final (:best, :worst) = legendBestWorstMap(maps ?? const []);
    return SurfaceCard(
      onTap: onOpen == null ? null : () => onOpen!(l),
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Text(plural(l.games, 'game'), style: AppTheme.caption),
                  ],
                ),
              ),
              Text(
                '${formatSigned(l.avgRpPerGame)} RP/game',
                style: TextStyle(
                  color: AppTheme.signColor(positive),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (onOpen != null) ...[
                const SizedBox(width: AppTheme.xs),
                const Icon(Icons.chevron_right, color: AppTheme.muted),
              ],
            ],
          ),
          const SizedBox(height: AppTheme.md),
          Row(
            children: [
              for (final (i, stat) in [
                ('Pick rate', formatPercent(rate, decimals: 1)),
                ('Win rate', formatPercent(l.winRate)),
                ('Kills', formatAvgKills(l.avgKills)),
                ('Damage', formatAvgDamage(l.avgDamage)),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: AppTheme.xs),
                Expanded(
                  child: StatDisplay(
                    label: stat.$1,
                    value: stat.$2,
                    centered: true,
                  ),
                ),
              ],
            ],
          ),
          if (best != null) ...[
            const SizedBox(height: AppTheme.md),
            _MapLines(best: best, worst: worst),
          ],
        ],
      ),
    );
  }
}

/// The legend's best map and, when there is a distinct one, its worst: a label,
/// the map, then how it goes there, in columns that line up between the rows.
class _MapLines extends StatelessWidget {
  final LegendMapCell best;
  final LegendMapCell? worst;
  const _MapLines({required this.best, required this.worst});

  TableRow _row(String label, LegendMapCell cell) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(label, style: AppTheme.caption),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
          child: Text(
            cell.mapName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text.rich(
            TextSpan(
              style: AppTheme.caption,
              children: [
                TextSpan(
                  text: '${formatSigned(cell.avgRpPerGame)} RP/game',
                  style: TextStyle(
                    color: AppTheme.signColor(cell.avgRpPerGame >= 0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: ' · ${plural(cell.games, 'game')}'),
              ],
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(3),
      },
      children: [_row('Best', best), if (worst != null) _row('Worst', worst!)],
    );
  }
}

/// Relative widths of the table's columns, in order of [LegendSort.values].
const _tableFlex = [12, 8, 6, 6, 7, 6, 6];

/// Table alternative to the scatter chart: one row per legend with its pick
/// share, win rate, RP and kills/damage side by side, for a precise read of the
/// same pool the chart plots. A header sorts by its column; a row selects its
/// legend, the same as tapping its dot.
class _LegendStatsTable extends StatefulWidget {
  final List<LegendBreakdown> pool;
  final int totalGames;
  final String? selected;
  final ValueChanged<LegendBreakdown> onSelect;

  const _LegendStatsTable({
    required this.pool,
    required this.totalGames,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_LegendStatsTable> createState() => _LegendStatsTableState();
}

class _LegendStatsTableState extends State<_LegendStatsTable> {
  LegendSort _sort = LegendSort.pick;
  bool _descending = true;

  void _sortBy(LegendSort sort) => setState(() {
    if (sort == _sort) {
      _descending = !_descending;
    } else {
      _sort = sort;
      _descending = sort.startsDescending;
    }
  });

  @override
  Widget build(BuildContext context) {
    final sorted = sortLegends(widget.pool, _sort, descending: _descending);
    final mostGames = widget.pool.fold(0, (m, l) => l.games > m ? l.games : m);

    // A dense table: past this, the numbers would shrink unevenly to fit.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final sort in LegendSort.values)
                        Expanded(
                          flex: _tableFlex[sort.index],
                          child: _HeaderCell(
                            sort: sort,
                            active: sort == _sort,
                            descending: _descending,
                            onTap: () => _sortBy(sort),
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: AppTheme.surface2, height: 1),
                  for (final l in sorted)
                    _LegendStatsRow(
                      legend: l,
                      pickRate: widget.totalGames == 0
                          ? 0.0
                          : l.games / widget.totalGames,
                      shareOfMost: mostGames == 0 ? 0.0 : l.games / mostGames,
                      selected: l.legend == widget.selected,
                      onTap: () => widget.onSelect(l),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.sm),
            const Text(
              'Tap a heading to sort. RP/G is RP per game and Net is total RP; '
              'kills and damage are per-game averages.',
              style: AppTheme.captionSmall,
            ),
          ],
        ),
      ),
    );
  }
}

extension on LegendSort {
  String get heading => switch (this) {
    LegendSort.legend => 'LEGEND',
    LegendSort.pick => 'PICK',
    LegendSort.win => 'WIN',
    LegendSort.rpPerGame => 'RP/G',
    LegendSort.netRp => 'NET',
    LegendSort.kills => 'KILLS',
    LegendSort.damage => 'DMG',
  };
}

class _HeaderCell extends StatelessWidget {
  final LegendSort sort;
  final bool active;
  final bool descending;
  final VoidCallback onTap;
  const _HeaderCell({
    required this.sort,
    required this.active,
    required this.descending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.accent : AppTheme.muted;
    final start = sort == LegendSort.legend;
    return Semantics(
      button: true,
      label: 'Sort by ${sort.heading.toLowerCase()}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(
            top: AppTheme.sm,
            bottom: AppTheme.sm,
            left: AppTheme.xs,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: start ? Alignment.centerLeft : Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active)
                  Icon(
                    descending ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 10,
                    color: color,
                  ),
                Text(
                  sort.heading,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendStatsRow extends StatelessWidget {
  final LegendBreakdown legend;
  final double pickRate;

  /// This legend's games as a share of the most played legend's, for the bar.
  final double shareOfMost;
  final bool selected;
  final VoidCallback onTap;

  const _LegendStatsRow({
    required this.legend,
    required this.pickRate,
    required this.shareOfMost,
    required this.selected,
    required this.onTap,
  });

  static const _value = TextStyle(color: AppTheme.textPrimary, fontSize: 12);

  Widget _number(
    LegendSort sort,
    String text, {
    Color? color,
    bool bold = false,
  }) {
    return Expanded(
      flex: _tableFlex[sort.index],
      child: Padding(
        padding: const EdgeInsets.only(left: AppTheme.xs),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            text,
            style: _value.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accent.withAlpha(25) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.sm),
          child: Row(
            children: [
              Expanded(
                flex: _tableFlex[LegendSort.legend.index],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      legend.legend,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      plural(legend.games, 'game'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.captionSmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: _tableFlex[LegendSort.pick.index],
                child: Padding(
                  padding: const EdgeInsets.only(left: AppTheme.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(formatPercent(pickRate), style: _value),
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: shareOfMost,
                          minHeight: 3,
                          color: AppTheme.accent,
                          backgroundColor: AppTheme.surface2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _number(
                LegendSort.win,
                formatPercent(legend.winRate, decimals: 0),
              ),
              _number(
                LegendSort.rpPerGame,
                formatSigned(legend.avgRpPerGame),
                color: AppTheme.signColor(legend.avgRpPerGame >= 0),
                bold: true,
              ),
              _number(
                LegendSort.netRp,
                formatSignedInt(legend.totalRp),
                color: AppTheme.signColor(legend.totalRp >= 0),
              ),
              _number(LegendSort.kills, formatAvgKills(legend.avgKills)),
              _number(LegendSort.damage, formatAvgDamage(legend.avgDamage)),
            ],
          ),
        ),
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
              style: AppTheme.captionLarge,
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
