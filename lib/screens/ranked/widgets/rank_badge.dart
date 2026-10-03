import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

/// Leaderboard rank chip shown beside a legend/map name. [onImage] uses a dark
/// scrim + white text so it stays legible over map artwork.
class RankBadge extends StatelessWidget {
  final int rank;
  final bool onImage;
  const RankBadge({super.key, required this.rank, this.onImage = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onImage ? Colors.black.withAlpha(140) : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        '#$rank',
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
