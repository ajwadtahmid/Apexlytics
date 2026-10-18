import 'package:flutter/material.dart';
import '../constants/legend_constants.dart';
import '../models/player_stats.dart';
import '../utils/formatting/format.dart';
import '../utils/theme.dart';
import '../utils/formatting/tracker_utils.dart';
import '../utils/formatting/weapon_utils.dart';
import 'legend_asset_image.dart';
import 'legend_trackers_sheet.dart';
import 'role_badge.dart';

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
    showLegendTrackersSheet(context, legend);
  }
}

class _LegendCard extends StatelessWidget {
  final LegendStat legend;
  final VoidCallback? onTap;
  const _LegendCard({required this.legend, this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = legendInfo(legend.name);

    // Deduplicate trackers by display name, keeping the highest value.
    // Weapon trackers are excluded here; they appear in the Guns tab instead.
    final nonWeaponTrackers = legend.trackers
        .where((t) => findWeaponFromTracker(t.displayName) == null)
        .toList();
    final card = legendCardTrackers(
      deduplicateTrackers(nonWeaponTrackers),
      career: legend.name == kCareerLegendName,
    );

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
                          RoleBadge(role: info.role, compact: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    _TrackerGrid(card: card),
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

/// A legend's trackers as the same 2 by 2 grid on every card, so the cards all
/// stand the same height, with a chevron to its page for the rest. [card] says
/// what goes in each cell and how many trackers didn't fit.
class _TrackerGrid extends StatelessWidget {
  final LegendCardTrackers card;
  const _TrackerGrid({required this.card});

  @override
  Widget build(BuildContext context) {
    final cells = card.cells;
    Widget row(int first) => Row(
      children: [
        for (var c = 0; c < 2; c++) ...[
          if (c > 0) const SizedBox(width: AppTheme.xs),
          Expanded(
            child: cells[first + c] == null
                ? const SizedBox.shrink()
                : _TrackerChip(cell: cells[first + c]!),
          ),
        ],
      ],
    );

    // The cells are narrow beside the portrait, so a very large text size
    // would break names letter by letter.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              children: [
                row(0),
                const SizedBox(height: AppTheme.xs),
                row(2),
              ],
            ),
          ),
          const SizedBox(width: 2),
          _MoreHint(hidden: card.hidden),
        ],
      ),
    );
  }
}

/// The chevron at the right of a card, which opens the legend's page. With
/// trackers the card has no room for it says how many.
class _MoreHint extends StatelessWidget {
  final int hidden;
  const _MoreHint({required this.hidden});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chevron_right, size: 22, color: AppTheme.muted),
          if (hidden > 0)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '+$hidden',
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const double _kChipLabelSize = 9;
const double _kChipLabelLineHeight = 1.2;

/// One tracker: its name over its value. The name has room for two lines and
/// is cut after that, whether it uses them or not, so every chip is the same
/// height.
class _TrackerChip extends StatelessWidget {
  final TrackerCell cell;
  const _TrackerChip({required this.cell});

  @override
  Widget build(BuildContext context) {
    final value = cell.value;
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(_kChipLabelSize) *
        _kChipLabelLineHeight *
        2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: labelHeight,
            child: Text(
              cell.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: _kChipLabelSize,
                height: _kChipLabelLineHeight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatNumberOrNone(value),
              style: TextStyle(
                color: value == null ? AppTheme.muted : AppTheme.textPrimary,
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
