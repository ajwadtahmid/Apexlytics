import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/rank_constants.dart' show kPredatorBadgeAsset;
import '../../models/ranked_match.dart';
import '../../providers/best_metric_provider.dart';
import '../../utils/formatting/format.dart'
    show
        formatDuration,
        formatNumber,
        formatSigned,
        formatSignedInt,
        formatTotalOrNone,
        kNoReading,
        plural;
import '../../utils/formatting/rank_utils.dart' show rankAssetPathFromImageUrl;
import '../../utils/ranked/recap_journey.dart';
import '../../utils/ranked/recap_tiles.dart';
import '../../utils/ranked/split_recap.dart';
import '../../utils/share_image.dart' show canShareFiles;
import '../../utils/theme.dart';
import '../../widgets/best_metric_picker.dart';
import '../../widgets/rank_badge.dart';
import '../../widgets/stat_display.dart';
import '../../widgets/surface_card.dart';
import 'ranked_recap_share_screen.dart';
import 'widgets/recap_journey_chart.dart';

/// A period of ranked play at a glance: where the player ended up, how the RP
/// got there, and the figures behind it. The card to share is a tap away.
/// [matches] are the period's games.
class RankedRecapScreen extends ConsumerWidget {
  final List<RankedMatch> matches;
  final String scope;
  final String playerName;

  /// Whether the player is Apex Predator at the end of this period. Only known
  /// for the live period.
  final bool isPredator;

  /// What the period is called under the RP it netted: "split", or "week" when
  /// a single week is on screen.
  final String periodPhrase;

  const RankedRecapScreen({
    super.key,
    required this.matches,
    required this.scope,
    required this.playerName,
    this.isPredator = false,
    this.periodPhrase = 'this split',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = splitRecap(matches, metric: ref.watch(bestMetricProvider));
    final journey = recapJourney(matches);
    final share = canShareFiles;

    return Scaffold(
      appBar: AppBar(title: const Text('Recap')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            _Header(
              recap: recap,
              scope: scope,
              isPredator: isPredator,
              periodPhrase: periodPhrase,
            ),
            if (journey != null) ...[
              const _Heading('Your climb'),
              RecapJourneyChart(journey: journey),
            ],
            _Heading(
              'The breakdown',
              // What "best" means, when the figures below name a best.
              trailing: recap.bestLegend == null && recap.bestMap == null
                  ? null
                  : const BestMetricPill(),
            ),
            StatGrid(rows: _rows(recap)),
            const SizedBox(height: AppTheme.lg),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RankedRecapShareScreen(
                    recap: recap,
                    scope: scope,
                    playerName: playerName,
                    isPredator: isPredator,
                    periodPhrase: periodPhrase,
                  ),
                ),
              ),
              icon: Icon(share ? Icons.ios_share : Icons.save_alt, size: 18),
              label: Text(share ? 'Share recap' : 'Save recap'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The figures of [recap] as rows of two, in the order of the card's tiles. One
/// with nothing behind it (no best legend) is left out.
List<List<Widget>> _rows(SplitRecap recap) {
  final available = availableRecapTiles(recap);
  final figures = [
    for (final tile in RecapTile.values)
      if (available.contains(tile)) _figure(tile, recap),
  ];
  return [
    for (var i = 0; i < figures.length; i += 2)
      [
        figures[i],
        // An odd one out keeps the width of the rest.
        if (i + 1 < figures.length) figures[i + 1] else const SizedBox.shrink(),
      ],
  ];
}

Widget _figure(RecapTile tile, SplitRecap r) {
  switch (tile) {
    case RecapTile.games:
      return StatDisplay(label: 'Games', value: '${r.games}');
    case RecapTile.peakRp:
      return StatDisplay(label: 'Peak RP', value: formatNumber(r.peakRp));
    case RecapTile.kills:
      return StatDisplay(
        label: 'Kills',
        value: formatTotalOrNone(r.totalKills, r.killsGames),
      );
    case RecapTile.damage:
      return StatDisplay(
        label: 'Damage',
        value: formatTotalOrNone(r.totalDamage, r.damageGames),
      );
    case RecapTile.bestSession:
      final s = r.bestSession!;
      return StatDisplay(
        label: 'Best session',
        value: '${formatSignedInt(s.netRp)} RP',
        valueColor: AppTheme.signColor(s.netRp >= 0),
      );
    case RecapTile.timePlayed:
      return StatDisplay(
        label: 'Time played',
        value: formatDuration(r.playSecs),
      );
    case RecapTile.bestLegend:
      return StatDisplay(
        label: 'Best legend',
        value: r.bestLegend!.legend,
        footnote: r.metric.formatValue(r.metric.valueOf(r.bestLegend!)!),
      );
    case RecapTile.bestMap:
      return StatDisplay(
        label: 'Best map',
        value: r.bestMap!.displayName,
        footnote: r.metric.formatValue(r.metric.valueOf(r.bestMap!)!),
      );
    case RecapTile.winRate:
      final rate = r.winRate;
      return StatDisplay(
        label: 'Win rate',
        value: rate == null ? kNoReading : '${(rate * 100).round()}%',
        footnote:
            '${plural(r.wins, 'win')} · ${plural(r.losses, 'loss', 'losses')}',
      );
    case RecapTile.rpPerGame:
      return StatDisplay(
        label: 'Avg RP',
        value: formatSigned(r.avgRpPerGame),
        valueColor: AppTheme.signColor(r.avgRpPerGame >= 0),
      );
  }
}

/// Where the player ended up: the rank badge, the RP they finished on and what
/// the period netted, as at the top of the card.
class _Header extends StatelessWidget {
  final SplitRecap recap;
  final String scope;
  final bool isPredator;
  final String periodPhrase;
  const _Header({
    required this.recap,
    required this.scope,
    required this.isPredator,
    required this.periodPhrase,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Row(
        children: [
          RankBadge(
            assetPath: isPredator
                ? kPredatorBadgeAsset
                : rankAssetPathFromImageUrl(recap.rankImg),
            size: 56,
          ),
          const SizedBox(width: AppTheme.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scope, style: AppTheme.captionSmall),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${formatNumber(recap.finalRp)} RP',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${formatSignedInt(recap.netRp)} RP $periodPhrase',
                  style: TextStyle(
                    color: AppTheme.signColor(recap.netRp >= 0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  /// Something at the right-hand end of the heading.
  final Widget? trailing;
  const _Heading(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.lg, bottom: AppTheme.sm),
      child: trailing == null
          ? title
          : Row(
              children: [
                Expanded(child: title),
                trailing!,
              ],
            ),
    );
  }
}
