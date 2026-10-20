import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatNumber, formatShortDateTime, formatSignedInt, plural;
import '../../../utils/formatting/season_utils.dart' show WeekRange;
import '../../../constants/map_constants.dart';
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/ranked/ranked_period.dart' show matchesInWeek;
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// Match and session times in the chart's tooltips and session picker.
final _sessionFmt = DateFormat('MMM d, h:mm a');

final _dayFmt = DateFormat('MMM d');

/// Above this many plotted points, individual dots stop being useful (they
/// overlap into a solid band) and cost more to paint than they convey.
const int _kMaxDotPoints = 150;

/// Hard cap on plotted points. Beyond this the chart downsamples rather than
/// paying an unbounded per-frame rendering cost for a very long history.
const int _kMaxChartPoints = 400;

/// Per-match RP progression for the selected split/week (passed in already
/// filtered). [sessions] is memoized by `rankedSplitViewProvider` rather than
/// recomputed here on every rebuild. The picker narrows the line to a single
/// play session; with every week selected ([weekIndex] below 0, and [weeks]
/// known) that would be a list as long as the split, so it offers the weeks
/// instead.
/// [onShowBackup], when set, adds a small icon opening the snapshot-based RP
/// graph as a backup view.
class RankedRpChart extends StatefulWidget {
  final List<RankedMatch> matches;
  final List<RankedSession> sessions;

  /// The split's weeks and the one selected on the page (-1 for all of them).
  final List<WeekRange> weeks;
  final int weekIndex;
  final VoidCallback? onShowBackup;
  const RankedRpChart({
    super.key,
    required this.matches,
    required this.sessions,
    this.weeks = const [],
    this.weekIndex = -1,
    this.onShowBackup,
  });

  @override
  State<RankedRpChart> createState() => _RankedRpChartState();
}

class _RankedRpChartState extends State<RankedRpChart> {
  // The choice, held as what it is rather than a list position, so data
  // changing under it can't leave it pointing at something else. Null = all of
  // the split or week.
  DateTime? _sessionStart;
  DateTime? _weekStart;

  @override
  void didUpdateWidget(RankedRpChart old) {
    super.didUpdateWidget(old);
    // Another week on the page's strip starts the chart over.
    if (old.weekIndex != widget.weekIndex) {
      _sessionStart = null;
      _weekStart = null;
    }
  }

