import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/artwork_image.dart';
import '../widgets/youtube_track_list_row.dart';

class YouTubeLibraryWorkspace extends StatelessWidget {
  const YouTubeLibraryWorkspace({
    required this.controller,
    required this.playerController,
    required this.shellController,
    super.key,
  });

  final YouTubeLibraryController controller;
  final PlayerController playerController;
  final ShellController shellController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.status == YouTubeAccountStatus.restoring) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.isSignedIn) {
          return _SignedOutLibrary(shellController: shellController);
        }
        if (controller.selectedPlaylist case final detail?) {
          return _PlaylistDetailView(
            detail: detail,
            isLoading: controller.isLoadingPlaylist,
            onBack: controller.closePlaylist,
            playerController: playerController,
          );
        }
        return _PlaylistGrid(
          playlists: controller.playlists,
          isLoading: controller.isLoadingLibrary,
          errorMessage: controller.errorMessage,
          onRefresh: controller.loadPlaylists,
          onOpen: controller.openPlaylist,
        );
      },
    );
  }
}

class _SignedOutLibrary extends StatelessWidget {
  const _SignedOutLibrary({required this.shellController});

  final ShellController shellController;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('youtube-library-signed-out'),
      child: FilledButton.icon(
        key: const Key('youtube-library-sign-in'),
        onPressed: () => shellController.togglePanel(SidePanel.account),
        icon: const Icon(Icons.login_rounded),
        label: const Text('Sign in to YouTube Music'),
      ),
    );
  }
}

class _PlaylistGrid extends StatelessWidget {
  const _PlaylistGrid({
    required this.playlists,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<YouTubePlaylist> playlists;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefresh;
  final ValueChanged<YouTubePlaylist> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppMetrics.workspacePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Your playlists',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
              Tooltip(
                message: 'Sync library',
                child: IconButton(
                  key: const Key('youtube-library-refresh'),
                  onPressed: isLoading ? null : onRefresh,
                  icon: const Icon(Icons.sync_rounded),
                ),
              ),
            ],
          ),
          if (isLoading) const LinearProgressIndicator(),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          Expanded(
            child: playlists.isEmpty && !isLoading
                ? const Center(child: Text('No playlists found'))
                : GridView.builder(
                    key: const Key('youtube-playlist-grid'),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 244,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                        ),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return _PlaylistCard(
                        playlist: playlist,
                        onTap: () => onOpen(playlist),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.onTap});

  final YouTubePlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('youtube-playlist-${playlist.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppMetrics.radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppMetrics.radius),
              child: SizedBox.expand(
                child: ArtworkImage(
                  assetPath: playlist.thumbnailUrl ?? '',
                  semanticLabel: '${playlist.title} artwork',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            playlist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            [
              playlist.owner,
              playlist.itemCount,
            ].whereType<String>().join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PlaylistDetailView extends StatelessWidget {
  const _PlaylistDetailView({
    required this.detail,
    required this.isLoading,
    required this.onBack,
    required this.playerController,
  });

  final YouTubePlaylistDetail detail;
  final bool isLoading;
  final VoidCallback onBack;
  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final playbackTracks = detail.tracks
        .map(
          (track) => _asSimulatedTrack(
            track,
            artworkFallback: detail.playlist.thumbnailUrl,
            albumFallback: detail.playlist.title,
          ),
        )
        .toList(growable: false);
    return Padding(
      key: const Key('youtube-playlist-detail'),
      padding: const EdgeInsets.all(AppMetrics.workspacePadding),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IconButton(
                key: const Key('youtube-playlist-back'),
                onPressed: onBack,
                tooltip: 'Back to playlists',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppMetrics.radius),
                child: SizedBox.square(
                  dimension: 144,
                  child: ArtworkImage(
                    assetPath: detail.playlist.thumbnailUrl ?? '',
                    semanticLabel: '${detail.playlist.title} artwork',
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'PLAYLIST',
                      style: TextStyle(
                        color: OtohaColors.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail.playlist.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        detail.playlist.owner,
                        detail.playlist.itemCount,
                      ].whereType<String>().join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.separated(
              itemCount: detail.tracks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final track = detail.tracks[index];
                return AnimatedBuilder(
                  animation: playerController,
                  builder: (context, _) => YouTubeTrackListRow(
                    rowKey: Key('youtube-track-${track.videoId}'),
                    index: index + 1,
                    track: track,
                    artworkFallback: detail.playlist.thumbnailUrl,
                    isSelected:
                        playerController.currentTrack.id ==
                        playbackTracks[index].id,
                    onTap: () {
                      playerController.playTracks(playbackTracks);
                      playerController.selectTrack(playbackTracks[index]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Track _asSimulatedTrack(
  YouTubeTrack track, {
  String? artworkFallback,
  String? albumFallback,
}) {
  return Track(
    id: track.videoId,
    title: track.title,
    artist: track.artists.isEmpty ? 'YouTube Music' : track.artists.join(', '),
    album: track.album ?? albumFallback ?? 'YouTube Music',
    artworkAsset: track.thumbnailUrl?.isNotEmpty == true
        ? track.thumbnailUrl!
        : artworkFallback ?? '',
    durationSeconds: track.durationSeconds,
    lyrics: const <String>['Lyrics unavailable for this track.'],
  );
}
