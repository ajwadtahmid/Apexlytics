import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Single win-rate chip: the win rate as the headline value with the raw win
/// (green) / loss (red) record trailing it, e.g. `34%  33–65`. Kept to the same
/// two lines (label + value) as the sibling [StatDisplay] chips so it never
/// stands taller in the grid — only wider. "Win" = a ranked game with positive
/// effective RP, "loss" = negative; RP-neutral games (pubs / neutralized split
/// resets) count as neither, so wins + losses can be fewer than games played.
///
/// The green/red record shows the split at a glance; when there are no decided
/// games the rate reads as an em dash rather than a misleading 0%. [onImage]
/// switches to the lighter styling the map cards use over their background art.
class WinLossStat extends StatelessWidget {
  final int wins;
  final int losses;
  final bool onImage;

  /// Drops the trailing `33W 65L` record, leaving just the rate.
  final bool showRecord;

  /// Shrinks to [StatDisplay]'s compact sizing, for a chip row with more than
  /// one line of chips.
  final bool compact;

  /// Centres the label and value instead of left-aligning them.
  final bool centered;

  const WinLossStat({
    super.key,
    required this.wins,
    required this.losses,
    this.onImage = false,
    this.showRecord = true,
    this.compact = false,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final decided = wins + losses;
    final rateText = decided == 0 ? '—' : '${(wins / decided * 100).round()}%';
    final valueSize = compact ? 12.0 : (onImage ? 14.0 : 15.0);

    final value = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: rateText,
            style: TextStyle(
              color: onImage ? Colors.white : AppTheme.textPrimary,
              fontSize: valueSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Record trails the rate at a smaller size so the line height stays
          // driven by the rate — same two-line height as the plain chips.
          if (showRecord) ...[
            const TextSpan(text: '  '),
            TextSpan(
              text: '${wins}W',
              style: const TextStyle(
                color: AppTheme.green,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: '${losses}L',
              style: const TextStyle(
                color: AppTheme.red,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          onImage ? 'WIN RATE' : 'Win Rate',
          style: TextStyle(
            color: onImage ? Colors.white60 : AppTheme.muted,
            fontSize: compact ? 9 : (onImage ? 9 : 10),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        value,
      ],
    );

    if (onImage) return content;

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: content,
    );
  }
}
