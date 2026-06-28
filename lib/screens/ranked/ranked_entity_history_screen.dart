import 'package:flutter/material.dart';
import '../../models/ranked_match.dart';
import '../../utils/theme.dart';
import 'widgets/ranked_match_list.dart';

/// Full-screen ranked history for a single legend or map, reached by tapping a
/// card in the Legends/Maps tabs. Shows the same day-grouped rows as the
/// History tab, but pre-filtered to one entity (ranked games only, matching the
/// breakdown it was opened from).
///
/// A sort toggle switches between date grouping (default) and grouping by a
/// secondary entity — maps within a legend, or legends within a map — turning
/// the page into a focused mini-breakdown.
class RankedEntityHistoryScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<RankedMatch> matches; // pre-filtered, newest first
  final Future<void> Function() onRefresh;

  /// Lower-case noun for the secondary grouping, e.g. 'map' or 'legend'.
  final String groupLabel;

  /// How to section matches when grouped mode is active.
  final MatchGrouping grouping;

  const RankedEntityHistoryScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.matches,
    required this.onRefresh,
    required this.groupLabel,
    required this.grouping,
  });

  @override
  State<RankedEntityHistoryScreen> createState() =>
      _RankedEntityHistoryScreenState();
}

class _RankedEntityHistoryScreenState extends State<RankedEntityHistoryScreen> {
  bool _grouped = false;

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
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: MatchHistoryList(
          matches: widget.matches,
          onRefresh: widget.onRefresh,
          emptyLabel: 'No ranked games here',
          grouping: _grouped ? widget.grouping : null,
          header: _SortToggle(
            grouped: _grouped,
            groupLabel: widget.groupLabel,
            onTap: () => setState(() => _grouped = !_grouped),
          ),
        ),
      ),
    );
  }
}

/// Cycling "Sort:" pill mirroring the Legends/Maps sort control. Toggles between
/// date grouping and the secondary-entity grouping.
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
          AppTheme.md, AppTheme.sm, AppTheme.md, AppTheme.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.surface2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('Sort:',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
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
      ),
    );
  }
}
