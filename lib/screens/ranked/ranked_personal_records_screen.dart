import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../constants/map_constants.dart';
import '../../models/ranked_match.dart';
import '../../providers/ranked_provider.dart';
import '../../utils/formatting/format.dart' show formatNumber, formatSigned;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/ranked/ranked_period.dart' show RankedSplitBucket;
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import 'ranked_compare_tab.dart';

final _dateFmt = DateFormat('MMM d, h:mm a');

/// Entry point for the Personal Records screen: standout single-game and
/// win-streak stats. Hides itself when there are no ranked matches to draw
/// records from. Session-over-session trends live on Performance Trends
/// instead (see RankedTimeBreakdownScreen) — this page is about peaks, not
/// ongoing patterns.
class RankedPersonalRecordsEntry extends StatelessWidget {
  final String uid;
  final List<RankedMatch> matches;
  final List<RankedSplitBucket> splits;
  const RankedPersonalRecordsEntry({
    super.key,
    required this.uid,
    required this.matches,
    required this.splits,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedPersonalRecordsScreen(
              uid: uid,
              matches: matches,
              splits: splits,
            ),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 18,
                color: AppTheme.accent,
              ),
              SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  'Personal Records',
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

class RankedPersonalRecordsScreen extends StatelessWidget {
  final String uid;
  final List<RankedMatch> matches;
  final List<RankedSplitBucket> splits;
  const RankedPersonalRecordsScreen({
    super.key,
    required this.uid,
    required this.matches,
    required this.splits,
  });

  @override
  Widget build(BuildContext context) {
    final records = personalRecords(matches);

    return Scaffold(
      appBar: AppBar(title: const Text('Personal Records')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            ..._recordCards(
              bestRpGame: records.bestRpGame,
              bestKillsGame: records.bestKillsGame,
              bestDamageGame: records.bestDamageGame,
            ),
            const SizedBox(height: AppTheme.md),
            _StreakCard(
              currentStreak: records.currentWinStreak,
              currentStreakStart: records.currentStreakStart,
              bestStreak: records.bestWinStreak,
              bestStreakStart: records.bestStreakStart,
            ),
            const SizedBox(height: AppTheme.lg),
            const Divider(color: AppTheme.surface2, height: 1),
            const SizedBox(height: AppTheme.lg),
            const Row(
              children: [
                Icon(Icons.compare_arrows, size: 18, color: AppTheme.accent),
                SizedBox(width: AppTheme.sm),
                Text(
                  'Split Comparison',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.md),
            RankedCompareTab(uid: uid, splits: splits),
          ],
        ),
      ),
    );
  }
}

/// Entry point for the Lifetime-scope "Personal Best": the same three
/// standout-game cards as [RankedPersonalRecordsScreen], fed by
/// [rankedPersonalBestProvider]'s SQL queries instead of hydrated matches.
/// No streaks or trends — those need chronological match/session data that
/// Lifetime deliberately never loads.
class RankedPersonalBestEntry extends StatelessWidget {
  final String uid;
  const RankedPersonalBestEntry({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RankedPersonalBestScreen(uid: uid)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 18,
                color: AppTheme.accent,
              ),
              SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  'Personal Best',
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

class RankedPersonalBestScreen extends ConsumerWidget {
  final String uid;
  const RankedPersonalBestScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bestAsync = ref.watch(rankedPersonalBestProvider(uid));
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Best')),
      body: SafeArea(
        child: bestAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
          error: (_, _) => const Center(
            child: Text(
              'Couldn\'t load personal bests.',
              style: TextStyle(color: AppTheme.muted),
            ),
          ),
          data: (best) => ListView(
            padding: const EdgeInsets.all(AppTheme.md),
            children: _recordCards(
              bestRpGame: best.bestRpGame,
              bestKillsGame: best.bestKillsGame,
              bestDamageGame: best.bestDamageGame,
            ),
          ),
        ),
      ),
    );
  }
}

/// The three standout-game cards (RP, kills, damage), shared by the split
/// scope's [RankedPersonalRecordsScreen] and the Lifetime scope's
/// [RankedPersonalBestScreen].
List<Widget> _recordCards({
  required RankedMatch? bestRpGame,
  required RankedMatch? bestKillsGame,
  required RankedMatch? bestDamageGame,
}) {
  return [
    _RecordCard(
      icon: Icons.bolt,
      label: 'Most RP Gained',
      match: bestRpGame,
      value: bestRpGame == null
          ? null
          : formatSigned(bestRpGame.effectiveRpChange.toDouble()),
    ),
    const SizedBox(height: AppTheme.md),
    _RecordCard(
      icon: Icons.sports_kabaddi,
      label: 'Most Kills',
      match: bestKillsGame,
      // Guards the *stat*, not the match. kills is nullable ("upstream
      // reported no tracker"), so a match can exist with nothing to show here.
      // Both sources already exclude those games, but checking only the match
      // is what let a null stat reach `!` and crash this screen once.
      value: bestKillsGame?.kills == null
          ? null
          : '${formatNumber(bestKillsGame!.kills!)} kills',
    ),
    const SizedBox(height: AppTheme.md),
    _RecordCard(
      icon: Icons.local_fire_department,
      label: 'Most Damage',
      match: bestDamageGame,
      // Same nullable-stat guard as Most Kills above.
      value: bestDamageGame?.damage == null
          ? null
          : '${formatNumber(bestDamageGame!.damage!)} damage',
    ),
  ];
}

/// One standout-game card: value on top, the match it came from underneath.
/// Shows a "No data yet" placeholder when [match] is null (no ranked match
/// in range reported this tracker).
class _RecordCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final RankedMatch? match;
  final String? value;

