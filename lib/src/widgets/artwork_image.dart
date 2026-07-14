import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/artwork_cache.dart';

class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    required this.assetPath,
    required this.semanticLabel,
    super.key,
  });

  final String assetPath;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(BuildContext context, Object error, StackTrace? _) {
      return const ColoredBox(
        color: OtohaColors.surfaceRaised,
        child: Center(
          child: Icon(Icons.graphic_eq_rounded, color: OtohaColors.accent),
        ),
      );
    }

    if (assetPath.startsWith('http://') || assetPath.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: assetPath,
        cacheManager: OtohaArtworkCache.instance,
        imageBuilder: (context, imageProvider) => Image(
          image: imageProvider,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          semanticLabel: semanticLabel,
        ),
        placeholder: (context, url) =>
            const ColoredBox(color: OtohaColors.surfaceRaised),
        errorWidget: (context, url, error) =>
            errorBuilder(context, error, null),
      );
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      errorBuilder: errorBuilder,
    );
  }
}
