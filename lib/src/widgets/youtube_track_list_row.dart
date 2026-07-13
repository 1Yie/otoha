import 'package:flutter/material.dart';

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
    super.key,
  });

  final Key rowKey;
  final int index;
  final YouTubeTrack track;
  final VoidCallback onTap;
  final String? artworkFallback;
  final List<String> artistFallback;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0x2E9BFF73) : OtohaColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppMetrics.radius),
      child: InkWell(
        key: rowKey,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        onTap: onTap,
        child: Container(
          key: isSelected
              ? Key('youtube-track-selected-${track.videoId}')
              : null,
          height: 64,
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? OtohaColors.accent : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(AppMetrics.radius),
          ),
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
                    semanticLabel: '${track.title} artwork',
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
                      _artistText(track.artists, artistFallback),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                _formatDuration(track.durationSeconds),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
            ],
          ),
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

String _artistText(List<String> artists, List<String> fallback) {
  if (artists.isNotEmpty) {
    return artists.join(', ');
  }
  if (fallback.isNotEmpty) {
    return fallback.join(', ');
  }
  return 'YouTube Music';
}

String _formatDuration(int seconds) {
  if (seconds <= 0) {
    return '--:--';
  }
  final duration = Duration(seconds: seconds);
  return '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
