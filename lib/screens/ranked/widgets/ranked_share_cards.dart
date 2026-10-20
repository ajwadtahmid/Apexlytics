import 'package:flutter/material.dart';
import '../../../constants/stat_icons.dart';
import '../../../constants/legend_constants.dart' show canonicalLegendName;
import '../../../constants/rank_constants.dart' show kPredatorBadgeAsset;
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show
        formatDuration,
        formatNumber,
        formatNumberOrNone,
        formatSessionSpan,
        formatSigned,
        formatSignedInt,
        formatTotalOrNone,
        kNoReading;
import '../../../utils/formatting/rank_utils.dart'
    show rankAssetPathFromImageUrl;
import '../../../utils/ranked/recap_tiles.dart';
import '../../../utils/ranked/split_recap.dart';
import '../../../utils/theme.dart';
import '../../../widgets/rank_badge.dart';
import '../../../widgets/share_card.dart';

Color _signed(num v) => AppTheme.signColor(v >= 0);

/// The taller card the recap needs for up to ten figures.
const double _kRecapHeight = 560;

/// A period of ranked play in numbers: [recap] for [scope] ("S30 Split 2"). The
/// player's name appears only when [playerName] is given; a UID never does.
class RecapShareCard extends StatelessWidget {
  final SplitRecap recap;
  final String scope;
  final String? playerName;

  /// Whether the player finished the period as Apex Predator. Match history
  /// only ever carries the Master badge for them, so this is told separately.
  final bool isPredator;

  /// The tiles to draw, in the order given; null for the default eight. A tile
  /// with nothing to show (no best legend, no best session) is skipped.
  final List<RecapTile>? tiles;

  /// Where the RP was netted, said after it: "this split", or "in Week 3" when a
  /// single week is on screen.
  final String periodPhrase;

  /// Whether the footer says what the best legend and map are best at, when the
  /// card shows either.
  final bool showNote;
  const RecapShareCard({
    super.key,
    required this.recap,
    required this.scope,
    this.playerName,
    this.isPredator = false,
    this.tiles,
    this.periodPhrase = 'this split',
    this.showNote = true,
  });

