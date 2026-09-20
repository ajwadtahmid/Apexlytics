import 'package:flutter/material.dart';
import '../../models/player_stats.dart';
import '../../models/season_meta.dart';
import '../../utils/formatting/snapshot_types.dart';
import '../../utils/theme.dart';
import '../../widgets/graph_card.dart';
import '../../widgets/player_stats_tabs.dart';
import '../../widgets/surface_card.dart';

/// Reached from Ranked's empty states while match history hasn't arrived
/// yet. Shows the snapshot-based RP graph (device-local RP samples) and All
/// Trackers (career-lifetime legend/weapon stats from the live player-stats
/// API) — neither depends on the match history the Ranked tab is waiting on.
/// Each section falls back to [_EmptySection] when its own data hasn't
/// accumulated yet, rather than rendering blank.
class RankedAvailableNowScreen extends StatelessWidget {
  final List<StatSnapshot> snapshots;
  final SeasonMeta? currentSeason;
  final Map<String, SeasonMeta> allSeasons;
  final int? currentRp;
  final List<LegendStat> legendStats;
  final List<String> legendStack;

  const RankedAvailableNowScreen({
    super.key,
    required this.snapshots,
    required this.currentSeason,
    required this.allSeasons,
    required this.currentRp,
    required this.legendStats,
    required this.legendStack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Available Now')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            const Text(
              'These don\'t need match history, so they\'re ready while '
              'ranked tracking warms up.',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.md),
            if (snapshots.isEmpty)
              const _EmptySection(
                icon: Icons.show_chart,
                text: 'Your RP graph fills in as you play with the app open.',
              )
            else
              GraphCard(
                snapshots: snapshots,
                currentSeason: currentSeason,
                allSeasons: allSeasons,
                currentRp: currentRp,
              ),
            const SizedBox(height: AppTheme.md),
            if (legendStats.isEmpty)
              const _EmptySection(
                icon: Icons.bar_chart_outlined,
                text: 'Tracker stats appear once you\'ve played a match.',
              )
            else
              PlayerStatsTabs(
                legendStats: legendStats,
                legendStack: legendStack,
              ),
            const SizedBox(height: AppTheme.lg),
          ],
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptySection({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.lg),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.muted, size: 28),
          const SizedBox(height: AppTheme.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
