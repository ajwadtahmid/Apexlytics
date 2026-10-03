import 'package:flutter/material.dart';
import '../utils/formatting/format.dart' show formatNumber;
import '../utils/theme.dart';

/// RP gained/lost pill — a tinted (not solid) background so it reads as a
/// plain-card chip rather than the dark-scrim [MapRpBadge] meant to sit over
/// map artwork. Shows a total (`+1,234 RP`) or, via [RpPill.perGame], an
/// average per game (`+12.4 /game`).
class RpPill extends StatelessWidget {
  final int? totalRp;
  final double? avgRp;
  const RpPill({super.key, required int this.totalRp}) : avgRp = null;
  const RpPill.perGame({super.key, required double this.avgRp})
    : totalRp = null;

  @override
  Widget build(BuildContext context) {
    final avg = avgRp;
    final positive = avg != null ? avg >= 0 : totalRp! >= 0;
    final text = avg != null
        ? '${positive ? '+' : ''}${avg.toStringAsFixed(1)} /game'
        : '${positive ? '+' : ''}${formatNumber(totalRp!)} RP';
    final color = positive ? AppTheme.green : AppTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }
}
