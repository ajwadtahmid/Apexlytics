import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../constants/map_constants.dart';
import '../../constants/stat_icons.dart';
import '../../models/player_stats.dart';
import '../../models/ranked_match.dart';
import '../../providers/best_metric_provider.dart';
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
import '../../utils/ranked/best_metric.dart';
import '../../utils/ranked/extra_records.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/share_image.dart' show canShareFiles;
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/nav_entry_card.dart';
import '../../widgets/share_card.dart';
import 'ranked_entity_history_screen.dart';
import 'ranked_session_detail_screen.dart';
import 'widgets/match_detail_sheet.dart';
import 'widgets/ranked_share_cards.dart';

/// Entry point for the Personal Records screen: standout single-game and
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

  /// Refreshes the breakdown, for the pages a record opens.
  final Future<void> Function() onRefresh;

  /// The split (and week) on screen, for the title of the card of all records.
  final String scope;
  const RankedPersonalRecordsEntry({
    super.key,
    required this.stats,
    required this.matches,
    required this.sessions,
    required this.onRefresh,
    this.live = true,
    this.scope = 'Ranked',
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();

    return NavEntryCard(
      icon: Icons.emoji_events_outlined,
      title: 'Personal Records',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RankedPersonalRecordsScreen(
            stats: stats,
            matches: matches,
            sessions: sessions,
            live: live,
            onRefresh: onRefresh,
            scope: scope,
          ),
        ),
      ),
    );
  }
}

class RankedPersonalRecordsScreen extends ConsumerStatefulWidget {
  final PlayerStats stats;
  final List<RankedMatch> matches;
  final List<RankedSession> sessions;

  /// See [RankedPersonalRecordsEntry.live].
  final bool live;

  /// See [RankedPersonalRecordsEntry.onRefresh].
  final Future<void> Function() onRefresh;

  /// See [RankedPersonalRecordsEntry.scope].
  final String scope;
  const RankedPersonalRecordsScreen({
    super.key,
    required this.stats,
    required this.matches,
    required this.sessions,
    required this.onRefresh,
    this.live = true,
    this.scope = 'Ranked',
  });

  @override
  ConsumerState<RankedPersonalRecordsScreen> createState() =>
      _RankedPersonalRecordsScreenState();
}

