import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../app/youtube_library_error_localizations.dart';
import '../models/catalog.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/artwork_image.dart';
import '../widgets/playlist_card.dart';
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
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.status == YouTubeAccountStatus.restoring) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.isSignedIn) {
          return _SignedOutLibrary(
            shellController: shellController,
            signInLabel: l10n.signInToYouTubeMusic,
          );
        }
        if (controller.selectedPlaylist case final detail?) {
          return _PlaylistDetailScroll(
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
  const _SignedOutLibrary({
    required this.shellController,
    required this.signInLabel,
  });

  final ShellController shellController;
  final String signInLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('youtube-library-signed-out'),
      child: FilledButton.icon(
        key: const Key('youtube-library-sign-in'),
        onPressed: () => shellController.togglePanel(SidePanel.account),
        icon: const Icon(Icons.login_rounded),
        label: Text(signInLabel),
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
  final YouTubeLibraryError? errorMessage;
  final VoidCallback onRefresh;
  final ValueChanged<YouTubePlaylist> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CustomScrollView(
      key: const Key('youtube-library-scroll'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _LibraryHeader(isLoading: isLoading, onRefresh: onRefresh),
          ),
        ),
        if (isLoading)
          const SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: AppMetrics.workspacePadding,
              vertical: 16,
            ),
            sliver: SliverToBoxAdapter(child: LinearProgressIndicator()),
          ),
        if (errorMessage != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              0,
              AppMetrics.workspacePadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                localizeYouTubeLibraryError(errorMessage!, l10n),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        if (playlists.isEmpty && !isLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(l10n.noPlaylistsFound)),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.workspacePadding,
            ),
            sliver: SliverGrid(
              key: const Key('youtube-playlist-grid'),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 244,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final playlist = playlists[index];
                return _PlaylistCard(
                  playlist: playlist,
                  onTap: () => onOpen(playlist),
                );
              }, childCount: playlists.length),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.isLoading, required this.onRefresh});

  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.yourLibrary,
                style: const TextStyle(
                  color: OtohaColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.yourPlaylists,
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
        Tooltip(
          message: l10n.syncLibrary,
          child: IconButton(
            key: const Key('youtube-library-refresh'),
            onPressed: isLoading ? null : onRefresh,
            icon: const Icon(Icons.sync_rounded),
          ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.onTap});

  final YouTubePlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PlaylistCard(
      cardKey: Key('youtube-playlist-${playlist.id}'),
      title: playlist.title,
      subtitle: [
        playlist.owner,
        playlist.itemCount,
      ].whereType<String>().join(' · '),
      artworkPath: playlist.thumbnailUrl ?? '',
      onTap: onTap,
    );
  }
}

abstract class _PlaylistDetailView extends StatelessWidget {
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
}

class _PlaylistDetailScroll extends _PlaylistDetailView {
  const _PlaylistDetailScroll({
    required super.detail,
    required super.isLoading,
    required super.onBack,
    required super.playerController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final playbackTracks = detail.tracks
        .map(
          (track) => _asSimulatedTrack(
            track,
            artworkFallback: detail.playlist.thumbnailUrl,
            albumFallback: detail.playlist.title,
          ),
        )
        .toList(growable: false);
    return KeyedSubtree(
      key: const Key('youtube-playlist-detail'),
      child: CustomScrollView(
        key: const Key('youtube-playlist-detail-scroll'),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  IconButton(
                    key: const Key('youtube-playlist-back'),
                    onPressed: onBack,
                    tooltip: l10n.backToPlaylists,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppMetrics.radius),
                    child: SizedBox.square(
                      dimension: 144,
                      child: ArtworkImage(
                        assetPath: detail.playlist.thumbnailUrl ?? '',
                        semanticLabel: l10n.artwork(detail.playlist.title),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.playlist,
                          style: const TextStyle(
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
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          if (isLoading)
            const SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: AppMetrics.workspacePadding,
                vertical: 16,
              ),
              sliver: SliverToBoxAdapter(child: LinearProgressIndicator()),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.workspacePadding,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index.isOdd) {
                  return const SizedBox(height: 2);
                }
                final trackIndex = index ~/ 2;
                final track = detail.tracks[trackIndex];
                return AnimatedBuilder(
                  animation: playerController,
                  builder: (context, _) => YouTubeTrackListRow(
                    rowKey: Key('youtube-track-${track.videoId}'),
                    index: trackIndex + 1,
                    track: track,
                    artworkFallback: detail.playlist.thumbnailUrl,
                    isSelected:
                        playerController.currentTrack?.id ==
                        playbackTracks[trackIndex].id,
                    onTap: () {
                      playerController.playTracks(playbackTracks);
                      playerController.selectTrack(playbackTracks[trackIndex]);
                    },
                  ),
                );
              }, childCount: detail.tracks.length * 2 - 1),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
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
    lyrics: const <String>[],
    youtubeVideoId: track.videoId,
  );
}
