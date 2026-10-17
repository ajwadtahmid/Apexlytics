import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart'
    show formatPercent, formatSigned, formatSignedInt;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/ranked/split_changes.dart';
import '../../../utils/theme.dart';
import '../../../widgets/legend_icon.dart';
import '../../../widgets/surface_card.dart';

/// What moved most between two splits: the legends picked more or less, and the
/// maps where RP per game went up or down. Left out when nothing moved.
class SplitChangesCard extends StatelessWidget {
  final List<LegendBreakdown> legendsA;
  final List<LegendBreakdown> legendsB;
  final List<MapBreakdown> mapsA;
  final List<MapBreakdown> mapsB;

  const SplitChangesCard({
    super.key,
    required this.legendsA,
    required this.legendsB,
    required this.mapsA,
    required this.mapsB,
  });

  @override
  Widget build(BuildContext context) {
    final picks = pickRateShifts(legendsA, legendsB);
    final maps = mapRpShifts(mapsA, mapsB);
    if (picks.isEmpty && maps.isEmpty) return const SizedBox.shrink();

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('What changed', style: AppTheme.cardTitle),
          if (picks.isNotEmpty) ...[
            const SizedBox(height: AppTheme.md),
            const Text('Legends picked differently', style: AppTheme.caption),
            for (final s in picks)
              _ShiftRow(
                leading: LegendIcon(legendName: s.legend, size: 14),
                name: s.legend,
                delta: '${formatSignedInt(pointsMoved(s))} pts',
                deltaColor: AppTheme.textPrimary,
                range:
                    '${formatPercent(s.before, decimals: 0)} → '
                    '${formatPercent(s.after, decimals: 0)}',
              ),
          ],
          if (maps.isNotEmpty) ...[
            const SizedBox(height: AppTheme.md),
            const Text('RP per game by map', style: AppTheme.caption),
            const Text(
              'Maps with 3+ games in both splits',
              style: AppTheme.captionSmall,
            ),
            for (final s in maps)
              _ShiftRow(
                name: s.map,
                delta: formatSigned(s.after - s.before),
                deltaColor: AppTheme.signColor(s.after >= s.before),
                range: '${formatSigned(s.before)} → ${formatSigned(s.after)}',
              ),
          ],
        ],
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  final Widget? leading;
  final String name;
  final String delta;
  final Color deltaColor;
  final String range;

  const _ShiftRow({
    this.leading,
    required this.name,
    required this.delta,
    required this.deltaColor,
    required this.range,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
          const SizedBox(width: AppTheme.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                delta,
                style: TextStyle(
                  color: deltaColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(range, style: AppTheme.captionSmall),
            ],
          ),
        ],
      ),
    );
  }
}
