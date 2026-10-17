import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart'
    show formatDuration, formatShortDate, formatSigned, formatSignedInt, plural;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/ranked/session_overview.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// How many of the latest sessions the chart draws.
const _kChartSessions = 30;

/// What the sessions add up to: counts and averages, the best and worst one,
/// and a bar per session for the RP it netted. [sessions] is newest first;
/// [onOpen] shows one session's games.
class SessionsOverview extends StatelessWidget {
  final List<RankedSession> sessions;
  final ValueChanged<RankedSession> onOpen;
  const SessionsOverview({
    super.key,
    required this.sessions,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final overview = sessionOverview(sessions);
    if (overview == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(AppTheme.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Stat('${overview.count}', 'sessions'),
                  _Stat(overview.avgGames.toStringAsFixed(1), 'games each'),
                  _Stat(
                    formatSigned(overview.avgNetRp),
                    'RP each',
                    color: AppTheme.signColor(overview.avgNetRp >= 0),
                  ),
                  _Stat(formatDuration(overview.totalTime.inSeconds), 'played'),
                ],
              ),
              const SizedBox(height: AppTheme.sm),
              const Divider(color: AppTheme.surface2, height: 1),
              _Extreme(
                label: 'Best session',
                session: overview.best,
                onOpen: onOpen,
              ),
              if (overview.worst != null)
                _Extreme(
                  label: 'Worst session',
                  session: overview.worst!,
                  onOpen: onOpen,
                ),
            ],
          ),
        ),
        if (sessions.length > 1) ...[
          const SizedBox(height: AppTheme.sm),
          _RpPerSessionChart(sessions: sessions, onOpen: onOpen),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Stat(this.value, this.label, {this.color = AppTheme.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
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

/// The best or worst session as a tappable line.
class _Extreme extends StatelessWidget {
  final String label;
  final RankedSession session;
  final ValueChanged<RankedSession> onOpen;
  const _Extreme({
    required this.label,
    required this.session,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onOpen(session),
      child: Padding(
        padding: const EdgeInsets.only(top: AppTheme.sm),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$label  ', style: AppTheme.caption),
                    TextSpan(
                      text:
                          '${formatShortDate(session.start)} · '
                          '${plural(session.games, 'game')}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTheme.sm),
            Text(
              '${formatSignedInt(session.netRp)} RP',
              style: TextStyle(
                color: AppTheme.signColor(session.netRp >= 0),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}

/// One bar per session, oldest on the left, green for RP gained and red for
/// lost. Tapping a bar opens that session.
class _RpPerSessionChart extends StatelessWidget {
  final List<RankedSession> sessions;
  final ValueChanged<RankedSession> onOpen;
  const _RpPerSessionChart({required this.sessions, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    // Newest first in, oldest first out, so time runs left to right.
    final shown = sessions.take(_kChartSessions).toList().reversed.toList();
    final values = [for (final s in shown) s.netRp.toDouble()];
    final top = values.fold(0.0, (a, b) => a > b ? a : b);
    final bottom = values.fold(0.0, (a, b) => a < b ? a : b);
    final maxY = top <= 0 ? 1.0 : top * 1.15;
    final minY = bottom >= 0 ? 0.0 : bottom * 1.15;
    final barWidth = (240 / shown.length).clamp(3.0, 14.0);

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('RP PER SESSION', style: AppTheme.cardTitle),
              const SizedBox(width: AppTheme.sm),
              // Flexible, so a narrow screen or larger text shortens the range
              // instead of overflowing the row.
              Flexible(
                child: Text(
                  '${formatShortDate(shown.first.start)} – '
                  '${formatShortDate(shown.last.start)}',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.captionSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            shown.length < sessions.length
                ? 'Latest ${shown.length} sessions · tap a bar to open it'
                : 'Tap a bar to open that session',
            style: AppTheme.captionSmall,
          ),
          const SizedBox(height: AppTheme.md),
          SizedBox(
            height: 110,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                minY: minY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: AppTheme.muted.withValues(alpha: 0.5),
                      strokeWidth: 1,
                    ),
                  ],
                ),
                barTouchData: BarTouchData(
                  handleBuiltInTouches: false,
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    final i = response?.spot?.touchedBarGroupIndex;
                    if (i != null) onOpen(shown[i]);
                  },
                ),
                barGroups: [
                  for (final (i, v) in values.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: v,
                          color: AppTheme.signColor(v >= 0),
                          width: barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
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
