import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/artwork_image.dart';
import '../widgets/youtube_track_list_row.dart';

enum YouTubeFeedKind { home, explore }

class YouTubeFeedWorkspace extends StatelessWidget {
  const YouTubeFeedWorkspace({
    required this.kind,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    super.key,
  });

  final YouTubeFeedKind kind;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  String get _title => kind == YouTubeFeedKind.home ? 'Home' : 'Explore';
  String get _eyebrow =>
      kind == YouTubeFeedKind.home ? 'FOR YOUR ACCOUNT' : 'YOUTUBE MUSIC';

  @override
  Widget build(BuildContext context) {
    final controller = youtubeLibraryController;
    if (controller.status == YouTubeAccountStatus.restoring) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!controller.isSignedIn) {
      return Center(
        key: Key('youtube-${kind.name}-signed-out'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_title, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: Key('youtube-${kind.name}-sign-in'),
              onPressed: () => shellController.togglePanel(SidePanel.account),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in to YouTube Music'),
            ),
          ],
        ),
      );
    }

    final collection = controller.selectedFeedCollection;
    if (collection?.source == kind.name) {
      return _FeedCollectionDetail(
        detail: collection!,
        playerController: playerController,
        onBack: controller.closeFeedDetail,
      );
    }
    final browse = controller.selectedFeedBrowse;
    if (browse?.source == kind.name) {
      return _FeedBrowseDetail(
        detail: browse!,
        loadingItemId: controller.loadingFeedItemId,
        reduceMotion: shellController.reduceMotion,
        onBack: controller.closeFeedDetail,
        onTap: _actionFor,
      );
    }

    final sections = kind == YouTubeFeedKind.home
        ? controller.homeSections
        : controller.exploreSections;
    final isLoading = kind == YouTubeFeedKind.home
        ? controller.isLoadingHome
        : controller.isLoadingExplore;
    final feedErrorMessage = kind == YouTubeFeedKind.home
        ? controller.homeErrorMessage
        : controller.exploreErrorMessage;
    final errorMessage = controller.feedActionErrorMessage ?? feedErrorMessage;
    final refresh = kind == YouTubeFeedKind.home
        ? controller.loadHome
        : controller.loadExplore;

    return CustomScrollView(
      key: Key('youtube-${kind.name}-feed'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            24,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _eyebrow,
                        style: const TextStyle(
                          color: OtohaColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _title,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Refresh $_title',
                  child: IconButton(
                    key: Key('youtube-${kind.name}-refresh'),
                    onPressed: isLoading ? null : refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isLoading)
          const SliverToBoxAdapter(child: LinearProgressIndicator()),
        if (errorMessage != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              16,
              AppMetrics.workspacePadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                errorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (sections.isEmpty && isLoading)
          const SliverToBoxAdapter(child: _FeedSkeleton())
        else if (sections.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: TextButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Load again'),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final section = sections[index];
              return _FeedSection(
                section: section,
                sectionIndex: index,
                loadingItemId: controller.loadingFeedItemId,
                reduceMotion: shellController.reduceMotion,
                onTap: _actionFor,
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  VoidCallback? _actionFor(YouTubeFeedItem item) {
    if (item.isCollection) {
      return () => unawaited(_openCollection(item));
    }
    if (item.isBrowsable) {
      return () => unawaited(
        youtubeLibraryController.openFeedBrowse(item, source: kind.name),
      );
    }
    if (item.isPlayable) {
      return () => unawaited(_playFeedItem(item));
    }
    return null;
  }

  Future<void> _openCollection(YouTubeFeedItem item) async {
    final tracks = await youtubeLibraryController.openFeedCollection(
      item,
      source: kind.name,
    );
    if (tracks.length == 1) {
      playerController.playTracks(<Track>[
        _asSimulatedYouTubeTrack(
          tracks[0],
          artworkFallback: item.thumbnailUrl,
          albumFallback: item.title,
          artistFallback: item.artists,
        ),
      ]);
    }
  }

  Future<void> _playFeedItem(YouTubeFeedItem item) async {
    final track = await youtubeLibraryController.resolveFeedTrack(item);
    playerController.playTracks(<Track>[_asSimulatedYouTubeTrack(track)]);
  }
}

class _FeedSection extends StatefulWidget {
  const _FeedSection({
    required this.section,
    required this.sectionIndex,
    required this.loadingItemId,
    required this.reduceMotion,
    required this.onTap,
  });

  final YouTubeFeedSection section;
  final int sectionIndex;
  final String? loadingItemId;
  final bool reduceMotion;
  final VoidCallback? Function(YouTubeFeedItem item) onTap;

  @override
  State<_FeedSection> createState() => _FeedSectionState();
}

class _FeedSectionState extends State<_FeedSection> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double direction) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target = (position.pixels + direction * position.viewportDimension)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if (widget.reduceMotion) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppMetrics.workspacePadding,
        20,
        0,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppMetrics.workspacePadding),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Tooltip(
                  message: 'Scroll ${widget.section.title} left',
                  child: IconButton(
                    key: Key('youtube-feed-scroll-left-${widget.sectionIndex}'),
                    onPressed: () => _scrollBy(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
                Tooltip(
                  message: 'Scroll ${widget.section.title} right',
                  child: IconButton(
                    key: Key(
                      'youtube-feed-scroll-right-${widget.sectionIndex}',
                    ),
                    onPressed: () => _scrollBy(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 224,
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(
                right: AppMetrics.workspacePadding,
              ),
              itemCount: widget.section.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                final item = widget.section.items[index];
                return _FeedItemCard(
                  item: item,
                  isLoading: widget.loadingItemId == item.id,
                  onTap: widget.onTap(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  const _FeedItemCard({
    required this.item,
    required this.isLoading,
    required this.onTap,
  });

  final YouTubeFeedItem item;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final profile = item.isProfile;
    return SizedBox(
      width: 168,
      child: InkWell(
        key: Key('youtube-feed-${item.itemType}-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox.square(
              dimension: 168,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (profile)
                    Center(
                      child: SizedBox.square(
                        dimension: 144,
                        child: ClipOval(
                          key: Key('youtube-feed-profile-artwork-${item.id}'),
                          child: ArtworkImage(
                            assetPath: item.thumbnailUrl ?? '',
                            semanticLabel: '${item.title} profile image',
                          ),
                        ),
                      ),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppMetrics.radius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          if (item.itemType == 'category' &&
                              item.thumbnailUrl == null)
                            Semantics(
                              label: '${item.title} mood and genre',
                              child: const ColoredBox(
                                color: OtohaColors.surfaceRaised,
                                child: Center(
                                  child: Icon(
                                    Icons.tune_rounded,
                                    color: OtohaColors.accent,
                                    size: 28,
                                  ),
                                ),
                              ),
                            )
                          else
                            ArtworkImage(
                              assetPath: item.thumbnailUrl ?? '',
                              semanticLabel: '${item.title} artwork',
                            ),
                        ],
                      ),
                    ),
                  if (isLoading)
                    const Positioned.fill(
                      key: Key('youtube-feed-loading-overlay'),
                      child: ColoredBox(
                        color: Color(0x99000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 3),
            Text(
              item.subtitle ?? _typeLabel(item.itemType),
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

class _FeedCollectionDetail extends StatelessWidget {
  const _FeedCollectionDetail({
    required this.detail,
    required this.playerController,
    required this.onBack,
  });

  final YouTubeFeedCollectionDetail detail;
  final PlayerController playerController;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tracks = detail.tracks
        .map(
          (track) => _asSimulatedYouTubeTrack(
            track,
            artworkFallback: detail.thumbnailUrl,
            albumFallback: detail.title,
            artistFallback: detail.artists,
          ),
        )
        .toList(growable: false);
    return CustomScrollView(
      key: const Key('youtube-feed-collection-detail'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            24,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: <Widget>[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    key: const Key('youtube-feed-collection-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _typeLabel(detail.itemType).toUpperCase(),
                        style: const TextStyle(
                          color: OtohaColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${detail.tracks.length} tracks',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.workspacePadding,
          ),
          sliver: SliverList.separated(
            itemCount: detail.tracks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final sourceTrack = detail.tracks[index];
              return AnimatedBuilder(
                animation: playerController,
                builder: (context, _) => YouTubeTrackListRow(
                  rowKey: Key(
                    'youtube-feed-detail-track-${sourceTrack.videoId}',
                  ),
                  index: index + 1,
                  track: sourceTrack,
                  artworkFallback: detail.thumbnailUrl,
                  artistFallback: detail.artists,
                  isSelected:
                      playerController.currentTrack.id == tracks[index].id,
                  onTap: () {
                    playerController.playTracks(tracks);
                    playerController.selectTrack(tracks[index]);
                  },
                ),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _FeedBrowseDetail extends StatelessWidget {
  const _FeedBrowseDetail({
    required this.detail,
    required this.loadingItemId,
    required this.reduceMotion,
    required this.onBack,
    required this.onTap,
  });

  final YouTubeFeedBrowseDetail detail;
  final String? loadingItemId;
  final bool reduceMotion;
  final VoidCallback onBack;
  final VoidCallback? Function(YouTubeFeedItem item) onTap;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const Key('youtube-feed-browse-detail'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            AppMetrics.workspacePadding,
            24,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: <Widget>[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    key: const Key('youtube-feed-browse-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    detail.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: detail.sections.length,
          itemBuilder: (context, index) => _FeedSection(
            section: detail.sections[index],
            sectionIndex: index,
            loadingItemId: loadingItemId,
            reduceMotion: reduceMotion,
            onTap: onTap,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppMetrics.workspacePadding),
      child: Row(
        children: List<Widget>.generate(
          5,
          (index) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == 4 ? 0 : 20),
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: OtohaColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppMetrics.radius),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Track _asSimulatedYouTubeTrack(
  YouTubeTrack track, {
  String? artworkFallback,
  String? albumFallback,
  List<String> artistFallback = const <String>[],
}) {
  return Track(
    id: 'youtube:${track.videoId}',
    title: track.title,
    artist: track.artists.isNotEmpty
        ? track.artists.join(', ')
        : artistFallback.isNotEmpty
        ? artistFallback.join(', ')
        : 'YouTube Music',
    album: track.album ?? albumFallback ?? 'YouTube Music',
    artworkAsset: _detailArtwork(track.thumbnailUrl, artworkFallback),
    durationSeconds: track.durationSeconds,
    lyrics: const <String>['Lyrics are not available for this track.'],
  );
}

String _typeLabel(String type) {
  return switch (type) {
    'album' => 'Album',
    'artist' => 'Artist',
    'category' => 'Mood & genre',
    'episode' => 'Episode',
    'playlist' => 'Playlist',
    'song' => 'Song',
    'video' => 'Music video',
    _ => 'YouTube Music',
  };
}

String _detailArtwork(String? trackArtwork, String? collectionArtwork) {
  if (trackArtwork != null && trackArtwork.isNotEmpty) {
    return trackArtwork;
  }
  return collectionArtwork ?? '';
}
