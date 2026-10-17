import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../constants/map_constants.dart';
import '../../models/player_stats.dart';
import '../../models/ranked_match.dart';
import '../../providers/ranked_provider.dart';
import '../../utils/formatting/format.dart'
    show
        formatDuration,
        formatNumber,
        formatNumberOrNone,
        formatSessionSpan,
        formatShortDateTime,
        formatSigned,
        formatSignedInt,
        plural;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/nav_entry_card.dart';
import '../../widgets/share_card.dart';
import 'widgets/ranked_share_cards.dart';

/// Entry point for the Records & Share screen: standout single-game and
/// win-streak stats, and the cards that can be shared. Hides itself when there
/// are no ranked matches to draw records from. Session-over-session trends live
/// on Performance Trends instead (see RankedTimeBreakdownScreen); this page is
/// about peaks, not ongoing patterns.
class RankedPersonalRecordsEntry extends StatelessWidget {
  final PlayerStats stats;
  final List<RankedMatch> matches;
  final List<RankedSession> sessions;

  /// False for a past week or split, whose last streak ended then.
  final bool live;
  const RankedPersonalRecordsEntry({
    super.key,
    required this.stats,
    required this.matches,
    required this.sessions,
    this.live = true,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();

    return NavEntryCard(
      icon: Icons.emoji_events_outlined,
      title: 'Records & Share',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RankedPersonalRecordsScreen(
            stats: stats,
            matches: matches,
            sessions: sessions,
            live: live,
          ),
        ),
      ),
    );
  }
}

class RankedPersonalRecordsScreen extends StatelessWidget {
  final PlayerStats stats;
  final List<RankedMatch> matches;
  final List<RankedSession> sessions;

  /// See [RankedPersonalRecordsEntry.live].
  final bool live;
  const RankedPersonalRecordsScreen({
    super.key,
    required this.stats,
    required this.matches,
    required this.sessions,
    this.live = true,
  });