  /// The weeks the picker offers, when it offers weeks: every week of the
  /// split with a ranked game in it. Empty when a week is already selected or
  /// the split has no weeks, which leaves the sessions.
  List<({WeekRange range, int number, int games})> _weekChoices() {
    if (widget.weekIndex >= 0 || widget.weeks.isEmpty) return const [];
    final ranked = widget.matches.where((m) => m.isRanked).toList();
    return [
      for (var i = 0; i < widget.weeks.length; i++)
        if (matchesInWeek(ranked, widget.weeks[i]).length case final games
            when games > 0)
          (range: widget.weeks[i], number: i + 1, games: games),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final weekChoices = _weekChoices();
    final byWeek = weekChoices.isNotEmpty;
    // A choice that no longer exists falls back to "All".
    final selected = byWeek
        ? weekChoices.indexWhere((w) => w.range.start == _weekStart)
        : sessions.indexWhere((s) => s.start == _sessionStart);

    final chrono = byWeek
        ? _matchesInWeek(selected < 0 ? null : weekChoices[selected].range)
        : _matchesForSelection(sessions, selected);
    // Downsampled for rendering only - "not enough matches" and the session
    // picker still reason about the real (non-downsampled) chrono list.
    final displayMatches = _downsample(chrono, _kMaxChartPoints);

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Ranked Point History',
                  style: AppTheme.cardTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onShowBackup != null)
                      IconButton(
                        icon: const Icon(Icons.backup_outlined, size: 16),
                        tooltip: 'Snapshot Graph',
                        color: AppTheme.muted,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: widget.onShowBackup,
                      ),
                    if (widget.onShowBackup != null &&
                        (byWeek || sessions.isNotEmpty))
                      const SizedBox(width: AppTheme.sm),
                    if (byWeek)
                      Flexible(
                        child: _ScopePicker(
                          allLabel: 'All weeks',
                          labels: [
                            for (final w in weekChoices)
                              'W${w.number} · ${_weekDates(w.range)}',
                          ],
                          details: [
                            for (final w in weekChoices)
                              plural(w.games, 'game'),
                          ],
                          selectedIndex: selected,
                          onSelected: (i) => setState(
                            () => _weekStart = i < 0
                                ? null
                                : weekChoices[i].range.start,
                          ),
                        ),
                      )
                    else if (sessions.isNotEmpty)
                      Flexible(
                        child: _ScopePicker(
                          allLabel: 'All sessions',
                          labels: [
                            for (final s in sessions)
                              _sessionFmt.format(s.start.toLocal()),
                          ],
                          details: [for (final s in sessions) '${s.games}g'],
                          selectedIndex: selected,
                          onSelected: (i) => setState(
                            () => _sessionStart = i < 0
                                ? null
                                : sessions[i].start,
                          ),
                        ),
                      ),
                  ],
                ),
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
                      style: AppTheme.caption,
                    ),
                  )
                : _buildChart(displayMatches),
          ),
        ],
      ),
    );
  }

  /// Ranked games, oldest first, in [week] (all of them when null).
  List<RankedMatch> _matchesInWeek(WeekRange? week) {
    final chrono = widget.matches.where((m) => m.isRanked).toList()
      ..sort((a, b) => a.endTime.compareTo(b.endTime));
    return week == null ? chrono : matchesInWeek(chrono, week);
  }

  /// "Oct 6–12", or "Oct 30 – Nov 5" across a month. The week's end is the
  /// start of the next one, so the last day shown is the one before it.
  static String _weekDates(WeekRange week) {
    final first = week.start.toLocal();
    final last = week.end.toLocal().subtract(const Duration(seconds: 1));
    return first.month == last.month
        ? '${_dayFmt.format(first)}–${last.day}'
        : '${_dayFmt.format(first)} – ${_dayFmt.format(last)}';
  }

  List<RankedMatch> _matchesForSelection(
    List<RankedSession> sessions,
    int selected,
  ) {
    final chrono = widget.matches.where((m) => m.isRanked).toList()
      ..sort((a, b) => a.endTime.compareTo(b.endTime));
    if (selected < 0) return chrono;
    final s = sessions[selected];
    return chrono
        .where(
          (m) => !m.startTime.isBefore(s.start) && !m.endTime.isAfter(s.end),
        )
        .toList();
  }

  /// Strided downsample to at most [cap] points, always keeping the last
  /// point so the plotted range still ends at the true latest match. No-op
  /// when already at or under the cap.
  List<RankedMatch> _downsample(List<RankedMatch> matches, int cap) {
    if (matches.length <= cap) return matches;
    final step = matches.length / cap;
    final sampled = <RankedMatch>[
      for (var i = 0; i < cap; i++) matches[(i * step).floor()],
    ];
    if (sampled.last != matches.last) sampled.add(matches.last);
    return sampled;
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
              return LineTooltipItem(
                '${formatNumber(m.cumulativeRp)} RP  (${formatSignedInt(m.rpChange)})\n'
                '${m.legend} · ${battleRoyaleMapName(m.mapKey)}\n'
                '${formatShortDateTime(m.endTime)}',
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
              // Above _kMaxDotPoints, individual dots overlap into a solid
              // band — the line alone still carries the trend.
              show: matches.length <= _kMaxDotPoints,
              getDotPainter: (spot, percent, bar, index) {
                final up = matches[index].rpChange >= 0;
                return FlDotCirclePainter(
                  radius: 2.5,
                  color: AppTheme.signColor(up),
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

/// The pill above the chart that narrows it to one session or week. [labels]
/// and [details] are the choices after "All" ([allLabel]), as the menu shows
/// them; [selectedIndex] is one of them, or -1 for all.
class _ScopePicker extends StatelessWidget {
  final String allLabel;
  final List<String> labels;
  final List<String> details;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _ScopePicker({
    required this.allLabel,
    required this.labels,
    required this.details,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedIndex < 0 ? allLabel : labels[selectedIndex];

    return PopupMenuButton<int>(
      initialValue: selectedIndex,
      onSelected: onSelected,
      color: AppTheme.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(value: -1, child: Text(allLabel)),
        for (var i = 0; i < labels.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              '${labels[i]} · ${details[i]}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.sm,
          vertical: AppTheme.xs,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }
}
