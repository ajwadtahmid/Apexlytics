import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

class MapHeroImage extends StatelessWidget {
  final String assetUrl;
  const MapHeroImage({super.key, required this.assetUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTheme.mapCardImageHeight,
      width: double.infinity,
      child: assetUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: assetUrl,
              fit: BoxFit.cover,
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
