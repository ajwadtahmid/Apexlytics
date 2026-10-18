import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/ranked_match.dart';
import '../../utils/formatting/format.dart'
    show
        formatDuration,
        formatSessionSpan,
        formatSigned,
        formatSignedInt,
        formatTotalOrNone,
        plural;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/ranked/session_overview.dart';
import '../../utils/theme.dart';
import '../../widgets/legend_icon.dart';
import '../../widgets/surface_card.dart';
import 'widgets/match_history_list.dart';

/// One session in full: what it netted and how, its RP through the games with
/// the worst stretch marked, how each legend did, and then its games.
class RankedSessionDetailScreen extends StatefulWidget {
  final RankedSession session;
  final Future<void> Function() onRefresh;

  /// Told of a correction made on this page, for whoever opened it to keep
  /// its own figures in step.
  final ValueChanged<RankedMatch>? onMatchUpdated;

  const RankedSessionDetailScreen({
    super.key,
    required this.session,
    required this.onRefresh,
    this.onMatchUpdated,
  });

  @override
  State<RankedSessionDetailScreen> createState() =>
      _RankedSessionDetailScreenState();
}

class _RankedSessionDetailScreenState extends State<RankedSessionDetailScreen> {
  // Held here, as the History drill-downs do, so a correction made on a game
  // shows up in the figures above without leaving the page.
  late List<RankedMatch> _matches = widget.session.matches;
  late RankedSession _session = widget.session;

  void _onMatchUpdated(RankedMatch updated) {
    setState(() {
      _matches = [
        for (final m in _matches)
          if (m.id == updated.id) updated else m,
      ];
      // The same games, so still one session; its totals follow the correction.
      final rebuilt = sessionize(_matches);
      if (rebuilt.length == 1) _session = rebuilt.single;
    });
    widget.onMatchUpdated?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final results = sessionGameRp(_session);
    final path = sessionRpPath(_session);
    final legends = sessionLegendResults(_session);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Session', style: TextStyle(fontSize: 17)),
            Text(
              formatSessionSpan(_session.start, _session.end),
              style: AppTheme.caption,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: MatchHistoryList(
          matches: _matches,
          onRefresh: widget.onRefresh,
          emptyLabel: 'No ranked games here',
          onMatchUpdated: _onMatchUpdated,
          collapseScope: 'session',
          showBreaks: false,
          hideSessionHeaders: true,
          leading: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Summary(session: _session, results: results),
              if (path.length > 2) ...[
                const SizedBox(height: AppTheme.md),
                _RpCurve(path: path),
              ],
              if (legends.length > 1) ...[
                const SizedBox(height: AppTheme.md),
                _LegendResults(results: legends),
              ],
              const SizedBox(height: AppTheme.lg),
              Text('GAMES · ${_session.games}', style: AppTheme.cardTitle),
            ],
          ),
        ),
      ),
    );
  }
}

/// The session's net RP, then its figures: games, record, time, kills, damage
/// and the longest wait between games.
class _Summary extends StatelessWidget {
  final RankedSession session;
  final List<int> results;
  const _Summary({required this.session, required this.results});

  @override
  Widget build(BuildContext context) {
    final wins = results.where((rp) => rp > 0).length;
    final losses = results.where((rp) => rp < 0).length;
    final avgRp = session.games == 0 ? 0.0 : session.netRp / session.games;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '${formatSignedInt(session.netRp)} RP',
              style: TextStyle(
                color: AppTheme.signColor(session.netRp >= 0),
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.md),
          Row(
            children: [
              _Figure('${session.games}', 'games'),
              _Figure.rich([
                TextSpan(
                  text: '$wins',
                  style: const TextStyle(color: AppTheme.green),
                ),
                const TextSpan(text: '–'),
                TextSpan(
                  text: '$losses',
                  style: const TextStyle(color: AppTheme.red),
                ),
              ], 'wins–losses'),
              _Figure(formatDuration(session.duration.inSeconds), 'played'),
            ],
          ),
          const SizedBox(height: AppTheme.md),
          Row(
            children: [
              _Figure(
                formatTotalOrNone(session.totalKills, session.killsGames),
                'kills',
              ),
              _Figure(
                formatTotalOrNone(session.totalDamage, session.damageGames),
                'damage',
              ),
              _Figure(
                formatSigned(avgRp),
                'avg RP/game',
                color: AppTheme.signColor(avgRp >= 0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String value;
  final List<InlineSpan>? spans;
  final String label;
  final Color color;
  const _Figure(this.value, this.label, {this.color = AppTheme.textPrimary})
    : spans = null;

  /// A figure made of differently coloured parts.
  const _Figure.rich(List<InlineSpan> this.spans, this.label)
    : value = '',
      color = AppTheme.textPrimary;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: color,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: spans == null
                ? Text(value, style: style)
                : Text.rich(TextSpan(children: spans), style: style),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.captionSmall,
          ),
        ],
      ),
    );
  }
}

