import 'package:flutter/material.dart';
import '../../../constants/ranked_map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/theme.dart';
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

enum _Filter { all, ranked, casual }

class _RankedMatchListState extends State<RankedMatchList> {
  // Default to Ranked — it's the headline view; All/Casual are one tap away.
  _Filter _filter = _Filter.ranked;
  _HistorySort _sort = _HistorySort.date;

  List<RankedMatch> get _visible => switch (_filter) {
        _Filter.all => widget.matches,
        _Filter.ranked => widget.matches.where((m) => m.isRanked).toList(),
        _Filter.casual => widget.matches.where((m) => !m.isRanked).toList(),
      };

  MatchGrouping? get _grouping => switch (_sort) {
        _HistorySort.date => null,
        _HistorySort.legend => MatchGrouping(
            keyOf: (m) => m.legend,
            nameOf: (m) => m.legend,
          ),
        _HistorySort.map => MatchGrouping(
            keyOf: (m) => m.mapKey,
            nameOf: (m) => rankedMapName(m.mapKey),
          ),
      };

  @override
  Widget build(BuildContext context) {
    return MatchHistoryList(
      matches: _visible,
      onRefresh: widget.onRefresh,
      emptyLabel: 'No games in this filter',
      grouping: _grouping,
      header: _HistoryControls(
        filter: _filter,
        sort: _sort,
        onFilterTap: () => setState(() => _filter = _nextFilter(_filter)),
        onSortTap: () => setState(() => _sort = _nextSort(_sort)),
      ),
    );
  }
}

// ── Filter bar ──────────────────────────────────────────────────────────────

const _filterLabels = {
  _Filter.all: 'All',
  _Filter.ranked: 'Ranked',
  _Filter.casual: 'Casual',
};

const _filterIcons = {
  _Filter.all: Icons.filter_list,
  _Filter.ranked: Icons.military_tech,
  _Filter.casual: Icons.sports_esports,
};

// Cycle starts on Ranked (the default), then All, then Casual.
_Filter _nextFilter(_Filter f) => switch (f) {
  _Filter.ranked => _Filter.all,
  _Filter.all => _Filter.casual,
  _Filter.casual => _Filter.ranked,
};

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
  final _Filter filter;
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
          AppTheme.md, AppTheme.sm, AppTheme.md, AppTheme.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.surface2)),
      ),
      child: Row(
        children: [
          _ControlPill(
            prefix: 'Filter:',
            icon: _filterIcons[filter]!,
            label: _filterLabels[filter]!,
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
  final String prefix;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlPill({
    required this.prefix,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(prefix, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(width: 4),
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
