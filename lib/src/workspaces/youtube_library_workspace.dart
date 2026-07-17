import 'dart:async';

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
import 'youtube_feed_workspace.dart';

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
        if (controller.selectedFeedCollection case final detail?
            when detail.source == 'library') {
          return YouTubeFeedCollectionDetailView(
            detail: detail,
            playerController: playerController,
            isSaved: controller.isAlbumSaved(detail.id),
            isSaving: controller.albumLibraryWriteId == detail.id,
            canToggleLibrary:
                controller.albumLibraryWriteId == null &&
                !controller.isAccountWriteCoolingDown,
            onToggleLibrary: () =>
                unawaited(controller.toggleAlbumLibrary(detail)),
            onBack: controller.closeFeedDetail,
          );
        }
        if (controller.selectedPodcastShow case final detail?
            when detail.source == 'library') {
          return YouTubePodcastShowDetailView(
            detail: detail,
            loadingItemId: controller.loadingFeedItemId,
            isLoadingMore: controller.isLoadingMorePodcast,
            isSaved: controller.isPodcastSaved(detail.id),
            isSaving: controller.podcastLibraryWriteId == detail.id,
            canToggleLibrary:
                controller.podcastLibraryWriteId == null &&
                !controller.isAccountWriteCoolingDown,
            onBack: controller.closeFeedDetail,
            onLoadMore: controller.loadMorePodcastShow,
            onToggleLibrary: () =>
                unawaited(controller.togglePodcastLibrary(detail)),
            onTap: _actionFor,
          );
        }
        if (controller.selectedFeedBrowse case final detail?
            when detail.source == 'library') {
          return YouTubeFeedBrowseDetailView(
            detail: detail,
            playerController: playerController,
            youtubeLibraryController: controller,
            loadingItemId: controller.loadingFeedItemId,
            reduceMotion: shellController.reduceMotion,
            onBack: controller.closeFeedDetail,
            onTap: _actionFor,
          );
        }
        if (controller.selectedPlaylist case final detail?) {
          return _PlaylistDetailScroll(
            detail: detail,
            isLoading: controller.isLoadingPlaylist,
            isLoadingMore: controller.isLoadingMorePlaylist,
            onBack: controller.closePlaylist,
            onLoadMore: controller.loadMorePlaylist,
            playerController: playerController,
          );
        }
        return _PlaylistGrid(
          playlists: controller.playlists,
          savedCollections: controller.savedCollections,
          podcasts: controller.podcasts,
          albums: controller.albums,
          followedArtists: controller.followedArtists,
          loadingItemId: controller.loadingFeedItemId,
          loadingPlaylistId: controller.loadingPlaylistId,
          isLoading: controller.isLoadingLibrary,
          errorMessage: controller.errorMessage,
          onRefresh: () => controller.loadMediaLibrary(forceRefresh: true),
          onOpen: controller.openPlaylist,
          onOpenArtist: _openArtist,
          onOpenCollection: _openCollection,
        );
      },
    );
  }

  VoidCallback? _actionFor(YouTubeFeedItem item) {
    if (item.isCollection) {
      return () => unawaited(_openCollection(item));
    }
    if (item.isBrowsable) {
      return () => unawaited(_openArtist(item));
    }
    if (item.isPlayable) {
      return () => unawaited(_playFeedItem(item));
    }
    return null;
  }

  Future<void> _openArtist(YouTubeFeedItem item) {
    return controller.openFeedBrowse(item, source: 'library');
  }

  Future<void> _openCollection(YouTubeFeedItem item) async {
    final tracks = await controller.openFeedCollection(item, source: 'library');
    if (tracks.length != 1 || item.itemType == 'album') {
      return;
    }
    playerController.playTracks(<Track>[
      _asSimulatedTrack(
        tracks.single,
        artworkFallback: item.thumbnailUrl,
        albumFallback: item.title,
      ),
    ]);
  }

  Future<void> _playFeedItem(YouTubeFeedItem item) async {
    final track = await controller.resolveFeedTrack(item);
    playerController.playTracks(<Track>[
      _asSimulatedTrack(
        track,
        artworkFallback: item.thumbnailUrl,
        albumFallback: item.album,
      ),
    ]);
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
    required this.savedCollections,
    required this.podcasts,
    required this.albums,
    required this.followedArtists,
    required this.loadingItemId,
    required this.loadingPlaylistId,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
    required this.onOpen,
    required this.onOpenArtist,
    required this.onOpenCollection,
  });

  final List<YouTubePlaylist> playlists;
  final List<YouTubePlaylist> savedCollections;
  final List<YouTubeFeedItem> podcasts;
  final List<YouTubeFeedItem> albums;
  final List<YouTubeFeedItem> followedArtists;
  final String? loadingItemId;
  final String? loadingPlaylistId;
  final bool isLoading;
  final YouTubeLibraryError? errorMessage;
  final VoidCallback onRefresh;
  final ValueChanged<YouTubePlaylist> onOpen;
  final ValueChanged<YouTubeFeedItem> onOpenArtist;
  final ValueChanged<YouTubeFeedItem> onOpenCollection;

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
        if (isLoading) ...<Widget>[
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(
            child: LinearProgressIndicator(
              key: Key('youtube-library-loading-rail'),
            ),
          ),
        ],
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
        if (playlists.isEmpty &&
            savedCollections.isEmpty &&
            podcasts.isEmpty &&
            albums.isEmpty &&
            followedArtists.isEmpty &&
            !isLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(l10n.noMediaFound)),
          )
        else ...<Widget>[
          if (podcasts.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                0,
                AppMetrics.workspacePadding,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: _LibrarySectionHeading(title: l10n.podcasts),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.workspacePadding,
              ),
              sliver: SliverGrid(
                key: const Key('youtube-podcast-show-grid'),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 168,
                  mainAxisExtent: 224,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final podcast = podcasts[index];
                  return YouTubeFeedItemCard(
                    item: podcast,
                    isLoading: loadingItemId == podcast.id,
                    onTap: () => onOpenArtist(podcast),
                  );
                }, childCount: podcasts.length),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
          if (albums.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                0,
                AppMetrics.workspacePadding,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: _LibrarySectionHeading(title: l10n.albums),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.workspacePadding,
              ),
              sliver: SliverGrid(
                key: const Key('youtube-album-grid'),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 168,
                  mainAxisExtent: 224,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final album = albums[index];
                  return YouTubeFeedItemCard(
                    item: album,
                    isLoading: loadingItemId == album.id,
                    onTap: () => onOpenCollection(album),
                  );
                }, childCount: albums.length),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
          if (savedCollections.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                0,
                AppMetrics.workspacePadding,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: _LibrarySectionHeading(title: l10n.savedMusic),
              ),
            ),
            _PlaylistGridSection(
              key: const Key('youtube-saved-collection-grid'),
              playlists: savedCollections,
              loadingPlaylistId: loadingPlaylistId,
              onOpen: onOpen,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
          if (playlists.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                0,
                AppMetrics.workspacePadding,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: _LibrarySectionHeading(title: l10n.yourPlaylists),
              ),
            ),
            _PlaylistGridSection(
              key: const Key('youtube-playlist-grid'),
              playlists: playlists,
              loadingPlaylistId: loadingPlaylistId,
              onOpen: onOpen,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
          if (followedArtists.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                0,
                AppMetrics.workspacePadding,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: _LibrarySectionHeading(title: l10n.followedArtists),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.workspacePadding,
              ),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  key: const Key('youtube-followed-artist-grid'),
                  spacing: 20,
                  runSpacing: 20,
                  children: <Widget>[
                    for (final artist in followedArtists)
                      SizedBox(
                        width: 168,
                        height: 224,
                        child: YouTubeFeedItemCard(
                          item: artist,
                          isLoading: loadingItemId == artist.id,
                          onTap: () => onOpenArtist(artist),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
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
      key: const Key('youtube-library-header'),
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.yourMediaLibrary,
                style: const TextStyle(
                  color: OtohaColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.mediaLibrary,
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
  const _PlaylistCard({
    required this.playlist,
    required this.isLoading,
    required this.onTap,
  });

  final YouTubePlaylist playlist;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PlaylistCard(
      cardKey: Key(
        playlist.specialKind == null
            ? 'youtube-playlist-${playlist.id}'
            : 'youtube-saved-${playlist.specialKind}',
      ),
      title: playlist.title,
      subtitle: [
        playlist.owner,
        playlist.itemCount,
      ].whereType<String>().join(' · '),
      artworkPath: playlist.thumbnailUrl ?? '',
      isLoading: isLoading,
      onTap: onTap,
    );
  }
}

class _PlaylistGridSection extends StatelessWidget {
  const _PlaylistGridSection({
    required this.playlists,
    required this.loadingPlaylistId,
    required this.onOpen,
    super.key,
  });

  final List<YouTubePlaylist> playlists;
  final String? loadingPlaylistId;
  final ValueChanged<YouTubePlaylist> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.workspacePadding,
      ),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          mainAxisExtent: 224,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final playlist = playlists[index];
          return _PlaylistCard(
            playlist: playlist,
            isLoading: loadingPlaylistId == playlist.id,
            onTap: () => onOpen(playlist),
          );
        }, childCount: playlists.length),
      ),
    );
  }
}

