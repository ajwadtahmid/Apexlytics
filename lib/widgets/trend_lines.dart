import 'package:flutter/material.dart';
import 'trend_arrow.dart';
import '../utils/formatting/format.dart' show formatNumber, formatSigned;
import '../utils/ranked/ranked_aggregates.dart';
import '../utils/theme.dart';

/// Up to three colored delta lines (RP/kills/damage) reading as "down 5, was
/// 50". A metric whose magnitude rounds to zero shows a muted "unchanged"
/// instead. Dropped individually when [entityTrends] returned null; collapses
/// to nothing if all three are.
class TrendLines extends StatelessWidget {
  final EntityTrends trends;
  const TrendLines({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    final lines = [
      _line(
        'Avg RP',
        trends.rp,
        magnitudeFmt: (v) => v.toStringAsFixed(1),
        olderFmt: formatSigned,
        roundsToZero: (d) => d.abs() < 0.05,
      ),
      _line(
        'Avg Kills',
        trends.kills,
        magnitudeFmt: (v) => v.toStringAsFixed(1),
        olderFmt: (v) => v.toStringAsFixed(1),
        roundsToZero: (d) => d.abs() < 0.05,
      ),
      _line(
        'Avg Damage',
        trends.damage,
        magnitudeFmt: (v) => formatNumber(v.round()),
        olderFmt: (v) => formatNumber(v.round()),
        roundsToZero: (d) => d.abs() < 0.5,
      ),
    ].whereType<Widget>().toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(padding: const EdgeInsets.only(top: 2), child: line),
        ],
      ),
    );
  }

  Widget? _line(
    String label,
    TrendChange? trend, {
    required String Function(double) magnitudeFmt,
    required String Function(double) olderFmt,
    required bool Function(double) roundsToZero,
  }) {
    if (trend == null) return null;
    if (roundsToZero(trend.delta)) {
      return Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 11, color: AppTheme.muted),
          children: [
            trendArrow(Icons.trending_flat, AppTheme.muted),
            TextSpan(text: '$label unchanged'),
          ],
        ),
      );
    }
    final up = trend.delta > 0;
    final color = AppTheme.signColor(up);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 11, color: color),
        children: [
          trendArrow(trendIcon(trend.delta), color),
          TextSpan(
            text:
                '$label ${up ? 'up' : 'down'} ${magnitudeFmt(trend.delta.abs())}, '
                'was ${olderFmt(trend.older)}',
          ),
        ],
      ),
    );
  }
}

/// One-line methodology explainer for [TrendLines].
class TrendFootnote extends StatelessWidget {
  const TrendFootnote({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppTheme.sm),
      child: Text(
        'Trends show your average now vs. before your last '
        '$kTrendRecentGames games.',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: AppTheme.muted),
      ),
    );
  }
}
