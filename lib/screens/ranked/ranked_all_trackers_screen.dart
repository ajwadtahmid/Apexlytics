import 'package:flutter/material.dart';
import '../../models/player_stats.dart';
import '../../utils/theme.dart';
import '../../widgets/player_stats_tabs.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/tracker_info_sheet.dart';

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
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedAllTrackersScreen(
              legendStats: legendStats,
              legendStack: legendStack,
            ),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(Icons.bar_chart_outlined, size: 18, color: AppTheme.accent),
              SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  'All Trackers',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
            ],
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