  @override
  Widget build(BuildContext context) {
    final records = personalRecords(matches);
    final summary = summarize(rankedOnly(matches));

    return Scaffold(
      appBar: AppBar(title: const Text('Records & Share')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            ..._recordCards(
              bestRpGame: records.bestRpGame,
              bestKillsGame: records.bestKillsGame,
              bestDamageGame: records.bestDamageGame,
              playerName: stats.name,
              averages: (
                rp: summary.avgRpPerGame,
                kills: summary.avgKills,
                damage: summary.avgDamage,
              ),
            ),
            const SizedBox(height: AppTheme.md),
            _SessionRecordCard(
              session: ([
                ...sessions,
              ]..sort((a, b) => b.netRp.compareTo(a.netRp))).firstOrNull,
              playerName: stats.name,
            ),
            const SizedBox(height: AppTheme.md),
            _StreakCard(
              currentStreak: records.currentWinStreak,
              bestStreak: records.bestWinStreak,
              bestStreakStart: records.bestStreakStart,
              streakMatches: records.bestStreakMatches,
              live: live,
              playerName: stats.name,
            ),
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
    return NavEntryCard(
      icon: Icons.emoji_events_outlined,
      title: 'Personal Best',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RankedPersonalBestScreen(uid: uid)),
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
///
/// [playerName] is offered on the shared card; null (the Lifetime screen, which
/// has no player at hand) shares it without a name.
List<Widget> _recordCards({
  required RankedMatch? bestRpGame,
  required RankedMatch? bestKillsGame,
  required RankedMatch? bestDamageGame,
  String? playerName,
  ({double rp, double? kills, double? damage})? averages,
}) {
  return [
    _RecordCard(
      icon: Icons.bolt,
      label: 'Most RP Gained',
      match: bestRpGame,
      playerName: playerName,
      shareDrops: 'RP',
      shareValue: bestRpGame == null
          ? null
          : formatSignedInt(bestRpGame.effectiveRpChange),
      shareUnit: 'RP',
      comparison: bestRpGame == null || averages == null
          ? null
          : _vsAverage(
              bestRpGame.effectiveRpChange,
              averages.rp,
              '${formatSigned(averages.rp)} RP per game',
            ),
      value: bestRpGame == null
          ? null
          : formatSignedInt(bestRpGame.effectiveRpChange),
    ),
    const SizedBox(height: AppTheme.md),
    _RecordCard(
      icon: Icons.sports_kabaddi,
      label: 'Most Kills',
      match: bestKillsGame,
      playerName: playerName,
      shareDrops: 'Kills',
      shareValue: bestKillsGame?.kills == null
          ? null
          : formatNumber(bestKillsGame!.kills!),
      shareUnit: 'kills',
      comparison: bestKillsGame?.kills == null || averages?.kills == null
          ? null
          : _vsAverage(
              bestKillsGame!.kills!,
              averages!.kills,
              '${averages.kills!.toStringAsFixed(1)} kills per game',
            ),
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
      playerName: playerName,
      shareDrops: 'Damage',
      shareValue: bestDamageGame?.damage == null
          ? null
          : formatNumber(bestDamageGame!.damage!),
      shareUnit: 'damage',
      comparison: bestDamageGame?.damage == null || averages?.damage == null
          ? null
          : _vsAverage(
              bestDamageGame!.damage!,
              averages!.damage,
              '${formatNumber(averages.damage!.round())} damage per game',
            ),
      // Same nullable-stat guard as Most Kills above.
      value: bestDamageGame?.damage == null
          ? null
          : '${formatNumber(bestDamageGame!.damage!)} damage',
    ),
  ];
}

/// How [value] compares with the player's [average] for the period: a multiple
/// when both are positive, otherwise the average itself, written as
/// [averageText] ("3.1 kills per game"). Null when there is no average.
String? _vsAverage(num value, double? average, String averageText) {
  if (average == null) return null;
  if (average > 0 && value > 0) {
    return '${(value / average).toStringAsFixed(1)}× your average';
  }
  return 'Your average: $averageText';
}

/// One standout-game card: value on top, the match it came from underneath.
/// Shows a "No data yet" placeholder when [match] is null (no ranked match
/// in range reported this tracker).
class _RecordCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final RankedMatch? match;
  final String? value;
  final String? playerName;

  /// The figure the record is about, left out of the shared card's stats since
  /// the card already leads with it.
  final String? shareDrops;

  /// The figure and unit on the shared card, and its chip in context. The figure
  /// is split from the unit so the card can set them in different sizes.
  final String? shareValue;
  final String? shareUnit;
  final String? comparison;

  const _RecordCard({
    required this.icon,
    required this.label,
    required this.match,
    required this.value,
    this.playerName,
    this.shareDrops,
    this.shareValue,
    this.shareUnit,
    this.comparison,
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
                Text(label, style: AppTheme.captionSmall),
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
                    '${formatShortDateTime(m.endTime)}',
                    style: AppTheme.caption,
                  ),
                ],
              ],
            ),
          ),
          if (m != null && value != null)
            _ShareButton(
              title: label,
              playerName: playerName,
              card: (name) => RecordShareCard(
                record: label,
                value: shareValue ?? value!,
                unit: shareUnit,
                detail: formatShortDateTime(m.endTime),
                comparison: comparison,
                legend: m.legend,
                playerName: name,
                stats: [
                  (Icons.person_outline, 'Legend', m.legend),
                  (Icons.map_outlined, 'Map', battleRoyaleMapName(m.mapKey)),
                  if (shareDrops != 'RP')
                    (Icons.bolt, 'RP', formatSignedInt(m.effectiveRpChange)),
                  if (shareDrops != 'Kills')
                    (
                      Icons.sports_kabaddi,
                      'Kills',
                      formatNumberOrNone(m.kills),
                    ),
                  if (shareDrops != 'Damage')
                    (
                      Icons.local_fire_department,
                      'Damage',
                      formatNumberOrNone(m.damage),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The share button at the right of a record card. Opens a preview of the card
/// built by [card], given the name to show (null when it is hidden or there is
/// none to offer).
class _ShareButton extends StatelessWidget {
  final String title;
  final String? playerName;
  final Widget Function(String? name) card;
  const _ShareButton({
    required this.title,
    required this.playerName,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.ios_share, size: 20),
      color: AppTheme.muted,
      tooltip: 'Share $title',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShareCardScreen(
            title: title,
            offerNameToggle: playerName != null,
            cardBuilder: (showName) => card(showName ? playerName : null),
          ),
        ),
      ),
    );
  }
}

/// The play session that gained the most RP: the figure in large type, and the
/// games, kills, damage and time behind it. Shows a placeholder with no session.
class _SessionRecordCard extends StatelessWidget {
  final RankedSession? session;
  final String? playerName;
  const _SessionRecordCard({required this.session, this.playerName});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final value = s == null ? null : '${formatSignedInt(s.netRp)} RP';
    final kills = s == null || s.killsGames == 0 ? null : s.totalKills;
    final damage = s == null || s.damageGames == 0 ? null : s.totalDamage;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Row(
        children: [
          const Icon(Icons.timeline, size: 20, color: AppTheme.accent),
          const SizedBox(width: AppTheme.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Best Session', style: AppTheme.captionSmall),
                const SizedBox(height: 2),
                Text(
                  value ?? 'No data yet',
                  style: TextStyle(
                    color: s == null ? AppTheme.muted : AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (s != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${plural(s.games, 'game')} · '
                    '${formatNumberOrNone(kills)} kills · '
                    '${formatNumberOrNone(damage)} dmg',
                    style: AppTheme.caption,
                  ),
                  Text(
                    '${formatSessionSpan(s.start, s.end)} · '
                    '${formatDuration(s.duration.inSeconds)}',
                    style: AppTheme.caption,
                  ),
                ],
              ],
            ),
          ),
          if (s != null)
            _ShareButton(
              title: 'Best Session',
              playerName: playerName,
              card: (name) => RecordShareCard(
                record: 'Best Session',
                value: formatSignedInt(s.netRp),
                unit: 'RP',
                valueColor: AppTheme.signColor(s.netRp >= 0),
                detail: formatSessionSpan(s.start, s.end),
                legend: s.bestLegend,
                playerName: name,
                stats: [
                  (Icons.sports_esports_outlined, 'Games', '${s.games}'),
                  (Icons.sports_kabaddi, 'Kills', formatNumberOrNone(kills)),
                  (
                    Icons.local_fire_department,
                    'Damage',
                    formatNumberOrNone(damage),
                  ),
                  (
                    Icons.schedule,
                    'Time played',
                    formatDuration(s.duration.inSeconds),
                  ),
                  if (s.bestLegend != null)
                    (Icons.person_outline, 'Top legend', s.bestLegend!),
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
  final int bestStreak;
  final DateTime? bestStreakStart;

  /// False for a past week or split: worded in the past tense.
  final bool live;
  final String? playerName;

  /// The games of the best streak, for the shared card.
  final List<RankedMatch> streakMatches;

  const _StreakCard({
    required this.currentStreak,
    required this.bestStreak,
    required this.bestStreakStart,
    required this.live,
    this.playerName,
    this.streakMatches = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isPersonalBest = currentStreak > 0 && currentStreak == bestStreak;
    final statusText = live
        ? (isPersonalBest
              ? 'You\'re on it now!'
              : currentStreak > 0
              ? 'Currently on a $currentStreak-game streak'
              : 'No active streak right now')
        : (isPersonalBest
              ? 'Ended on its best streak'
              : currentStreak > 0
              ? 'Ended on a $currentStreak-game streak'
              : 'Ended without a win streak');

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
                const Text('Best Win Streak', style: AppTheme.captionSmall),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.end,
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
                    if (bestStreak > 0)
                      Text(
                        '${live ? 'since' : 'from'} '
                        '${_formatStreakDate(bestStreakStart!)}',
                        style: AppTheme.caption,
                      ),
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
                    Expanded(
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: isPersonalBest
                              ? AppTheme.green
                              : AppTheme.muted,
                          fontSize: 12,
                          fontWeight: isPersonalBest
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (bestStreak > 0 && streakMatches.isNotEmpty)
            _ShareButton(
              title: 'Best Win Streak',
              playerName: playerName,
              card: (name) =>
                  StreakShareCard(matches: streakMatches, playerName: name),
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
