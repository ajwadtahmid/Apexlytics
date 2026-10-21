import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'trend_arrow.dart';
import '../utils/formatting/format.dart' show formatNumber, formatSigned;
import '../utils/ranked/entity_trend_window.dart' show EntityTrendWindow;
import '../utils/ranked/ranked_aggregates.dart';
import '../utils/theme.dart';

/// What one trend line says, and which way: 1 above the average, -1 below it,
/// 0 in line with it.
typedef TrendSentence = ({String text, int direction});

/// The sentence for [trend] under [label]: "Avg RP +57.0 lately, 31.6 above your
/// +25.4 average", or "Avg RP in line with your average" when it is.
///
/// The figures are shown to [decimals] places (signed when [signed], as RP is),
/// and the distance between them is worked out from the figures as shown, not
/// from the exact ones, so what is printed always adds up: 2.2 and 1.9 are 0.3
/// apart, not the 0.4 that 2.24 and 1.86 are.
TrendSentence trendSentence(
  String label,
  TrendChange trend, {
  required int decimals,
  bool signed = false,
}) {
  double shown(double v) => decimals == 0
      ? v.roundToDouble()
      : double.parse(v.toStringAsFixed(decimals));
  String figure(double v) => decimals == 0
      ? formatNumber(v.round())
      : (signed ? formatSigned(v) : v.toStringAsFixed(decimals));

  final recent = shown(trend.recent);
  final overall = shown(trend.overall);
  final delta = recent - overall;
  // Half of the last place shown: anything smaller is not a difference.
  final half = 0.5 / math.pow(10, decimals);
  if (trend.delta.abs() < half || delta.abs() < half) {
    return (text: '$label in line with your average', direction: 0);
  }
  final up = delta > 0;
  final distance = delta.abs();
  return (
    text:
        '$label ${figure(recent)} lately, '
        '${decimals == 0 ? formatNumber(distance.round()) : distance.toStringAsFixed(decimals)} '
        '${up ? 'above' : 'below'} your ${figure(overall)} average',
    direction: up ? 1 : -1,
  );
}

/// Up to three colored lines (RP/kills/damage) saying how recent games compare
/// with the average the sheet shows: "Avg RP +57.0 lately, 31.6 above your
/// +25.4 average" (see [trendSentence]). A metric in line with the average
/// shows a muted line saying so instead. Dropped individually when
/// [entityTrends] returned null; collapses to nothing if all three are.
class TrendLines extends StatelessWidget {
  final EntityTrends trends;
  const TrendLines({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    final lines = [
      _line('Avg RP', trends.rp, decimals: 1, signed: true),
      _line('Avg Kills', trends.kills, decimals: 1),
      _line('Avg Damage', trends.damage, decimals: 0),
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
    required int decimals,
    bool signed = false,
  }) {
    if (trend == null) return null;
    final line = trendSentence(
      label,
      trend,
      decimals: decimals,
      signed: signed,
    );
    if (line.direction == 0) {
      return Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 11, color: AppTheme.muted),
          children: [
            trendArrow(Icons.trending_flat, AppTheme.muted),
            TextSpan(text: line.text),
          ],
        ),
      );
    }
    final color = AppTheme.signColor(line.direction > 0);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 11, color: color),
        children: [
          trendArrow(trendIcon(line.direction.toDouble()), color),
          TextSpan(text: line.text),
        ],
      ),
    );
  }
}

/// A line saying how [TrendLines] were worked out: which games are recent, with
/// [window] the one that was used.
class TrendFootnote extends StatelessWidget {
  final EntityTrendWindow window;
  const TrendFootnote({super.key, required this.window});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Text(
        'Trends compare your last ${formatNumber(window.recent)} games with '
        'your average.',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppTheme.muted),
      ),
    );
  }
}
