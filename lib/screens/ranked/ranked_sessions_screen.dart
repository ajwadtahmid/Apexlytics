import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/formatting/format.dart' show formatTotalOrNone, plural;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/ranked/session_overview.dart';
import '../../utils/theme.dart';
import '../../widgets/rp_pill.dart';
import '../../widgets/surface_card.dart';

final _sessionDateFmt = DateFormat('MMM d · h:mm a');

/// A mark on the session that netted the most or the least RP.
enum SessionBadge {
  best('BEST', AppTheme.green),
  worst('WORST', AppTheme.red);

  final String label;
  final Color color;
  const SessionBadge(this.label, this.color);
}

/// A tappable session summary as its own card. Used by the Sessions
/// screen's session list.
class SessionRecapTile extends StatelessWidget {
  final RankedSession session;
  final VoidCallback onTap;
  final SessionBadge? badge;

  const SessionRecapTile({
    super.key,
    required this.session,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.md),
      child: SessionRecapBody(session: session, badge: badge),
    );
  }
}

/// Card-less session summary: date, net RP, a stat strip (games · kills ·
/// time · top legend), and how the session went game by game. Used by
/// [SessionRecapTile].
class SessionRecapBody extends StatelessWidget {
  final RankedSession session;
  final SessionBadge? badge;
  const SessionRecapBody({super.key, required this.session, this.badge});

  @override
  Widget build(BuildContext context) {
    final best = session.bestLegend;
    final multiple = session.matches.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _sessionDateFmt.format(session.start.toLocal()),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (badge != null) _BadgeChip(badge!),
          ],
        ),
        const SizedBox(height: AppTheme.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The stats and the strip share a column, so a long legend name
            // stops where the strip does.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Spread to the strip's edges; a long name shrinks to fit.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _stat('${session.games}', 'games'),
                      _stat(
                        formatTotalOrNone(
                          session.totalKills,
                          session.killsGames,
                        ),
                        'kills',
                      ),
                      if (best != null)
                        Flexible(child: _stat(best, 'top legend')),
                    ],
                  ),
                  if (session.matches.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.sm),
                    _ResultStrip(session: session),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppTheme.md),
            // The RP, level with the stats, and its line level with the strip.
            SizedBox(
              width: 96,
              child: Column(
                children: [
                  SizedBox(
                    height: AppTheme.scaledWithText(context, 32),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RpPill(totalRp: session.netRp),
                      ),
                    ),
                  ),
                  if (multiple) ...[
                    const SizedBox(height: AppTheme.sm),
                    SizedBox(
                      height: 30,
                      child: _RpPath(path: sessionRpPath(session)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(label, style: AppTheme.captionSmall),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final SessionBadge badge;
  const _BadgeChip(this.badge);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm, vertical: 2),
      decoration: BoxDecoration(
        color: badge.color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        badge.label,
        style: TextStyle(
          color: badge.color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// How a session went: a segment per game, green for a win, red for a loss and
/// grey for no change.
class _ResultStrip extends StatelessWidget {
  final RankedSession session;
  const _ResultStrip({required this.session});

  @override
  Widget build(BuildContext context) {
    final results = sessionGameRp(session);
    final wins = results.where((rp) => rp > 0).length;
    final losses = results.where((rp) => rp < 0).length;
    return Semantics(
      label: '${plural(wins, 'win')}, ${plural(losses, 'loss', 'losses')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final rp in results)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: rp > 0
                            ? AppTheme.green
                            : rp < 0
                            ? AppTheme.red
                            : AppTheme.muted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The RP running total through a session, from 0, with a faint line at 0.
class _RpPath extends StatelessWidget {
  final List<int> path;
  const _RpPath({required this.path});

  @override
  Widget build(BuildContext context) {
    final low = path.reduce((a, b) => a < b ? a : b).toDouble();
    final high = path.reduce((a, b) => a > b ? a : b).toDouble();
    // A flat run needs padding, else fl_chart's min == max range draws nothing.
    final pad = high - low < 1 ? 1.0 : (high - low) * 0.15;
    final color = AppTheme.signColor(path.last >= 0);
    return LineChart(
      LineChartData(
        minY: low - pad,
        maxY: high + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 0,
              color: AppTheme.muted.withValues(alpha: 0.4),
              strokeWidth: 1,
              dashArray: [3, 3],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, v) in path.indexed)
                FlSpot(i.toDouble(), v.toDouble()),
            ],
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
