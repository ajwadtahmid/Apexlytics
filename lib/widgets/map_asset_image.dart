import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// A bundled map image covering its parent, decoded at its drawn width
/// (layout width × device pixel ratio).
class MapAssetImage extends StatelessWidget {
  final String asset;
  const MapAssetImage({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Image.asset(
        asset,
        fit: BoxFit.cover,
        cacheWidth: constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).ceil()
            : null,
        errorBuilder: (_, _, _) => Container(color: AppTheme.surface2),
      ),
    );
  }
}