class _RankedPersonalRecordsScreenState
    extends ConsumerState<RankedPersonalRecordsScreen> {
  // Pushed with a snapshot, as the history pages are, and held here so a game
  // corrected from this page moves the records at once.
  late List<RankedMatch> _matches = widget.matches;
  late List<RankedSession> _sessions = widget.sessions;

  void _onMatchUpdated(RankedMatch updated) {
    setState(() {
      _matches = [
        for (final m in _matches)
          if (m.id == updated.id) updated else m,
      ];
      _sessions = sessionize(rankedOnly(_matches));
    });
  }

  Future<void> _openGame(RankedMatch game) async {
    final updated = await showMatchDetailSheet(
      context,
      matches: [game],
      index: 0,
      baselinePool: _matches,
    );
    if (updated != null) _onMatchUpdated(updated);
  }

  void _openSession(RankedSession session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedSessionDetailScreen(
          session: session,
          onRefresh: widget.onRefresh,
          onMatchUpdated: _onMatchUpdated,
        ),
      ),
    );
  }

  void _openStreak(List<RankedMatch> games) {
    final rp = games.fold<int>(0, (a, m) => a + m.effectiveRpChange);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: 'Best Win Streak',
          subtitle:
              '${plural(games.length, 'game')} · ${formatSignedInt(rp)} RP',
          // Newest first, as the history list expects.
          matches: games.reversed.toList(),
          onRefresh: widget.onRefresh,
          onMatchUpdated: _onMatchUpdated,
        ),
      ),
    );
  }

  void _openDay(DayRecord day) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedEntityHistoryScreen(
          title: 'Best Day',
          subtitle:
              '${_dayLabel(day.day)} · ${plural(day.matches.length, 'game')} · '
              '${formatSignedInt(day.netRp)} RP',
          matches: day.matches,
          onRefresh: widget.onRefresh,
          onMatchUpdated: _onMatchUpdated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = personalRecords(_matches);
    final counted = rankedOnly(_matches);
    final summary = summarize(counted);
    // Missing while it loads, or if it can't be read: the notes just don't show.
    final allTime = ref
        .watch(rankedAllTimeBestProvider(widget.stats.uid))
        .asData
        ?.value;
    final bestSession = ([
      ..._sessions,
    ]..sort((a, b) => b.netRp.compareTo(a.netRp))).firstOrNull;
    final bestDayRecord = bestDay(counted);
    // A day that is just the best session would repeat it.
    final day =
        bestDayRecord != null && dayIsSession(bestDayRecord, bestSession)
        ? null
        : bestDayRecord;
    final longest = longestSession(_sessions);
    final comeback = biggestComeback(_sessions);
    final metric = ref.watch(bestMetricProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Personal Records')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            _ShareAllButton(
              playerName: widget.stats.name,
              scope: widget.scope,
              tiles: _recordTiles(
                records: records,
                bestSession: bestSession,
                day: day,
                longest: longest,
                comeback: comeback,
              ),
              legend: records.bestRpGame?.legend,
            ),
            const SizedBox(height: AppTheme.md),
            ..._recordCards(
              bestRpGame: records.bestRpGame,
              bestKillsGame: records.bestKillsGame,
              bestDamageGame: records.bestDamageGame,
              playerName: widget.stats.name,
              averages: (
                rp: summary.avgRpPerGame,
                kills: summary.avgKills,
                damage: summary.avgDamage,
              ),
              allTime: allTime,
              onOpenGame: _openGame,
            ),
            const SizedBox(height: AppTheme.md),
            _SessionRecordCard(
              session: bestSession,
              metric: metric,
              playerName: widget.stats.name,
              onOpen: _openSession,
            ),
            const SizedBox(height: AppTheme.md),
            if (day != null) ...[
              _dayCard(day, metric, widget.stats.name, _openDay),
              const SizedBox(height: AppTheme.md),
            ],
            if (longest != null) ...[
              _longestSessionCard(
                longest,
                metric,
                widget.stats.name,
                _openSession,
              ),
              const SizedBox(height: AppTheme.md),
            ],
            if (comeback != null) ...[
              _comebackCard(comeback, metric, widget.stats.name, _openSession),
              const SizedBox(height: AppTheme.md),
            ],
            _StreakCard(
              currentStreak: records.currentWinStreak,
              bestStreak: records.bestWinStreak,
              bestStreakStart: records.bestStreakStart,
              streakMatches: records.bestStreakMatches,
              live: widget.live,
              playerName: widget.stats.name,
              onOpen: _openStreak,
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
              // An edit made in the sheet refreshes this page through the
              // provider, so nothing is passed back here.
              onOpenGame: (game) =>
                  showMatchDetailSheet(context, matches: [game], index: 0),
            ),
          ),
        ),
      ),
    );
  }
}

/// How a split's record compares with the best over every split: that it is the
/// all-time best, or what the all-time best is. Null with nothing to compare.
({String text, bool isBest})? _allTimeStanding(
  int? value,
  int? allTime,
  String Function(int) format,
) {
  if (value == null || allTime == null) return null;
  return value >= allTime
      ? (text: 'All-time best', isBest: true)
      : (text: 'All-time best: ${format(allTime)}', isBest: false);
}

