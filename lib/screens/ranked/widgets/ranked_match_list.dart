import 'package:flutter/material.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/theme.dart';
import 'history_filter.dart';
import 'match_history_items.dart';
import 'match_history_list.dart';
import '../../../widgets/control_pill.dart';

/// History tab: every match in the selected period (ranked + casual), grouped by
/// play session with day dividers. A mode filter scopes the list; tap a row for the
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
    _HistorySort.legend => MatchGrouping.byLegend,
    _HistorySort.map => MatchGrouping.byMap,
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
      // Sessions come from every game played, so the filter hides games
      // without reshaping them.
      sessionPool: widget.matches,
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
          ControlPill(
            icon: Icons.tune,
            label: filter.activeCount == 0
                ? 'Filter'
                : 'Filter · ${filter.activeCount}',
            onTap: onFilterTap,
          ),
          const Spacer(),
          ControlPill(
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
