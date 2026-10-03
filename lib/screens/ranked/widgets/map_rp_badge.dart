import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../utils/theme.dart';

/// RP gained/lost badge for map cards — the total (`1,234 RP`), or via
/// [MapRpBadge.perGame] the average per game (`12.4 /game`). A dark scrim +
/// coloured text + a direction arrow keep it legible over any (bright or
/// dark) part of a map photo.
class MapRpBadge extends StatelessWidget {
  final int? totalRp;
  final double? avgRp;
  final Color color;
  const MapRpBadge({super.key, required int this.totalRp, required this.color})
    : avgRp = null;
  const MapRpBadge.perGame({
    super.key,
    required double this.avgRp,
    required this.color,
  }) : totalRp = null;

  @override
  Widget build(BuildContext context) {
    final avg = avgRp;
    final positive = avg != null ? avg >= 0 : totalRp! >= 0;
    final text = avg != null
        ? '${avg.abs().toStringAsFixed(1)} /game'
        : '${formatNumber(totalRp!.abs())} RP';
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
          Icon(
            positive ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            text,
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
