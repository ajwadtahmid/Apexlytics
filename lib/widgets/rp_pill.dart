import 'package:flutter/material.dart';
import '../utils/formatting/format.dart' show formatNumber;
import '../utils/theme.dart';

/// Total RP gained/lost pill — a tinted (not solid) background so it reads
/// as a plain-card chip rather than the dark-scrim [MapRpBadge] meant to sit
/// over map artwork.
class RpPill extends StatelessWidget {
  final int totalRp;
  const RpPill({super.key, required this.totalRp});

  @override
  Widget build(BuildContext context) {
    final positive = totalRp >= 0;
    final color = positive ? AppTheme.green : AppTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        '${positive ? '+' : ''}${formatNumber(totalRp)} RP',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }
}
