import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../constants/ranked_map_constants.dart';
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// Per-match RP progression for the selected split/week (passed in already
/// filtered). A Session filter narrows the line to a single play session.
class RankedRpChart extends StatefulWidget {
  final List<RankedMatch> matches;
  const RankedRpChart({super.key, required this.matches});

  @override
  State<RankedRpChart> createState() => _RankedRpChartState();
}

class _RankedRpChartState extends State<RankedRpChart> {
  // -1 = all sessions in the current split/week.
  int _sessionIndex = -1;

  static final _sessionFmt = DateFormat('MMM d, h:mm a');

  @override
  Widget build(BuildContext context) {
    final sessions = sessionize(widget.matches);
    // A stale selection (data changed under us) falls back to "All".
    final selected = _sessionIndex >= 0 && _sessionIndex < sessions.length
        ? _sessionIndex
        : -1;

    final chrono = _matchesForSelection(sessions, selected);

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ranked Point History',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.muted,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              if (sessions.isNotEmpty)
                _SessionPicker(
                  sessions: sessions,
                  selectedIndex: selected,
                  fmt: _sessionFmt,
                  onSelected: (i) => setState(() => _sessionIndex = i),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.md),
          SizedBox(
            height: 130,
            child: chrono.length < 2
                ? const Center(
                    child: Text(
                      'Not enough matches in this range',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  )
                : _buildChart(chrono),
          ),
        ],
      ),
    );
  }

  List<RankedMatch> _matchesForSelection(
      List<RankedSession> sessions, int selected) {
    final chrono = widget.matches.where((m) => m.isRanked).toList()
      ..sort((a, b) => a.endTime.compareTo(b.endTime));
    if (selected < 0) return chrono;
    final s = sessions[selected];
    return chrono
        .where((m) =>
            !m.startTime.isBefore(s.start) && !m.endTime.isAfter(s.end))
        .toList();
  }

  Widget _buildChart(List<RankedMatch> matches) {
    final spots = matches
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.cumulativeRp.toDouble()))
        .toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.surface2,
            getTooltipItems: (touched) => touched.map((s) {
              final idx = s.x.isNaN
                  ? 0
                  : s.x.toInt().clamp(0, matches.length - 1);
              final m = matches[idx];
              final sign = m.rpChange >= 0 ? '+' : '';
              return LineTooltipItem(
                '${formatNumber(m.cumulativeRp)} RP  ($sign${m.rpChange})\n'
                '${m.legend} · ${rankedMapName(m.mapKey)}\n'
                '${DateFormat('MMM d, h:mm a').format(m.endTime.toLocal())}',
                const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: AppTheme.accent,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                final up = matches[index].rpChange >= 0;
                return FlDotCirclePainter(
                  radius: 2.5,
                  color: up ? AppTheme.green : AppTheme.red,
                  strokeColor: AppTheme.surface,
                  strokeWidth: 1,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.accent.withAlpha(35),
            ),
            isCurved: false,
          ),
        ],
      ),
    );
  }
}

class _SessionPicker extends StatelessWidget {
  final List<RankedSession> sessions;
  final int selectedIndex; // -1 = All
  final DateFormat fmt;
  final ValueChanged<int> onSelected;

  const _SessionPicker({
    required this.sessions,
    required this.selectedIndex,
    required this.fmt,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedIndex < 0
        ? 'All sessions'
        : fmt.format(sessions[selectedIndex].start.toLocal());

    return PopupMenuButton<int>(
      initialValue: selectedIndex,
      onSelected: onSelected,
      color: AppTheme.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: -1, child: Text('All sessions')),
        for (var i = 0; i < sessions.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              '${fmt.format(sessions[i].start.toLocal())} · ${sessions[i].games}g',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }
}
