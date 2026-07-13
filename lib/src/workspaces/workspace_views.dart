import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/artwork_image.dart';
import 'youtube_feed_workspace.dart';
import 'youtube_library_workspace.dart';

class WorkspaceView extends StatelessWidget {
  const WorkspaceView({
    required this.page,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    super.key,
  });

  final WorkspacePage page;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  Widget build(BuildContext context) {
    return switch (page) {
      WorkspacePage.home => YouTubeFeedWorkspace(
        kind: YouTubeFeedKind.home,
        playerController: playerController,
        shellController: shellController,
        youtubeLibraryController: youtubeLibraryController,
      ),
      WorkspacePage.explore => YouTubeFeedWorkspace(
        kind: YouTubeFeedKind.explore,
        playerController: playerController,
        shellController: shellController,
        youtubeLibraryController: youtubeLibraryController,
      ),
      WorkspacePage.library => LibraryWorkspace(
        playerController: playerController,
        shellController: shellController,
        youtubeLibraryController: youtubeLibraryController,
      ),
      WorkspacePage.settings => SettingsWorkspace(
        shellController: shellController,
      ),
    };
  }
}

class LibraryWorkspace extends StatelessWidget {
  const LibraryWorkspace({
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    super.key,
  });

  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  Widget build(BuildContext context) {
    return YouTubeLibraryWorkspace(
      controller: youtubeLibraryController,
      playerController: playerController,
      shellController: shellController,
    );
  }
}

class SettingsWorkspace extends StatelessWidget {
  const SettingsWorkspace({required this.shellController, super.key});

  final ShellController shellController;

  @override
  Widget build(BuildContext context) {
    return _WorkspaceScroller(
      children: <Widget>[
        const _PageHeading(title: 'Settings', eyebrow: 'DESKTOP'),
        const SizedBox(height: 40),
        const _SectionHeading('Motion'),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: shellController,
          builder: (context, _) {
            return Material(
              color: OtohaColors.surface,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppMetrics.radius),
              ),
              child: SwitchListTile.adaptive(
                key: const Key('reduce-motion-switch'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('Reduce motion'),
                value: shellController.reduceMotion,
                onChanged: shellController.setReduceMotion,
              ),
            );
          },
        ),
      ],
    );
  }
}

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({required this.tracks, required this.onSelect, super.key});

  final List<Track> tracks;
  final ValueChanged<Track> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 184,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.76,
      ),
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _AlbumCard(track: track, onSelect: () => onSelect(track));
      },
    );
  }
}

class TrackList extends StatelessWidget {
  const TrackList({
    required this.tracks,
    required this.playerController,
    this.compact = false,
    super.key,
  });

  final List<Track> tracks;
  final PlayerController playerController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playerController,
      builder: (context, _) {
        return Column(
          children: tracks
              .map(
                (track) => _TrackRow(
                  track: track,
                  compact: compact,
                  selected: track == playerController.currentTrack,
                  onSelect: () => playerController.selectTrack(track),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _WorkspaceScroller extends StatelessWidget {
  const _WorkspaceScroller({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppMetrics.workspacePadding,
        AppMetrics.workspacePadding,
        AppMetrics.workspacePadding,
        56,
      ),
      children: children,
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.title, required this.eyebrow});

  final String title;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          eyebrow,
          style: const TextStyle(
            color: OtohaColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.displaySmall),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.track, required this.onSelect});

  final Track track;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppMetrics.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppMetrics.radius),
                ),
                child: SizedBox.expand(
                  child: ArtworkImage(
                    assetPath: track.artworkAsset,
                    semanticLabel: '${track.album} artwork',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.compact,
    required this.selected,
    required this.onSelect,
  });

  final Track track;
  final bool compact;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final artworkSize = compact ? 40.0 : 48.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppMetrics.radius),
          ),
          child: Container(
            height: compact ? 56 : 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? OtohaColors.surfaceRaised : Colors.transparent,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppMetrics.radius),
              ),
            ),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppMetrics.radius),
                  ),
                  child: SizedBox(
                    width: artworkSize,
                    height: artworkSize,
                    child: ArtworkImage(
                      assetPath: track.artworkAsset,
                      semanticLabel: '${track.album} artwork',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? OtohaColors.accent
                              : OtohaColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${track.artist} - ${track.album}',
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
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatDuration(int seconds) => _formatDuration(seconds);

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final minutes = duration.inMinutes.toString();
  final remainingSeconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainingSeconds';
}
