import 'package:flutter/material.dart';
import '../../models/ranked_match.dart';
import '../../utils/theme.dart';
import 'widgets/match_history_items.dart';
import 'widgets/match_history_list.dart';
import '../../widgets/control_pill.dart';

/// Full-screen ranked history for a single legend or map, reached by tapping a
/// card in the Legends/Maps tabs. Shows the same session-grouped rows as the
/// History tab, but pre-filtered to one entity (ranked games only, matching the
/// breakdown it was opened from).
///
/// A sort toggle switches between session grouping (default) and grouping by a
/// secondary entity — maps within a legend, or legends within a map — turning
/// the page into a focused mini-breakdown.
class RankedEntityHistoryScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<RankedMatch> matches; // pre-filtered, newest first
  final Future<void> Function() onRefresh;

  /// Lower-case noun for the secondary grouping, e.g. 'map' or 'legend'.
  final String groupLabel;

  /// How to section matches when grouped mode is active. Null for a page with
  /// nothing to group by (a single legend on a single map), which then has no
  /// sort toggle.
  final MatchGrouping? grouping;

  /// The scope's full history (newest first), which sessions are found over.
  /// Null for Lifetime: break rows are then hidden.
  final List<RankedMatch>? sessionPool;

  /// Told of a correction made on this page, for whoever opened it to keep
  /// its own figures in step.
  final ValueChanged<RankedMatch>? onMatchUpdated;

  const RankedEntityHistoryScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.matches,
    required this.onRefresh,
    this.groupLabel = '',
    this.grouping,
    this.sessionPool,
    this.onMatchUpdated,
  });

  @override
  State<RankedEntityHistoryScreen> createState() =>
      _RankedEntityHistoryScreenState();
}

class _RankedEntityHistoryScreenState extends State<RankedEntityHistoryScreen> {
  bool _grouped = false;

  // This screen is pushed with a one-time snapshot of matches (the caller has
  // already filtered it to one legend/map/session), not a live provider
  // watch. Held locally so a correction made on this page can be reflected
  // immediately via [_onMatchUpdated] instead of only after leaving and
  // reopening the page.
  late List<RankedMatch> _matches;

  @override
  void initState() {
    super.initState();
    _matches = widget.matches;
  }

  void _onMatchUpdated(RankedMatch updated) {
    setState(() {
      _matches = [
        for (final m in _matches)
          if (m.id == updated.id) updated else m,
      ];
    });
    widget.onMatchUpdated?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 17)),
            Text(
              widget.subtitle,
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
          grouping: _grouped ? widget.grouping : null,
          onMatchUpdated: _onMatchUpdated,
          sessionPool: widget.sessionPool,
          showBreaks: widget.sessionPool != null,
          collapseScope: widget.title,
          // A legend's page holds all its games, so the comparison has the
          // history it needs; a map's page only has one map's worth of each
          // legend, which would skew the average.
          averagePool: widget.groupLabel == 'map' ? _matches : null,
          header: widget.grouping == null
              ? null
              : _SortToggle(
                  grouped: _grouped,
                  groupLabel: widget.groupLabel,
                  onTap: () => setState(() => _grouped = !_grouped),
                ),
        ),
      ),
    );
  }
}

/// Cycling "Sort:" pill. Toggles between date grouping and the
/// secondary-entity grouping.
class _SortToggle extends StatelessWidget {
  final bool grouped;
  final String groupLabel;
  final VoidCallback onTap;
  const _SortToggle({
    required this.grouped,
    required this.groupLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = grouped ? 'By $groupLabel' : 'Date';
    final icon = grouped ? Icons.category_outlined : Icons.calendar_today;
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
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ControlPill(
            prefix: 'Sort:',
            icon: icon,
            label: label,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}
