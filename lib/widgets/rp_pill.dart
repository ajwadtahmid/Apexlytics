import 'package:flutter/material.dart';
import '../utils/formatting/format.dart' show formatNumber, formatSigned;
import '../utils/theme.dart';

/// RP gained/lost pill — a tinted (not solid) background so it reads as a
/// plain-card chip rather than the dark-scrim [MapRpBadge] meant to sit over
/// map artwork. Shows a total (`+1,234 RP`) or, via [RpPill.perGame], an
/// average per game (`+12.4 /game`).
///
/// [compact] is the smaller form for dense rows (a day header, a single
/// match): less padding and a 12 pt label.
class RpPill extends StatelessWidget {
  final int? totalRp;
  final double? avgRp;
  final bool compact;
  const RpPill({super.key, required int this.totalRp, this.compact = false})
    : avgRp = null;
  const RpPill.perGame({
    super.key,
    required double this.avgRp,
    this.compact = false,
  }) : totalRp = null;

  @override
  Widget build(BuildContext context) {
    final avg = avgRp;
    final positive = avg != null ? avg >= 0 : totalRp! >= 0;
    final text = avg != null
        ? '${formatSigned(avg)} /game'
        : '${positive ? '+' : ''}${formatNumber(totalRp!)} RP';
    final color = AppTheme.signColor(positive);
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
