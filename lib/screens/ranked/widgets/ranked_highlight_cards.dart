import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatAvgDamage, formatAvgKills, formatSigned, formatSignedInt;
import '../../../utils/ranked/best_metric.dart';
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/legend_asset_image.dart';
import '../../../widgets/map_asset_image.dart';
import '../../../widgets/rp_pill.dart';
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

  /// The scope's full history, for sessions on the page a card opens. Null for
  /// Lifetime.
  final List<RankedMatch>? sessionPool;

  /// What makes a legend or map strongest.
  final BestMetric metric;

  const RankedOverviewHighlights({
    super.key,
    required this.legends,
    required this.maps,
    required this.legendMatchesFor,
    required this.mapMatchesFor,
    required this.onRefresh,
    this.sessionPool,
    this.metric = kDefaultBestMetric,
  });

  @override
  Widget build(BuildContext context) {
    final legendsRanked = rankByMetric(
      legends,
      metric,
      nameOf: (l) => l.legend,
      softGate: true,
    );
    final mapsRanked = rankByMetric(
      maps.where((m) => !isUnknownMapKey(m.mapKey)),
      metric,
      nameOf: (m) => m.displayName,
      softGate: true,
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
          const _SectionLabel('Strongest Legends'),
          _legendList(best),
        ],
        if (worst.isNotEmpty) ...[
          const SizedBox(height: AppTheme.md),
          const _SectionLabel('Weakest Legends'),
          _legendList(worst),
        ],
        if (mapsRanked.isNotEmpty) ...[
          const SizedBox(height: AppTheme.md),
          const _SectionLabel('Maps'),
          _MapHighlight(
            label: 'Strongest Map',
            map: mapsRanked.first,
            metric: metric,
            matchesFor: mapMatchesFor,
            onRefresh: onRefresh,
            sessionPool: sessionPool,
          ),
          if (mapsRanked.length > 1) ...[
            const SizedBox(height: AppTheme.sm),
            _MapHighlight(
              label: 'Weakest Map',
              map: mapsRanked.last,
              metric: metric,
              matchesFor: mapMatchesFor,
              onRefresh: onRefresh,
              sessionPool: sessionPool,
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
            metric: metric,
            matchesFor: legendMatchesFor,
            onRefresh: onRefresh,
            sessionPool: sessionPool,
          ),
        ],
      ],
    );
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
  final BestMetric metric;

  final Future<List<RankedMatch>> Function(String legend) matchesFor;
  final Future<void> Function() onRefresh;
  final List<RankedMatch>? sessionPool;

  const _CompactLegend({
    required this.breakdown,
    required this.metric,
    required this.matchesFor,
    required this.onRefresh,
    this.sessionPool,
  });

  // The portrait fills the card's full height, flush with its left edge, and
  // its width follows its own aspect ratio so it shows uncropped.
  static const _cardHeight = 80.0;

  // RpPill: 13pt text plus 4dp padding top and bottom.
  static const _pillHeight = 24.0;

  @override
  Widget build(BuildContext context) {
    final cardHeight = AppTheme.scaledWithText(context, _cardHeight);
    final pillHeight = AppTheme.scaledWithText(context, _pillHeight);
    // Capped so large text can't widen the portrait and squeeze the stats.
    final portraitWidth =
        math.min(cardHeight, _cardHeight) * kLegendPortraitAspectRatio;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: Clip.antiAlias,
      onTap: () => showLegendDetailSheet(
        context,
        breakdown,
        matchesFor,
        onRefresh,
        sessionPool: sessionPool,
      ),
      child: SizedBox(
        height: cardHeight,
        // The pill column is capped at a share of the card's width, so it sits
        // flush right at normal sizes and only shrinks when text is large.
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: portraitWidth,
                child: LegendAssetImage(
                  imageKey: legendImageKey(breakdown.legend),
                  displayName: breakdown.legend,
                  fallbackFontSize: 20,
                ),
              ),
              const SizedBox(width: AppTheme.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    AppTheme.sm,
                    AppTheme.sm + 2,
                    AppTheme.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // The name and the pill share the top line, so the stats
                      // below get the card's whole width to themselves.
                      ConstrainedBox(
                        constraints: BoxConstraints(minHeight: pillHeight),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                breakdown.legend,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppTheme.sm),
                            // The ranking metric, so the pill and the order
                            // agree. Capped so it can't squeeze the name.
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * 0.4,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _metricPill(metric, breakdown),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: _statsFor(
                                  metric,
                                  totalRp: breakdown.totalRp,
                                  avgRp: breakdown.avgRpPerGame,
                                  avgKills: breakdown.avgKills,
                                  avgDamage: breakdown.avgDamage,
                                  games: breakdown.games,
                                ),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppTheme.muted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapHighlight extends StatelessWidget {
  final String label;
  final MapBreakdown map;
  final BestMetric metric;
  final Future<List<RankedMatch>> Function(String mapKey) matchesFor;
  final Future<void> Function() onRefresh;
  final List<RankedMatch>? sessionPool;

  const _MapHighlight({
    required this.label,
    required this.map,
    required this.metric,
    required this.matchesFor,
    required this.onRefresh,
    this.sessionPool,
  });

  @override
  Widget build(BuildContext context) {
    final asset = battleRoyaleMapAsset(map.mapKey);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: Clip.antiAlias,
      onTap: () => showMapDetailSheet(
        context,
        map,
        matchesFor,
        onRefresh,
        sessionPool: sessionPool,
      ),
      child: SizedBox(
        height: AppTheme.scaledWithText(context, 118),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              MapAssetImage(asset: asset)
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
            // The ranking metric, top-right, as on the legend cards.
            Positioned(
              top: AppTheme.sm,
              right: AppTheme.sm,
              child: _metricBadge(metric, map),
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
                      children: _statsFor(
                        metric,
                        totalRp: map.totalRp,
                        avgRp: map.avgRpPerGame,
                        avgKills: map.avgKills,
                        avgDamage: map.avgDamage,
                        games: map.games,
                        onImage: true,
                      ),
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

/// The ranking measure as the chip at a legend card's top right. RP figures
/// are coloured as gains or losses; kills, damage and win rate, which can't be
/// either, take the app's accent.
Widget _metricPill(BestMetric metric, RankedTally tally) {
  final value = metric.valueOf(tally)!;
  return switch (metric) {
    BestMetric.rpPerGame => RpPill.perGame(avgRp: value),
    BestMetric.totalRp => RpPill(totalRp: tally.totalRp),
    _ => RpPill.custom(text: metric.formatValue(value), color: AppTheme.accent),
  };
}

/// [_metricPill] for a map card, over its photo.
Widget _metricBadge(BestMetric metric, RankedTally tally) {
  final value = metric.valueOf(tally)!;
  return switch (metric) {
    BestMetric.rpPerGame => MapRpBadge.perGame(
      avgRp: value,
      color: AppTheme.signColor(value >= 0),
    ),
    BestMetric.totalRp => MapRpBadge(
      totalRp: tally.totalRp,
      color: AppTheme.signColor(tally.totalRp >= 0),
    ),
    _ => MapRpBadge.custom(
      text: metric.formatValue(value),
      color: AppTheme.accent,
    ),
  };
}

/// A card's stat row. A figure the card already shows as its ranking pill
/// ([metric]) is left out, so nothing appears twice, and the average RP per
/// game, just the number, stands in beside Total RP so the row keeps its length.
List<Widget> _statsFor(
  BestMetric metric, {
  required int totalRp,
  required double avgRp,
  required double? avgKills,
  required double? avgDamage,
  required int games,
  bool onImage = false,
}) => [
  if (metric != BestMetric.totalRp)
    _HighlightStat(
      label: 'Total RP',
      value: formatSignedInt(totalRp),
      color: AppTheme.signColor(totalRp >= 0),
      onImage: onImage,
    ),
  if (const {
    BestMetric.totalRp,
    BestMetric.avgKills,
    BestMetric.avgDamage,
  }.contains(metric))
    _HighlightStat(
      label: 'Avg RP',
      value: formatSigned(avgRp),
      color: AppTheme.signColor(avgRp >= 0),
      onImage: onImage,
    ),
  if (metric != BestMetric.avgKills)
    _HighlightStat(
      label: 'Avg Kills',
      value: formatAvgKills(avgKills),
      onImage: onImage,
    ),
  if (metric != BestMetric.avgDamage)
    _HighlightStat(
      label: 'Avg Dmg',
      value: formatAvgDamage(avgDamage),
      onImage: onImage,
    ),
  _HighlightStat(label: 'Games', value: '$games', onImage: onImage),
];

/// Small label/value stat pair for the highlight cards' stat row.
class _HighlightStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool onImage; // white text over map art vs. themed text on a plain card

  const _HighlightStat({
    required this.label,
    required this.value,
    this.color,
    this.onImage = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = onImage ? Colors.white60 : AppTheme.muted;
    final valueColor = color ?? (onImage ? Colors.white : AppTheme.textPrimary);
    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: labelColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