  const _RecordCard({
    required this.icon,
    required this.label,
    required this.match,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final m = match;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.accent),
          const SizedBox(width: AppTheme.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value ?? 'No data yet',
                  style: TextStyle(
                    color: value == null
                        ? AppTheme.muted
                        : AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (m != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${m.legend} · ${battleRoyaleMapName(m.mapKey)} · '
                    '${_dateFmt.format(m.endTime.toLocal())}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Win-streak card: headline is the best-ever streak with its start date
/// (e.g. "since August 5th, 2023"); a secondary line shows the current
/// streak, or confirms it's tied with the best.
class _StreakCard extends StatelessWidget {
  final int currentStreak;
  final DateTime? currentStreakStart;
  final int bestStreak;
  final DateTime? bestStreakStart;

  const _StreakCard({
    required this.currentStreak,
    required this.currentStreakStart,
    required this.bestStreak,
    required this.bestStreakStart,
  });

  @override
  Widget build(BuildContext context) {
    final isPersonalBest = currentStreak > 0 && currentStreak == bestStreak;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Row(
        children: [
          const Icon(Icons.military_tech, size: 20, color: AppTheme.accent),
          const SizedBox(width: AppTheme.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Best Win Streak',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      bestStreak > 0 ? '$bestStreak games' : 'No streak yet',
                      style: TextStyle(
                        color: bestStreak > 0
                            ? AppTheme.textPrimary
                            : AppTheme.muted,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (bestStreak > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        'since ${_formatStreakDate(bestStreakStart!)}',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppTheme.sm),
                Row(
                  children: [
                    Icon(
                      isPersonalBest
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: isPersonalBest ? AppTheme.green : AppTheme.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPersonalBest
                          ? 'You\'re on it now!'
                          : currentStreak > 0
                          ? 'Currently on a $currentStreak-game streak'
                          : 'No active streak right now',
                      style: TextStyle(
                        color: isPersonalBest ? AppTheme.green : AppTheme.muted,
                        fontSize: 12,
                        fontWeight: isPersonalBest
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatStreakDate(DateTime d) {
  final local = d.toLocal();
  return '${DateFormat('MMMM').format(local)} ${_ordinal(local.day)}, ${local.year}';
}

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}
