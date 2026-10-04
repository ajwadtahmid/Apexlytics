import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart';
import '../../../utils/theme.dart';
import '../../../widgets/map_asset_image.dart';

/// Home map card image: bundled art for known Battle Royale maps, else the rotation
/// API's [assetUrl] (e.g. Mixtape maps).
class MapHeroImage extends StatelessWidget {
  /// Display name from the rotation API.
  final String mapName;

  /// API image; used only when no bundled one exists.
  final String assetUrl;
  const MapHeroImage({
    super.key,
    required this.mapName,
    required this.assetUrl,
  });

  @override
  Widget build(BuildContext context) {
    // Card height is fixed by design; width just stretches to fill it, so
    // decoding to a physical-pixel height derived from the fixed dimension
    // is enough on any screen density — a wide landscape source fit into
    // this short card is height-constrained under BoxFit.cover regardless.
    // Only memCacheHeight is set: passing both dimensions would resize to
    // that exact box before BoxFit.cover runs, distorting a mismatched
    // source aspect ratio.
    final cacheHeight =
        (AppTheme.mapCardImageHeight * MediaQuery.devicePixelRatioOf(context))
            .ceil();
    final bundled = battleRoyaleMapInfoByName(mapName)?.asset;
    return SizedBox(
      height: AppTheme.mapCardImageHeight,
      width: double.infinity,
      child: bundled != null
          ? MapAssetImage(asset: bundled)
          : assetUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: assetUrl,
              fit: BoxFit.cover,
              memCacheHeight: cacheHeight,
              placeholder: (ctx, url) => const ColoredBox(
                color: AppTheme.surface2,
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.accent,
                    strokeWidth: 2,
                  ),
                ),
              ),
              errorWidget: (ctx, url, err) => const ColoredBox(
                color: AppTheme.surface2,
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: AppTheme.muted,
                    size: 48,
                  ),
                ),
              ),
            )
          : const ColoredBox(
              color: AppTheme.surface2,
              child: Center(
                child: Icon(
                  Icons.map_outlined,
                  color: AppTheme.muted,
                  size: 48,
                ),
              ),
            ),
    );
  }
}