  /// One tile of the card, or null when it has nothing to show.
  ShareTile? _tile(RecapTile tile) {
    final r = recap;
    switch (tile) {
      case RecapTile.games:
        return ShareTile(
          icon: StatIcons.games,
          label: 'Games',
          value: '${r.games}',
        );
      case RecapTile.peakRp:
        return ShareTile(
          icon: Icons.trending_up,
          label: 'Peak RP',
          value: formatNumber(r.peakRp),
        );
      case RecapTile.kills:
        return ShareTile(
          icon: StatIcons.totalKills,
          label: 'Kills',
          value: formatTotalOrNone(r.totalKills, r.killsGames),
        );
      case RecapTile.damage:
        return ShareTile(
          icon: StatIcons.totalDamage,
          label: 'Damage',
          value: formatTotalOrNone(r.totalDamage, r.damageGames),
        );
      case RecapTile.bestSession:
        final s = r.bestSession;
        return s == null
            ? null
            : ShareTile(
                icon: Icons.timeline,
                label: 'Best session',
                value: '${formatSignedInt(s.netRp)} RP',
                color: _signed(s.netRp),
              );
      case RecapTile.timePlayed:
        return ShareTile(
          icon: StatIcons.time,
          label: 'Time played',
          value: formatDuration(r.playSecs),
        );
      case RecapTile.bestLegend:
        return r.bestLegend == null
            ? null
            : ShareTile(
                icon: Icons.person_outline,
                label: 'Best legend',
                value: r.bestLegend!.legend,
              );
      case RecapTile.bestMap:
        return r.bestMap == null
            ? null
            : ShareTile(
                icon: Icons.map_outlined,
                label: 'Best map',
                value: r.bestMap!.displayName,
              );
      case RecapTile.winRate:
        return ShareTile(
          icon: StatIcons.winRate,
          label: 'Win rate',
          value: r.winRate == null
              ? kNoReading
              : '${(r.winRate! * 100).round()}%',
        );
      case RecapTile.rpPerGame:
        return ShareTile(
          icon: StatIcons.avgRp,
          label: 'RP per game',
          value: formatSigned(r.avgRpPerGame),
          color: _signed(r.avgRpPerGame),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = recap;
    final shown = tiles ?? defaultRecapTiles.toList();
    final note = showNote ? recapBestNote(r, shown) : null;
    return ShareCardFrame(
      label: '$scope recap',
      name: playerName,
      legend: r.bestLegend?.legend,
      height: _kRecapHeight,
      // One line whatever the font, so the footer keeps its height.
      footer: note == null
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(note, style: AppTheme.captionSmall),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RankBadge(
                assetPath: isPredator
                    ? kPredatorBadgeAsset
                    : rankAssetPathFromImageUrl(r.rankImg),
                size: 56,
              ),
              const SizedBox(width: AppTheme.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${formatNumber(r.finalRp)} RP',
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // One line whatever the font, so the card keeps its height.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${formatSignedInt(r.netRp)} RP $periodPhrase',
                        style: TextStyle(
                          color: _signed(r.netRp),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // The tiles start at the same place whatever their number; any room
          // left over is at the bottom.
          const SizedBox(height: AppTheme.lg),
          Wrap(
            spacing: AppTheme.sm,
            runSpacing: AppTheme.sm,
            children: [for (final t in shown) ?_tile(t)],
          ),
        ],
      ),
    );
  }
}

/// What [recap]'s best legend and map are best at, said for the card's footer
/// once [shown] tiles include either: "Best legend and map by total RP". Null
/// when neither is on the card.
String? recapBestNote(SplitRecap recap, List<RecapTile> shown) {
  final legend =
      shown.contains(RecapTile.bestLegend) && recap.bestLegend != null;
  final map = shown.contains(RecapTile.bestMap) && recap.bestMap != null;
  if (!legend && !map) return null;
  final what = legend && map ? 'legend and map' : (legend ? 'legend' : 'map');
  return 'Best $what by ${recap.metric.phrase}';
}

/// All of a period's records on one card, as the same two-column tiles the recap
/// uses: [tiles] are an icon, a label and a figure each, for [scope] ("S30
/// Split 2"). [legend] fades its portrait in behind. The player's name appears
/// only when [playerName] is given; a UID never does.
class RecordsShareCard extends StatelessWidget {
  final String scope;
  final List<(IconData icon, String label, String value)> tiles;
  final String? legend;
  final String? playerName;
  const RecordsShareCard({
    super.key,
    required this.scope,
    required this.tiles,
    this.legend,
    this.playerName,
  });

  @override
  Widget build(BuildContext context) {
    return ShareCardFrame(
      label: '$scope records',
      name: playerName,
      legend: legend,
      child: Column(
        children: [
          const Spacer(),
          Wrap(
            spacing: AppTheme.sm,
            runSpacing: AppTheme.sm,
            children: [
              for (final (icon, label, value) in tiles)
                ShareTile(icon: icon, label: label, value: value),
            ],
          ),
        ],
      ),
    );
  }
}

/// One personal record as a card: its name, the figure in large orange type
/// with its unit, a chip putting it in context, and the numbers around it. A
/// UID never appears; the name only when given. [legend] fades its portrait in
/// behind the card.
class RecordShareCard extends StatelessWidget {
  final String record;
  final String value;

  /// What the figure counts: "RP", "kills", "damage", "games".
  final String? unit;
  final Color? valueColor;
  final String? detail;

  /// A short chip under the figure putting it in context, such as how it
  /// compares with the player's average.
  final String? comparison;
  final List<(IconData icon, String label, String value)> stats;
  final String? legend;
  final String? playerName;

  /// Anything to draw between the figure and the tiles, such as the streak's
  /// row of wins.
  final Widget? visual;

  /// Taller than the standard card, for one with more on it.
  final double height;
  const RecordShareCard({
    super.key,
    required this.record,
    required this.value,
    this.unit,
    this.valueColor,
    this.detail,
    this.comparison,
    this.stats = const [],
    this.legend,
    this.playerName,
    this.visual,
    this.height = kShareCardHeight,
  });

  @override
  Widget build(BuildContext context) {
    final color = valueColor ?? AppTheme.accent;
    return ShareCardFrame(
      label: record,
      name: playerName,
      legend: legend,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppTheme.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 54,
                    height: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: AppTheme.sm),
                  Text(
                    unit!,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (comparison != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.sm + 2,
                  vertical: AppTheme.xs,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  comparison!,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.sm),
              child: Text(detail!, style: AppTheme.captionLarge),
            ),
          if (visual != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.md),
              child: visual,
            ),
          const Spacer(),
          if (stats.isNotEmpty)
            Wrap(
              spacing: AppTheme.sm,
              runSpacing: AppTheme.sm,
              children: [
                for (final (icon, label, v) in stats)
                  ShareTile(icon: icon, label: label, value: v),
              ],
            ),
        ],
      ),
    );
  }
}