class _LibrarySectionHeading extends StatelessWidget {
  const _LibrarySectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.headlineSmall);
  }
}

abstract class _PlaylistDetailView extends StatelessWidget {
  const _PlaylistDetailView({
    required this.detail,
    required this.isLoading,
    required this.isLoadingMore,
    required this.onBack,
    required this.onLoadMore,
    required this.playerController,
  });

  final YouTubePlaylistDetail detail;
  final bool isLoading;
  final bool isLoadingMore;
  final VoidCallback onBack;
  final Future<void> Function() onLoadMore;
  final PlayerController playerController;
}

class _PlaylistDetailScroll extends _PlaylistDetailView {
  const _PlaylistDetailScroll({
    required super.detail,
    required super.isLoading,
    required super.isLoadingMore,
    required super.onBack,
    required super.onLoadMore,
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
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 480 &&
              detail.hasMore &&
              !isLoadingMore) {
            unawaited(onLoadMore());
          }
          return false;
        },
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
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
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
                        onTap: () => playerController.playTracks(
                          playbackTracks,
                          initialIndex: trackIndex,
                        ),
                      ),
                    );
                  },
                  childCount: detail.tracks.isEmpty
                      ? 0
                      : detail.tracks.length * 2 - 1,
                ),
              ),
            ),
            if (isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
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
    videoAvailable: track.isVideo,
  );
}
