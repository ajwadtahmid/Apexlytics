import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Maps a legend display name to its portrait asset key under `assets/legends/`
/// — lowercased with spaces as underscores. The synthetic "Global" career
/// aggregate has no legend portrait, so it maps to the `career` image.
String legendImageKey(String name) {
  final lower = name.toLowerCase();
  return lower == 'global' ? 'career' : lower.replaceAll(' ', '_');
}

/// Renders a legend portrait from assets with a two-level fallback:
///   1. assets/legends/{imageKey}.webp
///   2. assets/legends/placeholder.webp
///   3. Coloured box showing the first letter of [displayName]
///
/// Source portraits are 1680×1878px, but call sites render this at 36-150
/// logical px — decoding full-res every time wastes ~12MB per unique legend.
/// [build] reads its incoming width via [LayoutBuilder] and passes only
/// `width * devicePixelRatio` as `cacheWidth`, letting height derive
/// automatically. Passing both dimensions would resize to that exact box
/// before [fit] runs, pre-distorting a portrait source under [BoxFit.cover]
/// in a squarer target.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        // Unbounded width (no ancestor constraint) — decode full-res rather
        // than pass an infinite size to ResizeImage.
        final cacheWidth = width.isFinite
            ? (width * devicePixelRatio).ceil()
            : null;

        return Image.asset(
          'assets/legends/$imageKey.webp',
          fit: fit,
          alignment: alignment,
          cacheWidth: cacheWidth,
          errorBuilder: (ctx, err, trace) => Image.asset(
            'assets/legends/placeholder.webp',
            fit: fit,
            cacheWidth: cacheWidth,
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
      },
    );
  }
}