/// The three standout-game cards (RP, kills, damage), shared by the split
/// scope's [RankedPersonalRecordsScreen] and the Lifetime scope's
/// [RankedPersonalBestScreen].
///
/// [playerName] is offered on the shared card; null (the Lifetime screen, which
/// has no player at hand) shares it without a name. [allTime], when given, sets
/// each record against the best over every split. [onOpenGame] opens the game a
/// record was set in.
List<Widget> _recordCards({
  required RankedMatch? bestRpGame,
  required RankedMatch? bestKillsGame,
  required RankedMatch? bestDamageGame,
  required void Function(RankedMatch game) onOpenGame,
  String? playerName,
  ({double rp, double? kills, double? damage})? averages,
  PersonalBestGames? allTime,
}) {
  return [
    _RecordCard(
      icon: StatIcons.totalRp,
      label: 'Most RP Gained',
      match: bestRpGame,
      playerName: playerName,
      onOpen: onOpenGame,
      allTime: _allTimeStanding(
        bestRpGame?.rpChange,
        allTime?.bestRpGame?.rpChange,
        (v) => '${formatSignedInt(v)} RP',
      ),
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
      icon: StatIcons.totalKills,
      label: 'Most Kills',
      match: bestKillsGame,
      playerName: playerName,
      onOpen: onOpenGame,
      allTime: _allTimeStanding(
        bestKillsGame?.kills,
        allTime?.bestKillsGame?.kills,
        (v) => '${formatNumber(v)} kills',
      ),
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
      icon: StatIcons.totalDamage,
      label: 'Most Damage',
      match: bestDamageGame,
      playerName: playerName,
      onOpen: onOpenGame,
      allTime: _allTimeStanding(
        bestDamageGame?.damage,
        allTime?.bestDamageGame?.damage,
        (v) => '${formatNumber(v)} damage',
      ),
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
/// in range reported this tracker). Tapping it opens the game.
class _RecordCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final RankedMatch? match;
  final String? value;
  final String? playerName;

  /// Opens the game the record was set in.
  final void Function(RankedMatch game) onOpen;

  /// How the record stands against the best over every split, when known.
  final ({String text, bool isBest})? allTime;

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
    required this.onOpen,
    this.allTime,
    this.playerName,
    this.shareDrops,
    this.shareValue,
    this.shareUnit,
    this.comparison,
  });

  @override
  Widget build(BuildContext context) {
    final m = match;
    final standing = allTime;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      onTap: m == null || value == null ? null : () => onOpen(m),
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
                if (standing != null && value != null) ...[
                  const SizedBox(height: AppTheme.xs),
                  _AllTimeNote(text: standing.text, isBest: standing.isBest),
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
                    (
                      StatIcons.totalRp,
                      'RP',
                      formatSignedInt(m.effectiveRpChange),
                    ),
                  if (shareDrops != 'Kills')
                    (
                      StatIcons.totalKills,
                      'Kills',
                      formatNumberOrNone(m.kills),
                    ),
                  if (shareDrops != 'Damage')
                    (
                      StatIcons.totalDamage,
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

/// A small line under a record: orange when it is the best ever, muted with the
/// all-time figure when it isn't.
class _AllTimeNote extends StatelessWidget {
  final String text;
  final bool isBest;
  const _AllTimeNote({required this.text, required this.isBest});

  @override
  Widget build(BuildContext context) {
    final color = isBest ? AppTheme.accent : AppTheme.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isBest ? Icons.workspace_premium : Icons.history,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: isBest ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// The share button at the right of a record card. Opens a preview of the card
/// built by [card], given the name to show (null when it is hidden or there is
/// none to offer). It reads Save where the platform can't share a file, since
/// the preview then saves the image instead.
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
    final share = canShareFiles;
    return Tooltip(
      message: '${share ? 'Share' : 'Save'} $title',
      child: TextButton.icon(
        icon: Icon(share ? Icons.ios_share : Icons.save_alt, size: 18),
        label: Text(share ? 'Share' : 'Save'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.accent,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ShareCardScreen(
              title: title,
              offerNameToggle: playerName != null,
              cardBuilder: (showName) => card(showName ? playerName : null),
            ),
          ),
        ),
      ),
    );
  }
}

/// The play session that gained the most RP: the figure in large type, and the
/// games, kills, damage and time behind it. Shows a placeholder with no session.
/// Tapping it opens the session.
class _SessionRecordCard extends StatelessWidget {
  final RankedSession? session;

  /// What decides the session's top legend, for its portrait and share card.
  final BestMetric metric;
  final String? playerName;
  final void Function(RankedSession session) onOpen;
  const _SessionRecordCard({
    required this.session,
    required this.metric,
    required this.onOpen,
    this.playerName,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    final value = s == null ? null : '${formatSignedInt(s.netRp)} RP';
    final kills = s == null || s.killsGames == 0 ? null : s.totalKills;
    final damage = s == null || s.damageGames == 0 ? null : s.totalDamage;
    final top = s?.bestLegendBy(metric);
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      onTap: s == null ? null : () => onOpen(s),
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
                legend: top,
                playerName: name,
                stats: [
                  (StatIcons.games, 'Games', '${s.games}'),
                  (StatIcons.totalKills, 'Kills', formatNumberOrNone(kills)),
                  (
                    StatIcons.totalDamage,
                    'Damage',
                    formatNumberOrNone(damage),
                  ),
                  (
                    StatIcons.time,
                    'Time played',
                    formatDuration(s.duration.inSeconds),
                  ),
                  if (top != null) (Icons.person_outline, 'Top legend', top),
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
/// streak, or confirms it's tied with the best. Tapping it lists the games.
class _StreakCard extends StatelessWidget {
  final int currentStreak;
  final int bestStreak;
  final DateTime? bestStreakStart;

  /// False for a past week or split: worded in the past tense.
  final bool live;
  final String? playerName;

  /// The games of the best streak, oldest first, for the shared card and the
  /// list a tap opens.
  final List<RankedMatch> streakMatches;

  /// Opens the streak's games.
  final void Function(List<RankedMatch> games) onOpen;

  const _StreakCard({
    required this.currentStreak,
    required this.bestStreak,
    required this.bestStreakStart,
    required this.live,
    required this.onOpen,
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
    final hasGames = bestStreak > 0 && streakMatches.isNotEmpty;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      onTap: hasGames ? () => onOpen(streakMatches) : null,
      child: Row(
        children: [
          const Icon(StatIcons.winStreak, size: 20, color: AppTheme.accent),
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
          if (hasGames)
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

/// "Fri, Oct 9": a day on a record.
String _dayLabel(DateTime day) => DateFormat('EEE, MMM d').format(day);

/// Kills, damage and time played over [games]. Kills and damage are null when no
/// game reported them.
({int? kills, int? damage, int secs}) _gameTotals(List<RankedMatch> games) {
  final killed = games.where((m) => m.kills != null);
  final damaged = games.where((m) => m.damage != null);
  return (
    kills: killed.isEmpty ? null : killed.fold<int>(0, (a, m) => a + m.kills!),
    damage: damaged.isEmpty
        ? null
        : damaged.fold<int>(0, (a, m) => a + m.damage!),
    secs: games.fold<int>(
      0,
      (a, m) => a + m.endTime.difference(m.startTime).inSeconds,
    ),
  );
}

/// The day that netted the most RP, as a record card.
Widget _dayCard(
  DayRecord day,
  BestMetric metric,
  String playerName,
  void Function(DayRecord day) onOpen,
) {
  final t = _gameTotals(day.matches);
  return _SummaryRecordCard(
    icon: Icons.calendar_today_outlined,
    label: 'Best Day',
    value: '${formatSignedInt(day.netRp)} RP',
    lines: [
      '${_dayLabel(day.day)} · ${plural(day.matches.length, 'game')}',
      '${formatNumberOrNone(t.kills)} kills · '
          '${formatNumberOrNone(t.damage)} dmg',
    ],
    playerName: playerName,
    onTap: () => onOpen(day),
    card: (name) => RecordShareCard(
      record: 'Best Day',
      value: formatSignedInt(day.netRp),
      unit: 'RP',
      valueColor: AppTheme.signColor(day.netRp >= 0),
      detail: DateFormat('EEEE, MMMM d').format(day.day),
      legend: topLegendBy(day.matches, metric),
      playerName: name,
      stats: [
        (StatIcons.games, 'Games', '${day.matches.length}'),
        (StatIcons.totalKills, 'Kills', formatNumberOrNone(t.kills)),
        (StatIcons.totalDamage, 'Damage', formatNumberOrNone(t.damage)),
        (StatIcons.time, 'Time played', formatDuration(t.secs)),
      ],
    ),
  );
}

/// The session that ran longest, as a record card.
Widget _longestSessionCard(
  RankedSession s,
  BestMetric metric,
  String playerName,
  void Function(RankedSession session) onOpen,
) {
  final kills = s.killsGames == 0 ? null : s.totalKills;
  final damage = s.damageGames == 0 ? null : s.totalDamage;
  final time = formatDuration(s.duration.inSeconds);
  return _SummaryRecordCard(
    icon: StatIcons.time,
    label: 'Longest Session',
    value: time,
    lines: [
      '${plural(s.games, 'game')} · ${formatSignedInt(s.netRp)} RP',
      formatSessionSpan(s.start, s.end),
    ],
    playerName: playerName,
    onTap: () => onOpen(s),
    card: (name) => RecordShareCard(
      record: 'Longest Session',
      value: time,
      comparison:
          '${formatSignedInt(s.netRp)} RP over ${plural(s.games, 'game')}',
      detail: formatSessionSpan(s.start, s.end),
      legend: s.bestLegendBy(metric),
      playerName: name,
      stats: [
        (StatIcons.games, 'Games', '${s.games}'),
        (StatIcons.totalKills, 'Kills', formatNumberOrNone(kills)),
        (StatIcons.totalDamage, 'Damage', formatNumberOrNone(damage)),
        (StatIcons.totalRp, 'RP', formatSignedInt(s.netRp)),
      ],
    ),
  );
}

/// The session with the biggest climb back from its low, as a record card.
Widget _comebackCard(
  Comeback c,
  BestMetric metric,
  String playerName,
  void Function(RankedSession session) onOpen,
) {
  final s = c.session;
  final kills = s.killsGames == 0 ? null : s.totalKills;
  final damage = s.damageGames == 0 ? null : s.totalDamage;
  return _SummaryRecordCard(
    icon: Icons.trending_up,
    label: 'Biggest Comeback',
    value: '${formatSignedInt(c.recovered)} RP',
    lines: [
      'Down ${c.low.abs()} RP, finished ${formatSignedInt(c.net)}',
      '${plural(s.games, 'game')} · ${formatSessionSpan(s.start, s.end)}',
    ],
    playerName: playerName,
    onTap: () => onOpen(s),
    card: (name) => RecordShareCard(
      record: 'Biggest Comeback',
      value: formatSignedInt(c.recovered),
      unit: 'RP',
      comparison: 'From ${formatSignedInt(c.low)} to ${formatSignedInt(c.net)}',
      detail: formatSessionSpan(s.start, s.end),
      legend: s.bestLegendBy(metric),
      playerName: name,
      stats: [
        (StatIcons.games, 'Games', '${s.games}'),
        (StatIcons.totalKills, 'Kills', formatNumberOrNone(kills)),
        (StatIcons.totalDamage, 'Damage', formatNumberOrNone(damage)),
        (StatIcons.time, 'Time played', formatDuration(s.duration.inSeconds)),
      ],
    ),
  );
}

/// The tiles of the card of all records: one for each record the period has.
List<(IconData icon, String label, String value)> _recordTiles({
  required PersonalRecords records,
  required RankedSession? bestSession,
  required DayRecord? day,
  required RankedSession? longest,
  required Comeback? comeback,
}) {
  final kills = records.bestKillsGame?.kills;
  final damage = records.bestDamageGame?.damage;
  return [
    if (records.bestRpGame != null)
      (
        StatIcons.totalRp,
        'Best game',
        '${formatSignedInt(records.bestRpGame!.effectiveRpChange)} RP',
      ),
    if (kills != null)
      (StatIcons.totalKills, 'Most kills', formatNumber(kills)),
    if (damage != null)
      (StatIcons.totalDamage, 'Most damage', formatNumber(damage)),
    if (bestSession != null)
      (
        Icons.timeline,
        'Best session',
        '${formatSignedInt(bestSession.netRp)} RP',
      ),
    if (day != null)
      (
        Icons.calendar_today_outlined,
        'Best day',
        '${formatSignedInt(day.netRp)} RP',
      ),
    if (longest != null)
      (
        StatIcons.time,
        'Longest session',
        formatDuration(longest.duration.inSeconds),
      ),
    if (comeback != null)
      (
        Icons.trending_up,
        'Comeback',
        '${formatSignedInt(comeback.recovered)} RP',
      ),
    if (records.bestWinStreak > 0)
      (
        StatIcons.winStreak,
        'Win streak',
        plural(records.bestWinStreak, 'game'),
      ),
  ];
}

/// A record card for a day or a session: the figure, a couple of lines about it,
/// and the Share button. Tapping it opens the games behind it.
class _SummaryRecordCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<String> lines;
  final String? playerName;
  final VoidCallback onTap;
  final Widget Function(String? name) card;
  const _SummaryRecordCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.lines,
    required this.onTap,
    required this.card,
    this.playerName,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      onTap: onTap,
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
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                for (final line in lines) Text(line, style: AppTheme.caption),
              ],
            ),
          ),
          _ShareButton(title: label, playerName: playerName, card: card),
        ],
      ),
    );
  }
}

/// The button at the top of the page that opens every record on one card.
class _ShareAllButton extends StatelessWidget {
  final String playerName;
  final String scope;
  final List<(IconData icon, String label, String value)> tiles;
  final String? legend;
  const _ShareAllButton({
    required this.playerName,
    required this.scope,
    required this.tiles,
    required this.legend,
  });

  @override
  Widget build(BuildContext context) {
    final share = canShareFiles;
    return OutlinedButton.icon(
      onPressed: tiles.isEmpty
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ShareCardScreen(
                  title: 'My records',
                  cardBuilder: (showName) => RecordsShareCard(
                    scope: scope,
                    tiles: tiles,
                    legend: legend,
                    playerName: showName ? playerName : null,
                  ),
                ),
              ),
            ),
      icon: Icon(share ? Icons.ios_share : Icons.save_alt, size: 18),
      label: Text(share ? 'Share all my records' : 'Save all my records'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.accent,
        side: const BorderSide(color: AppTheme.accent),
        minimumSize: const Size.fromHeight(44),
      ),
    );
  }
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
