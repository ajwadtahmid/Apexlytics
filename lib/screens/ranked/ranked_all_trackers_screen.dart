import 'package:flutter/material.dart';
import '../../models/player_stats.dart';
import '../../utils/theme.dart';
import '../../widgets/player_stats_tabs.dart';
import '../../widgets/tracker_info_sheet.dart';
import '../../widgets/nav_entry_card.dart';

/// Entry point for the full Legends/Guns tracker breakdown — out of the main
/// Overview list, same pattern as the other Ranked drill-downs, so it doesn't
/// compete for space there.
class RankedAllTrackersEntry extends StatelessWidget {
  final List<LegendStat> legendStats;
  final List<String> legendStack;

  const RankedAllTrackersEntry({
    super.key,
    required this.legendStats,
    this.legendStack = const [],
  });

  @override
  Widget build(BuildContext context) {
    return NavEntryCard(
      icon: Icons.bar_chart_outlined,
      title: 'All Trackers',
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedAllTrackersScreen(
              legendStats: legendStats,
              legendStack: legendStack,
            ),
          ),
        ),
    );
  }
}

/// Full-screen Legends/Guns tracker breakdown — the same [PlayerStatsTabs] My
/// Stats used to show inline, now reached from Ranked's Overview instead.
class RankedAllTrackersScreen extends StatelessWidget {
  final List<LegendStat> legendStats;
  final List<String> legendStack;

  const RankedAllTrackersScreen({
    super.key,
    required this.legendStats,
    this.legendStack = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Trackers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Tracker info',
            onPressed: () => showTrackerInfoSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            PlayerStatsTabs(legendStats: legendStats, legendStack: legendStack),
          ],
        ),
      ),
    );
  }
}
