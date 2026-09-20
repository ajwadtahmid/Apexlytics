import 'package:flutter/material.dart';
import '../constants/legend_constants.dart';
import '../models/player_stats.dart';
import '../utils/formatting/format.dart';
import '../utils/navigation_utils.dart';
import '../utils/theme.dart';
import 'stat_display.dart';
import '../utils/formatting/tracker_utils.dart';
import '../utils/formatting/weapon_utils.dart';
import 'legend_asset_image.dart';
import 'legend_detail_page.dart';

class LegendStatsSection extends StatelessWidget {
  final List<LegendStat> legends;
  const LegendStatsSection({super.key, required this.legends});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: legends
          .where((legend) {
            // Skip Career/Global tracker if it only has weapon trackers
            if (legend.name.toLowerCase() == 'global') {
              final nonWeaponTrackers = legend.trackers
                  .where((t) => findWeaponFromTracker(t.displayName) == null)
                  .toList();
              return nonWeaponTrackers.isNotEmpty;
            }
            return true;
          })
          .map(
            (legend) => Padding(
              key: ValueKey(legend.name),
              padding: const EdgeInsets.only(bottom: AppTheme.sm),
              child: _LegendCard(
                legend: legend,
                onTap: () => _openDetail(context, legend),
              ),
            ),
          )
          .toList(),
    );
  }

  void _openDetail(BuildContext context, LegendStat legend) {
    context.pushPage(LegendDetailPage(legend: legend));
  }
}

class _LegendCard extends StatelessWidget {
  final LegendStat legend;
  final VoidCallback? onTap;
  const _LegendCard({required this.legend, this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = kLegendsByName[legend.name.toLowerCase()];

    // Deduplicate trackers by display name, keeping the highest value.
    // Weapon trackers are excluded here; they appear in the Guns tab instead.
    final nonWeaponTrackers = legend.trackers
        .where((t) => findWeaponFromTracker(t.displayName) == null)
        .toList();
    final trackers = deduplicateTrackers(nonWeaponTrackers);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Image fills the full card height without IntrinsicHeight.
            // Stack sizes to the non-positioned child (the content padding),
            // and Positioned(top/bottom:0) stretches the image to match.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 100,
              child: LegendAssetImage(
                imageKey: legendImageKey(legend.name),
                displayName: legendDisplayName(legend.name),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 100),
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            legendDisplayName(legend.name),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (info != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: info.role.color.withAlpha(35),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusSm,
                              ),
                            ),
                            child: Text(
                              info.role.displayName,
                              style: TextStyle(
                                color: info.role.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: trackers
                            .map(
                              (t) => Container(
                                margin: const EdgeInsets.only(right: 8),
                                child: StatDisplay(
                                  label: t.displayName,
                                  value: formatNumber(t.value),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