/// Games shown as dots on a streak card, before the rest are summed up.
const int _kMaxStreakDots = 30;

/// The streak card's height: a little over 4:5, for its row of dots.
const double _kStreakHeight = 500;

/// The best win streak: its length in large type, a dot for every win, the RP
/// it earned, and what happened across it. [matches] are its games, oldest
/// first. The legend won with most fades in behind the card.
class StreakShareCard extends StatelessWidget {
  final List<RankedMatch> matches;
  final String? playerName;
  const StreakShareCard({super.key, required this.matches, this.playerName});

  @override
  Widget build(BuildContext context) {
    final games = matches.length;
    final totalRp = matches.fold<int>(0, (a, m) => a + m.effectiveRpChange);
    final reported = matches.where((m) => m.kills != null);
    final damaged = matches.where((m) => m.damage != null);
    final kills = reported.isEmpty
        ? null
        : reported.fold<int>(0, (a, m) => a + m.kills!);
    final damage = damaged.isEmpty
        ? null
        : damaged.fold<int>(0, (a, m) => a + m.damage!);
    final first = matches.first.startTime;
    final last = matches.last.endTime;

    // The legend that earned the most RP across the streak. Games played is a
    // poor measure: a streak is often one win on each of several legends.
    final rpByLegend = <String, int>{};
    final gamesByLegend = <String, int>{};
    for (final m in matches) {
      final name = canonicalLegendName(m.legend);
      rpByLegend[name] = (rpByLegend[name] ?? 0) + m.effectiveRpChange;
      gamesByLegend[name] = (gamesByLegend[name] ?? 0) + 1;
    }
    final top =
        (rpByLegend.keys.toList()..sort((a, b) {
              final byRp = rpByLegend[b]!.compareTo(rpByLegend[a]!);
              if (byRp != 0) return byRp;
              final byGames = gamesByLegend[b]!.compareTo(gamesByLegend[a]!);
              return byGames != 0 ? byGames : a.compareTo(b);
            }))
            .first;

    return RecordShareCard(
      record: 'Best Win Streak',
      value: '$games',
      unit: games == 1 ? 'game' : 'games',
      comparison: '${formatSignedInt(totalRp)} RP across the streak',
      detail: formatSessionSpan(first, last),
      legend: top,
      playerName: playerName,
      visual: _WinDots(count: games),
      height: _kStreakHeight,
      stats: [
        (StatIcons.totalKills, 'Kills', formatNumberOrNone(kills)),
        (StatIcons.totalDamage, 'Damage', formatNumberOrNone(damage)),
        (
          Icons.schedule,
          'First to last win',
          formatDuration(last.difference(first).inSeconds),
        ),
        (
          Icons.person_outline,
          'Top legend',
          rpByLegend.length == 1 ? 'Only $top' : top,
        ),
      ],
    );
  }
}

/// One dot per win, wrapping across the card; past [_kMaxStreakDots] the rest
/// are summed up as "+N".
class _WinDots extends StatelessWidget {
  final int count;
  const _WinDots({required this.count});

  @override
  Widget build(BuildContext context) {
    final shown = count < _kMaxStreakDots ? count : _kMaxStreakDots;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < shown; i++)
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppTheme.accent.withAlpha(70), blurRadius: 4),
              ],
            ),
          ),
        if (count > shown)
          Text('+${count - shown}', style: AppTheme.captionLarge),
      ],
    );
  }
}
