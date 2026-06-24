import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/season_meta.dart';
import '../utils/formatting/snapshot_types.dart';
import '../utils/formatting/season_utils.dart';
import '../utils/theme.dart';
import 'surface_card.dart';
import '../utils/formatting/format.dart' show formatNumber;

class GraphCard extends StatefulWidget {
  final List<StatSnapshot> snapshots;
  final SeasonMeta? currentSeason;
  final Map<String, SeasonMeta> allSeasons;
  final int? currentRp;

  const GraphCard({
    super.key,
    required this.snapshots,
    this.currentSeason,
    this.allSeasons = const {},
    this.currentRp,
  });

  @override
  State<GraphCard> createState() => _GraphCardState();
}

class _GraphCardState extends State<GraphCard> {
  String? _selectedSeasonId;
  int _selectedWeekIndex = 0;

  // Week list is memoized — recomputed only when the selected season changes.
  List<WeekRange> _weeks = const [];
  String? _weeksForSeasonId;

  // _effectiveAllSeasons is memoized — recomputed only when widget.allSeasons or widget.currentSeason changes.
  Map<String, SeasonMeta>? _memoizedAllSeasons;
  Map<String, SeasonMeta>? _memoizedAllSeasonsFrom;
  String? _memoizedAllSeasonsCurrentId;

  @override
  void initState() {
    super.initState();
    _resetToCurrentSeason();
  }

  @override
  void didUpdateWidget(GraphCard old) {
    super.didUpdateWidget(old);
    if (old.currentSeason?.id != widget.currentSeason?.id) {
      setState(() {
        _resetToCurrentSeason();
      });
    }
  }

  void _resetToCurrentSeason() {
    _selectedSeasonId = widget.currentSeason?.id;
    final weeks = _getWeeks();
    _selectedWeekIndex = currentWeekIndex(weeks);
  }

  SeasonMeta? get _selectedSeason {
    final id = _selectedSeasonId ?? widget.currentSeason?.id;
    if (id == null) return widget.currentSeason;
    return _effectiveAllSeasons[id] ?? widget.currentSeason;
  }

  // allSeasons always includes currentSeason even if storage hasn't caught up.
  // Memoized to avoid creating a new Map on every call.
  // identical() for the map: widget.allSeasons only changes reference on provider
  // rebuild, so reference equality is sufficient. currentSeason is compared by id
  // because the widget may receive a new SeasonMeta instance with the same value.
  Map<String, SeasonMeta> get _effectiveAllSeasons {
    if (_memoizedAllSeasons != null &&
        identical(_memoizedAllSeasonsFrom, widget.allSeasons) &&
        _memoizedAllSeasonsCurrentId == widget.currentSeason?.id) {
      return _memoizedAllSeasons!;
    }
    final base = Map<String, SeasonMeta>.from(widget.allSeasons);
    if (widget.currentSeason != null) {
      base[widget.currentSeason!.id] = widget.currentSeason!;
    }
    _memoizedAllSeasons = base;
    _memoizedAllSeasonsFrom = widget.allSeasons;
    _memoizedAllSeasonsCurrentId = widget.currentSeason?.id;
    return base;
  }

  List<WeekRange> _getWeeks() {
    final season = _selectedSeason;
    if (season == null) return const [];
    if (_weeksForSeasonId != season.id) {
      _weeks = computeWeeks(season);
      _weeksForSeasonId = season.id;
    }
    return _weeks;
  }

  void _onSeasonSelected(String id) {
    final season = _effectiveAllSeasons[id];
    if (season == null) return;
    final weeks = computeWeeks(season);
    final isCurrentSeason = id == widget.currentSeason?.id;
    int weekIdx;
    if (isCurrentSeason) {
      weekIdx = currentWeekIndex(weeks);
    } else {
      // Jump to the last week that has at least one snapshot.
      final lastSnap = widget.snapshots.lastWhere(
        (s) =>
            !s.timestamp.isBefore(season.start) &&
            s.timestamp.isBefore(season.end),
        orElse: () => widget.snapshots.isNotEmpty
            ? widget.snapshots.last
            : StatSnapshot(timestamp: season.start, rp: 0),
      );
      weekIdx = weeks.indexWhere((w) =>
          !lastSnap.timestamp.isBefore(w.start) &&
          lastSnap.timestamp.isBefore(w.end));
      if (weekIdx < 0) weekIdx = 0;
    }
    setState(() {
      _selectedSeasonId = id;
      _weeksForSeasonId = null; // force recompute
      _selectedWeekIndex = weekIdx;
    });
  }

