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
    this.isLoading = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final String artworkPath;
  final VoidCallback onTap;
  final Key? cardKey;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          key: cardKey,
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(AppMetrics.radius),
          child: Stack(
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 1,
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
                  const SizedBox(height: AppMetrics.unit),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              if (isLoading)
                const Positioned.fill(
                  key: Key('playlist-card-loading-overlay'),
                  child: ColoredBox(
                    color: Color(0x99000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
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
        ),
      ),
    );
  }
}
