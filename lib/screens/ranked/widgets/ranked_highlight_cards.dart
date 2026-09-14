import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart' show formatNumber, formatSigned;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/legend_asset_image.dart';
import '../../../widgets/surface_card.dart';
import 'map_rp_badge.dart';
import 'ranked_legend_detail_sheet.dart';
import 'ranked_map_detail_sheet.dart';

/// Overview highlight reel: best & worst legends (one per line, tappable for a
/// detail sheet) and the worst & best maps (image banners, also tappable). Each
/// sheet's "View all history" button reuses [RankedEntityHistoryScreen] — the
/// same drill-down the Legends/Maps tabs push to. "Unknown" maps are excluded.
/// Takes precomputed breakdowns so it works off either the in-memory split
/// aggregates or the SQL lifetime aggregates; [legendMatchesFor]/
/// [mapMatchesFor] resolve one entity's matches lazily, same as those tabs.
class RankedOverviewHighlights extends StatelessWidget {
  final List<LegendBreakdown> legends;
  final List<MapBreakdown> maps;
  final Future<List<RankedMatch>> Function(String legend) legendMatchesFor;
  final Future<List<RankedMatch>> Function(String mapKey) mapMatchesFor;
  final Future<void> Function() onRefresh;

  const RankedOverviewHighlights({
    super.key,
    required this.legends,
    required this.maps,
    required this.legendMatchesFor,
    required this.mapMatchesFor,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final legendsRanked = _rankByAvgRp(
      legends,
      (l) => l.games,
      (l) => l.avgRpPerGame,
    );
    final mapsRanked = _rankByAvgRp(
      maps.where((m) => !isUnknownMapKey(m.mapKey)).toList(),
      (m) => m.games,
      (m) => m.avgRpPerGame,
    );

    // Split legends into top (best) and bottom (worst) without overlap.
    final n = legendsRanked.length;
    final worstCount = n >= 2 ? (n >= 4 ? 2 : 1) : 0;
    final bestCount = (n - worstCount).clamp(0, 2);
    final best = legendsRanked.take(bestCount).toList();
    final worst = legendsRanked.sublist(n - worstCount).reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (best.isNotEmpty) ...[
          const _SectionLabel('Best Legends'),
          _legendList(best),
        ],
        if (worst.isNotEmpty) ...[
          const SizedBox(height: AppTheme.md),
          const _SectionLabel('Worst Legends'),
          _legendList(worst),
        ],
        if (mapsRanked.isNotEmpty) ...[
          const SizedBox(height: AppTheme.md),
          const _SectionLabel('Maps'),
          _MapHighlight(
            label: 'Best Map',
            map: mapsRanked.first,
            matchesFor: mapMatchesFor,
            onRefresh: onRefresh,
          ),
          if (mapsRanked.length > 1) ...[
            const SizedBox(height: AppTheme.sm),
            _MapHighlight(
              label: 'Worst Map',
              map: mapsRanked.last,
              matchesFor: mapMatchesFor,
              onRefresh: onRefresh,
            ),
          ],
        ],
      ],
    );
  }

  Widget _legendList(List<LegendBreakdown> items) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTheme.sm),
          _CompactLegend(
            breakdown: items[i],
            matchesFor: legendMatchesFor,
            onRefresh: onRefresh,
          ),
        ],
      ],
    );
  }

  /// Ranks by average RP/game (desc), preferring items with enough games to be
  /// meaningful but falling back to all when too few qualify.
  static List<T> _rankByAvgRp<T>(
    List<T> all,
    int Function(T) games,
    double Function(T) avgRp,
  ) {
    final qualified = all
        .where((e) => games(e) >= kMinGamesForInsight)
        .toList();
    final pool = qualified.isNotEmpty ? qualified : List<T>.from(all);
    pool.sort((a, b) => avgRp(b).compareTo(avgRp(a)));
    return pool;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.sm, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _CompactLegend extends StatelessWidget {
  final LegendBreakdown breakdown;
  final Future<List<RankedMatch>> Function(String legend) matchesFor;
  final Future<void> Function() onRefresh;

  const _CompactLegend({
    required this.breakdown,
    required this.matchesFor,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final positive = breakdown.avgRpPerGame >= 0;
    final rpColor = positive ? AppTheme.green : AppTheme.red;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.sm + 2),
      onTap: () =>
          showLegendDetailSheet(context, breakdown, matchesFor, onRefresh),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: SizedBox(
              width: 44,
              height: 44,
              child: LegendAssetImage(
                imageKey: legendImageKey(breakdown.legend),
                displayName: breakdown.legend,
                fallbackFontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  breakdown.legend,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${formatSigned(breakdown.avgRpPerGame)} RP/game',
                  style: TextStyle(
                    color: rpColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${breakdown.games}g · ${breakdown.avgKills.toStringAsFixed(1)}K · ${formatNumber(breakdown.avgDamage.round())} dmg',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
        ],
      ),
    );
  }
}

class _MapHighlight extends StatelessWidget {
  final String label;
  final MapBreakdown map;
  final Future<List<RankedMatch>> Function(String mapKey) matchesFor;
  final Future<void> Function() onRefresh;

  const _MapHighlight({
    required this.label,
    required this.map,
    required this.matchesFor,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final positive = map.avgRpPerGame >= 0;
    final accent = positive ? AppTheme.green : AppTheme.red;
    final asset = battleRoyaleMapAsset(map.mapKey);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: Clip.antiAlias,
      onTap: () => showMapDetailSheet(context, map, matchesFor, onRefresh),
      child: SizedBox(
        height: 118,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              Image.asset(
                asset,
                fit: BoxFit.cover,
                cacheWidth: 800,
                errorBuilder: (_, _, _) => Container(color: AppTheme.surface2),
              )
            else
              Container(color: AppTheme.surface2),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppTheme.cardScrimStart, AppTheme.cardScrimEnd],
                ),
              ),
            ),
            const Positioned(
              bottom: AppTheme.sm,
              right: AppTheme.sm,
              child: Icon(Icons.chevron_right, size: 20, color: Colors.white70),
            ),
            // Total RP gained/lost, top-right (matches the Maps tab).
            Positioned(
              top: AppTheme.sm,
              right: AppTheme.sm,
              child: MapRpBadge(totalRp: map.totalRp, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    map.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        _MapStat(
                          label: 'Avg RP',
                          value: formatSigned(map.avgRpPerGame),
                          color: accent,
                        ),
                        _MapStat(
                          label: 'Kills',
                          value: map.avgKills.toStringAsFixed(1),
                        ),
                        _MapStat(
                          label: 'Dmg',
                          value: formatNumber(map.avgDamage.round()),
                        ),
                        _MapStat(label: 'Games', value: '${map.games}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MapStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
