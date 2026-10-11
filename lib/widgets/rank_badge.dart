import 'package:flutter/material.dart';

/// A rank badge from a bundled asset, [size] logical px square.
///
/// The one rule for a missing badge: nothing is drawn. [assetPath] is null for
/// a tier with no bundled art (Rookie), and a file that fails to load ends up
/// the same way, so no screen invents its own stand-in (a letter, an icon, a
/// coloured dot). The empty space keeps its [size] so a row doesn't shift.
///
/// Source badges are several hundred px across, so the image is decoded at its
/// display size ([cacheWidth]) rather than at full resolution.
class RankBadge extends StatelessWidget {
  final String? assetPath;
  final double size;

  const RankBadge({super.key, required this.assetPath, required this.size});

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    if (path == null) return SizedBox.square(dimension: size);
    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
    );
  }
}
