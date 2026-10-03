import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/theme.dart';
import 'history_filter.dart';
import 'match_history_items.dart';
import 'match_history_list.dart';

/// History tab: every match in the selected period (ranked + casual), grouped by
/// day with session breaks. A mode filter scopes the list; tap a row for the
/// full match detail.
class RankedMatchList extends StatefulWidget {
  final List<RankedMatch> matches; // all-in-period, newest first
  final Future<void> Function() onRefresh;

  const RankedMatchList({
    super.key,
    required this.matches,
    required this.onRefresh,
  });

  @override
  State<RankedMatchList> createState() => _RankedMatchListState();
}

class _RankedMatchListState extends State<RankedMatchList> {
  // Defaults to Ranked — it's the headline view; the rest is in the sheet.
  HistoryFilter _filter = const HistoryFilter();
  _HistorySort _sort = _HistorySort.date;

  List<RankedMatch> get _visible => _filter.apply(widget.matches);

  MatchGrouping? get _grouping => switch (_sort) {
    _HistorySort.date => null,
    _HistorySort.legend => MatchGrouping(
      keyOf: (m) => m.legend,
      nameOf: (m) => m.legend,
    ),
    _HistorySort.map => MatchGrouping(
      keyOf: (m) => m.mapKey,
      nameOf: (m) => battleRoyaleMapName(m.mapKey),
    ),
  };

  @override
  Widget build(BuildContext context) {
    return MatchHistoryList(
      matches: _visible,
      onRefresh: widget.onRefresh,
      emptyLabel: 'No games in this filter',
      grouping: _grouping,
      // The whole period, not the filtered view: a legend's average shouldn't
      // shrink because the list is filtered to one map.
      averagePool: widget.matches,
      header: _HistoryControls(
        filter: _filter,
        sort: _sort,
        onFilterTap: () => showHistoryFilterSheet(
          context,
          filter: _filter,
          pool: widget.matches,
          onChanged: (f) => setState(() => _filter = f),
        ),
        onSortTap: () => setState(() => _sort = _nextSort(_sort)),
      ),
    );
  }
}

// ── Filter bar ──────────────────────────────────────────────────────────────

enum _HistorySort { date, legend, map }

const _sortLabels = {
  _HistorySort.date: 'Date',
  _HistorySort.legend: 'Legend',
  _HistorySort.map: 'Map',
};

const _sortIcons = {
  _HistorySort.date: Icons.calendar_today,
  _HistorySort.legend: Icons.person_outline,
  _HistorySort.map: Icons.map_outlined,
};

_HistorySort _nextSort(_HistorySort s) => switch (s) {
  _HistorySort.date => _HistorySort.legend,
  _HistorySort.legend => _HistorySort.map,
  _HistorySort.map => _HistorySort.date,
};

/// History control strip: filter pill pinned left, sort pill pinned right.
/// Both cycle on tap, mirroring the Legends/Maps sort control's pill styling.
class _HistoryControls extends StatelessWidget {
  final HistoryFilter filter;
  final _HistorySort sort;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  const _HistoryControls({
    required this.filter,
    required this.sort,
    required this.onFilterTap,
    required this.onSortTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.md,
        AppTheme.sm,
        AppTheme.md,
        AppTheme.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.surface2)),
      ),
      child: Row(
        children: [
          _ControlPill(
            icon: Icons.tune,
            label: filter.activeCount == 0
                ? 'Filter'
                : 'Filter · ${filter.activeCount}',
            onTap: onFilterTap,
          ),
          const Spacer(),
          _ControlPill(
            prefix: 'Sort:',
            icon: _sortIcons[sort]!,
            label: _sortLabels[sort]!,
            onTap: onSortTap,
          ),
        ],
      ),
    );
  }
}

/// A labelled, cycling pill: `prefix [icon value]`.
class _ControlPill extends StatelessWidget {
  final String? prefix;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlPill({
    this.prefix,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix != null) ...[
          Text(
            prefix!,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(width: 4),
        ],
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
                Icon(icon, size: 13, color: AppTheme.accent),
                const SizedBox(width: 4),
                Text(
                  label,
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
