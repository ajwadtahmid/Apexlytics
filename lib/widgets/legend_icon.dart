import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Maps a legend display name to its small face-icon asset under
/// `assets/legend_icons/` (`"Mad Maggie"` → `Mad_Maggie_Icon.webp`).
/// Unlike [legendImageKey]/`assets/legends/`, this set has no entry for the
/// synthetic "Global" career aggregate or an unrecognised/legacy name —
/// [LegendIcon]'s `errorBuilder` handles that gap by rendering nothing.
String legendIconAsset(String name) =>
    'assets/legend_icons/${name.replaceAll(' ', '_')}_Icon.webp';

/// Small per-legend face icon, used where a full [LegendAssetImage] portrait
/// would be too heavy (dense lists, dropdowns) but a bare name is hard to
/// scan. Renders nothing (not a placeholder box) when [legendName] has no
/// matching asset, so an "Unknown"/legacy value degrades to plain text
/// rather than showing a broken-image glyph.
class LegendIcon extends StatelessWidget {
  final String legendName;
  final double size;

  const LegendIcon({super.key, required this.legendName, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      legendIconAsset(legendName),
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Source is a black silhouette on transparent — invisible as-is
      // against this app's dark background, so tint it to the theme's
      // light text color instead of the source's raw black fill.
      color: AppTheme.textPrimary,
      colorBlendMode: BlendMode.srcIn,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      errorBuilder: (ctx, err, trace) => SizedBox(width: size, height: size),
    );
  }
}
