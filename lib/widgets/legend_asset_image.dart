import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Renders a legend portrait from assets with a two-level fallback:
///   1. assets/legends/{imageKey}.webp
///   2. assets/legends/placeholder.webp
///   3. Coloured box showing the first letter of [displayName]
class LegendAssetImage extends StatelessWidget {
  final String imageKey;
  final String displayName;
  final BoxFit fit;
  final Alignment alignment;
  final double fallbackFontSize;

  const LegendAssetImage({
    super.key,
    required this.imageKey,
    required this.displayName,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.fallbackFontSize = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/legends/$imageKey.webp',
      fit: fit,
      alignment: alignment,
      errorBuilder: (ctx, err, trace) => Image.asset(
        'assets/legends/placeholder.webp',
        fit: fit,
        errorBuilder: (ctx, err, trace) => Container(
          color: AppTheme.surface2,
          child: Center(
            child: Text(
              displayName.isNotEmpty ? displayName[0] : '?',
              style: TextStyle(
                fontSize: fallbackFontSize,
                fontWeight: FontWeight.bold,
                color: AppTheme.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
