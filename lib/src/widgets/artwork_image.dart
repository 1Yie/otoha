import 'package:flutter/material.dart';

import '../app/theme.dart';

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
      return Image.network(
        assetPath,
        fit: BoxFit.cover,
        semanticLabel: semanticLabel,
        errorBuilder: errorBuilder,
      );
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      semanticLabel: semanticLabel,
      errorBuilder: errorBuilder,
    );
  }
}
