import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../utils/theme.dart';

/// Total-RP gained/lost badge for map cards. A dark scrim + coloured text + a
/// direction arrow keep it legible over any (bright or dark) part of a map photo.
class MapRpBadge extends StatelessWidget {
  final int totalRp;
  final Color color;
  const MapRpBadge({super.key, required this.totalRp, required this.color});

  @override
  Widget build(BuildContext context) {
    final positive = totalRp >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: color.withAlpha(160)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(positive ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            '${formatNumber(totalRp.abs())} RP',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
