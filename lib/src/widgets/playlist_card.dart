import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import 'artwork_image.dart';

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    required this.title,
    required this.subtitle,
    required this.artworkPath,
    required this.onTap,
    this.cardKey,
    super.key,
  });

  final String title;
  final String subtitle;
  final String artworkPath;
  final VoidCallback onTap;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      key: cardKey,
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(AppMetrics.radius),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppMetrics.radius),
                  child: SizedBox.expand(
                    child: ArtworkImage(
                      assetPath: artworkPath,
                      semanticLabel: l10n.artwork(title),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppMetrics.radius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
