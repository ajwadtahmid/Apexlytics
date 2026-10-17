import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart' show mapNameKey;
import '../../../utils/formatting/format.dart' show formatSigned, plural;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// For each map the player has played: their record there and the legends that
/// do best and worst on it, so the matrix doubles as a pre-game decision. The
/// map in the live ranked rotation ([currentMapName]) comes first, marked
/// "Playing now".
class RankedBestLegendPerMap extends StatelessWidget {
  final List<LegendMapCell> cells;
  final String? currentMapName;
  const RankedBestLegendPerMap({
    super.key,
    required this.cells,
    this.currentMapName,
  });

  @override
  Widget build(BuildContext context) {
    final insights = mapLegendInsights(cells);
    if (insights.isEmpty) return const SizedBox.shrink();
    final nowKey = currentMapName == null ? null : mapNameKey(currentMapName!);
    final ordered = [
      ...insights.where((i) => mapNameKey(i.mapName) == nowKey),
      ...insights.where((i) => mapNameKey(i.mapName) != nowKey),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BEST AND WORST LEGEND PER MAP',
            style: AppTheme.cardTitle,
          ),
          const SizedBox(height: AppTheme.xs),
          const Text(
            'Needs $kMinGamesForInsight or more games on a map.',
            style: AppTheme.captionSmall,
          ),
          const SizedBox(height: AppTheme.sm),
          for (final i in ordered)
            _MapRow(insight: i, playingNow: mapNameKey(i.mapName) == nowKey),
        ],
      ),
    );
  }
}

class _MapRow extends StatelessWidget {
  final MapLegendInsight insight;
  final bool playingNow;
  const _MapRow({required this.insight, required this.playingNow});

  @override
  Widget build(BuildContext context) {
    final best = insight.best;
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: AppTheme.sm),
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  insight.mapName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (playingNow)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PLAYING NOW',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.xs),
          Text(
            insight.hasRecord
                ? 'Overall: ${_rate(insight.avgRpPerGame)} RP/game, '
                      '${plural(insight.games, 'game')}'
                : 'Only ${plural(insight.games, 'game')} here so far',
            style: AppTheme.caption,
          ),
          if (best != null) ...[
            const SizedBox(height: 2),
            _LegendLine('Best', best),
          ],
          if (insight.worst != null) ...[
            const SizedBox(height: 2),
            _LegendLine('Worst', insight.worst!),
          ] else if (best != null && insight.qualified == 1)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'No other legend has $kMinGamesForInsight+ games here yet',
                style: AppTheme.captionSmall,
              ),
            ),
        ],
      ),
    );
  }

  static String _rate(double v) => formatSigned(v);
}

/// "Best: Bangalore (+30.0 RP/game, 4 games)", in the colour of its RP.
class _LegendLine extends StatelessWidget {
  final String label;
  final LegendMapCell cell;
  const _LegendLine(this.label, this.cell);

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.signColor(cell.avgRpPerGame >= 0);
    return Text(
      '$label: ${cell.legend} (${formatSigned(cell.avgRpPerGame)} '
      'RP/game, ${plural(cell.games, 'game')})',
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}