  @override
  Widget build(BuildContext context) {
    final season = _selectedSeason;
    if (season == null) return _buildNoSeason();

    final weeks = _getWeeks();
    if (weeks.isEmpty) return _buildNoSeason();

    final weekIdx = _selectedWeekIndex.clamp(0, weeks.length - 1);
    final week = weeks[weekIdx];
    final weekSnaps = snapshotsForWeek(widget.snapshots, week);

    final now = DateTime.now();
    final isCurrentSeason = season.id == widget.currentSeason?.id;
    final isLiveWeek =
        isCurrentSeason && !now.isBefore(week.start) && now.isBefore(week.end);

    // Append the live RP point to the line without a disk write.
    final List<StatSnapshot> displaySnaps;
    if (isLiveWeek && widget.currentRp != null) {
      final liveRp = widget.currentRp!;
      final livePoint = StatSnapshot(timestamp: now, rp: liveRp);
      displaySnaps = (weekSnaps.isNotEmpty && weekSnaps.last.rp == liveRp)
          ? weekSnaps
          : [...weekSnaps, livePoint];
    } else {
      displaySnaps = weekSnaps;
    }

    final delta = weekDelta(
      widget.snapshots,
      week,
      currentRp: isCurrentSeason ? widget.currentRp : null,
    );
    final allSeasonsSorted = _effectiveAllSeasons.values.toList()
      ..sort((a, b) => b.start.compareTo(a.start));

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: title + season selector ──────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
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
              _SeasonPicker(
                selectedId: season.id,
                seasons: allSeasonsSorted,
                onSelected: _onSeasonSelected,
              ),
            ],
          ),

          const SizedBox(height: AppTheme.xs),

          // ── Week date range + delta badge ─────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_fmtDate(week.start)} – ${_fmtDate(week.end)}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
              if (delta != null)
                _DeltaBadge(delta: delta),
            ],
          ),

          const SizedBox(height: AppTheme.md),

          // ── Chart area ────────────────────────────────────────────────────
          SizedBox(
            height: 110,
            child: displaySnaps.isEmpty
                ? const Center(
                    child: Text(
                      'No sessions recorded this week',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  )
                : _buildChart(displaySnaps),
          ),

          const SizedBox(height: AppTheme.md),
          const Divider(color: AppTheme.surface2, height: 1),
          const SizedBox(height: AppTheme.md),

          // ── Week tab strip ────────────────────────────────────────────────
          _WeekTabStrip(
            weeks: weeks,
            selectedIndex: weekIdx,
            isCurrentSeason: isCurrentSeason,
            onSelected: (i) => setState(() => _selectedWeekIndex = i),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<StatSnapshot> snaps) {
    final spots = snaps.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.rp.toDouble());
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.surface2,
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final idx =
                  s.x.isNaN ? 0 : s.x.toInt().clamp(0, snaps.length - 1);
              final snap = snaps[idx];
              return LineTooltipItem(
                '${formatNumber(snap.rp)} RP\n${DateFormat('MMM d, h:mm a').format(snap.timestamp)}',
                const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 11,
                ),
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
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3,
                color: AppTheme.accent,
                strokeColor: AppTheme.surface,
                strokeWidth: 1.5,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.accent.withAlpha(40),
            ),
            isCurved: spots.length >= 2,
            curveSmoothness: 0.3,
          ),
        ],
      ),
    );
  }

  Widget _buildNoSeason() {
    return const SurfaceCard(
      padding: EdgeInsets.all(AppTheme.md),
      child: Text(
        'Ranked Point History',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.muted,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static String _fmtDate(DateTime dt) => DateFormat('MMM d').format(dt);
}

// ── Season picker ─────────────────────────────────────────────────────────────

class _SeasonPicker extends StatelessWidget {
  final String selectedId;
  final List<SeasonMeta> seasons;
  final ValueChanged<String> onSelected;

  const _SeasonPicker({
    required this.selectedId,
    required this.seasons,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('No seasons'),
      );
    }

    final selected = seasons.firstWhere(
      (s) => s.id == selectedId,
      orElse: () => seasons.first,
    );
    final hasChoice = seasons.length > 1;

    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selected.displayName,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.arrow_drop_down,
            size: 14,
            color: hasChoice ? AppTheme.accent : AppTheme.accent.withAlpha(120),
          ),
        ],
      ),
    );

    if (!hasChoice) return label;

    return PopupMenuButton<String>(
      initialValue: selectedId,
      onSelected: onSelected,
      color: AppTheme.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      itemBuilder: (_) => seasons
          .map(
            (s) => PopupMenuItem<String>(
              value: s.id,
              child: Text(
                s.displayName,
                style: TextStyle(
                  fontSize: 13,
                  color: s.id == selectedId
                      ? AppTheme.accent
                      : AppTheme.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
      child: label,
    );
  }
}

// ── Delta badge ───────────────────────────────────────────────────────────────

class _DeltaBadge extends StatelessWidget {
  final int delta;
  const _DeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    final isPos = delta >= 0;
    final color = isPos ? AppTheme.green : AppTheme.red;
    final sign = isPos ? '+' : '-';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        '$sign${formatNumber(delta.abs())} RP this week',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Week tab strip ────────────────────────────────────────────────────────────

class _WeekTabStrip extends StatefulWidget {
  final List<WeekRange> weeks;
  final int selectedIndex;
  final bool isCurrentSeason;
  final ValueChanged<int> onSelected;

  const _WeekTabStrip({
    required this.weeks,
    required this.selectedIndex,
    required this.isCurrentSeason,
    required this.onSelected,
  });

  @override
  State<_WeekTabStrip> createState() => _WeekTabStripState();
}

class _WeekTabStripState extends State<_WeekTabStrip> {
  late ScrollController _scroll;

  // Approximate rendered width of each chip: label text (~28px) + horizontal
  // padding (8px each side) + inter-chip margin (2px) = ~46px.
  static const double _chipWidth = 46;
  // Scroll offset subtracted so the selected chip lands near the left edge
  // rather than at the very start of the viewport (~80px visible lead-in).
  static const double _chipScrollLeadIn = 80;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(_WeekTabStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) _scrollToSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!_scroll.hasClients) return;
    final offset =
        (widget.selectedIndex * _chipWidth - _chipScrollLeadIn).clamp(0.0, double.infinity);
    _scroll.animateTo(
      offset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Center(
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.weeks.length, (i) {
            final week = widget.weeks[i];
            final isFuture =
                widget.isCurrentSeason && now.isBefore(week.start);
            final isSelected = i == widget.selectedIndex;

            return GestureDetector(
              onTap: isFuture ? null : () => widget.onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent
                      : isFuture
                          ? AppTheme.surface2.withAlpha(80)
                          : AppTheme.surface2,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'W${i + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : isFuture
                            ? AppTheme.muted.withAlpha(80)
                            : AppTheme.muted,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