/// The RP running total through the session, a dot a game, with the worst fall
/// shaded and described under it.
class _RpCurve extends StatelessWidget {
  final List<int> path;
  const _RpCurve({required this.path});

  @override
  Widget build(BuildContext context) {
    final drop = biggestDrop(path);
    final gain = biggestGain(path);
    final low = path.reduce((a, b) => a < b ? a : b).toDouble();
    final high = path.reduce((a, b) => a > b ? a : b).toDouble();
    final pad = high - low < 1 ? 1.0 : (high - low) * 0.15;
    // The line is green while the session's running total is above where it
    // started, and red while it is below. When it crosses, the colour changes
    // at the baseline itself (the line's box runs from its highest point at the
    // top to its lowest at the bottom, so the baseline sits this far down it).
    final crosses = low < 0 && high > 0;
    final baseline = crosses ? high / (high - low) : 0.0;
    final onePart = low >= 0 ? AppTheme.green : AppTheme.red;
    Color sideOf(num rp) => rp >= 0 ? AppTheme.green : AppTheme.red;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RP THROUGH THE SESSION', style: AppTheme.cardTitle),
          const SizedBox(height: 2),
          const Text(
            'Tap a game to see the total after it',
            style: AppTheme.captionSmall,
          ),
          const SizedBox(height: AppTheme.md),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: low - pad,
                maxY: high + pad,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: [
                    if (gain != null)
                      VerticalRangeAnnotation(
                        x1: gain.from.toDouble(),
                        x2: gain.to.toDouble(),
                        color: AppTheme.green.withValues(alpha: 0.14),
                      ),
                    if (drop != null)
                      VerticalRangeAnnotation(
                        x1: drop.from.toDouble(),
                        x2: drop.to.toDouble(),
                        color: AppTheme.red.withValues(alpha: 0.14),
                      ),
                  ],
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: AppTheme.muted.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.surface2,
                    getTooltipItems: (touched) => [
                      for (final t in touched)
                        LineTooltipItem(
                          t.x == 0
                              ? 'Start'
                              : 'Game ${t.x.toInt()}\n'
                                    '${formatSignedInt(t.y.round())} RP',
                          const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (final (i, v) in path.indexed)
                        FlSpot(i.toDouble(), v.toDouble()),
                    ],
                    color: crosses ? null : onePart,
                    gradient: crosses
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: const [
                              AppTheme.green,
                              AppTheme.green,
                              AppTheme.red,
                              AppTheme.red,
                            ],
                            stops: [0, baseline, baseline, 1],
                          )
                        : null,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                        radius: 2.5,
                        color: sideOf(spot.y),
                        strokeWidth: 0,
                      ),
                    ),
                    // Tinted between the line and the baseline, on each side.
                    belowBarData: BarAreaData(
                      show: high > 0,
                      color: AppTheme.green.withValues(alpha: 0.08),
                      cutOffY: 0,
                      applyCutOffY: true,
                    ),
                    aboveBarData: BarAreaData(
                      show: low < 0,
                      color: AppTheme.red.withValues(alpha: 0.08),
                      cutOffY: 0,
                      applyCutOffY: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (gain != null)
            _Stretch(
              label: 'Biggest gain',
              rp: gain.amount,
              from: gain.from,
              to: gain.to,
              color: AppTheme.green,
            ),
          if (drop != null)
            _Stretch(
              label: 'Biggest drop',
              rp: -drop.amount,
              from: drop.from,
              to: drop.to,
              color: AppTheme.red,
            ),
        ],
      ),
    );
  }
}

/// A caption for a stretch of the session: "Biggest gain: +55 RP over games
/// 1–2". [from] and [to] are indexes into the RP path, so the games that made
/// it are [from] + 1 through [to].
class _Stretch extends StatelessWidget {
  final String label;
  final int rp;
  final int from;
  final int to;
  final Color color;
  const _Stretch({
    required this.label,
    required this.rp,
    required this.from,
    required this.to,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final first = from + 1;
    final games = first == to ? 'game $first' : 'games $first–$to';
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Text(
        '$label: ${formatSignedInt(rp)} RP over $games',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// How each legend did in the session, the best first.
class _LegendResults extends StatelessWidget {
  final List<LegendResult> results;
  const _LegendResults({required this.results});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BY LEGEND', style: AppTheme.cardTitle),
          for (final r in results)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.sm),
              child: Row(
                children: [
                  LegendIcon(legendName: r.legend, size: 16),
                  const SizedBox(width: AppTheme.sm),
                  Expanded(
                    child: Text(
                      r.legend,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(plural(r.games, 'game'), style: AppTheme.caption),
                  const SizedBox(width: AppTheme.md),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '${formatSignedInt(r.netRp)} RP',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: AppTheme.signColor(r.netRp >= 0),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
