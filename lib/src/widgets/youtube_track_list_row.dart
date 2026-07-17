import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../models/youtube_library.dart';
import 'artwork_image.dart';

class YouTubeTrackListRow extends StatelessWidget {
  const YouTubeTrackListRow({
    required this.rowKey,
    required this.index,
    required this.track,
    required this.onTap,
    this.artworkFallback,
    this.artistFallback = const <String>[],
    this.isSelected = false,
    this.trailing,
    super.key,
  });

  final Key rowKey;
  final int index;
  final YouTubeTrack track;
  final VoidCallback onTap;
  final String? artworkFallback;
  final List<String> artistFallback;
  final bool isSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('youtube-track-action-${track.videoId}'),
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Stack(
          key: rowKey,
          children: <Widget>[
            SizedBox(
              height: 64,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 40,
                          child: Text(
                            '$index',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        SizedBox.square(
                          dimension: 44,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: ArtworkImage(
                              assetPath: _artworkPath(
                                track.thumbnailUrl,
                                artworkFallback,
                              ),
                              semanticLabel: l10n.artwork(track.title),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _artistText(
                                  track.artists,
                                  artistFallback,
                                  l10n,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatDuration(track.durationSeconds, l10n),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing case final trailing?) ...<Widget>[
                    const SizedBox(width: 12),
                    trailing,
                    const SizedBox(width: 8),
                  ] else
                    const SizedBox(width: 16),
                ],
              ),
            ),
            if (isSelected)
              Positioned.fill(
                key: Key('youtube-track-selected-${track.videoId}'),
                child: IgnorePointer(
                  child: ColoredBox(
                    color: OtohaColors.accent.withValues(alpha: 0.10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _artworkPath(String? trackArtwork, String? fallbackArtwork) {
  if (trackArtwork != null && trackArtwork.isNotEmpty) {
    return trackArtwork;
  }
  return fallbackArtwork ?? '';
}

String _artistText(
  List<String> artists,
  List<String> fallback,
  AppLocalizations l10n,
) {
  if (artists.isNotEmpty) {
    return artists.join(', ');
  }
  if (fallback.isNotEmpty) {
    return fallback.join(', ');
  }
  return l10n.youtubeMusic;
}

String _formatDuration(int seconds, AppLocalizations l10n) {
  if (seconds <= 0) {
    return l10n.unknownDuration;
  }
  final duration = Duration(seconds: seconds);
  return '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
