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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = kind == YouTubeFeedKind.home ? l10n.home : l10n.explore;
    final eyebrow = kind == YouTubeFeedKind.home
        ? l10n.forYourAccount
        : l10n.youtubeMusic;
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
            Text(title, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: Key('youtube-${kind.name}-sign-in'),
              onPressed: () => shellController.togglePanel(SidePanel.account),
              icon: const Icon(Icons.login_rounded),
              label: Text(l10n.signInToYouTubeMusic),
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
        : controller.isLoadingExplore || controller.isLoadingFeedBrowse;
    final feedErrorMessage = kind == YouTubeFeedKind.home
        ? controller.homeErrorMessage
        : controller.exploreErrorMessage;
    final errorMessage = controller.feedActionErrorMessage ?? feedErrorMessage;
    final refresh = kind == YouTubeFeedKind.home
        ? () => unawaited(controller.loadHome(forceRefresh: true))
        : () => unawaited(controller.loadExplore(forceRefresh: true));

    final isHome = kind == YouTubeFeedKind.home;
    final isLoadingMore = isHome
        ? controller.isLoadingMoreHome
        : controller.isLoadingMoreExplore;
    final hasMore = isHome ? controller.hasMoreHome : controller.hasMoreExplore;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 640 &&
            !isLoadingMore &&
            hasMore) {
          unawaited(
            isHome ? controller.loadMoreHome() : controller.loadMoreExplore(),
          );
        }
        return false;
      },
      child: CustomScrollView(
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
                          eyebrow,
                          style: const TextStyle(
                            color: OtohaColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: l10n.refreshSection(title),
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
          if (kind == YouTubeFeedKind.explore &&
              controller.exploreCategories.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                0,
                AppMetrics.workspacePadding,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: _ExploreCategoryTabs(
                  categories: controller.exploreCategories,
                  selectedCategoryId: controller.selectedExploreCategoryId,
                  onReset: () =>
                      unawaited(controller.loadExplore(forceRefresh: true)),
                  onSelected: (item) => unawaited(
                    controller.openFeedBrowse(item, source: kind.name),
                  ),
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
                  localizeYouTubeLibraryError(errorMessage, l10n),
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
                  label: Text(l10n.loadAgain),
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
          if (isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
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

class _ExploreCategoryTabs extends StatefulWidget {
  const _ExploreCategoryTabs({
    required this.categories,
    required this.selectedCategoryId,
    required this.onReset,
    required this.onSelected,
  });

  final List<YouTubeFeedItem> categories;
  final String? selectedCategoryId;
  final VoidCallback onReset;
  final ValueChanged<YouTubeFeedItem> onSelected;

  @override
  State<_ExploreCategoryTabs> createState() => _ExploreCategoryTabsState();
}

class _ExploreCategoryTabsState extends State<_ExploreCategoryTabs> {
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
    final target = (position.pixels + direction * 280)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected = widget.selectedCategoryId;
    return SizedBox(
      height: 42,
      child: Row(
        children: <Widget>[
          Tooltip(
            message: l10n.scrollMoodsGenresLeft,
            child: IconButton(
              key: const Key('youtube-explore-tabs-left'),
              onPressed: () => _scrollBy(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _ExploreCategoryTab(
                  label: l10n.forYou,
                  selected: selected == null,
                  onTap: selected == null ? null : widget.onReset,
                ),
                for (final category in widget.categories)
                  _ExploreCategoryTab(
                    key: Key('youtube-explore-tab-${category.browseIdentity}'),
                    label: category.title,
                    selected: selected == category.browseIdentity,
                    onTap: () => widget.onSelected(category),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: l10n.scrollMoodsGenresRight,
            child: IconButton(
              key: const Key('youtube-explore-tabs-right'),
              onPressed: () => _scrollBy(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreCategoryTab extends StatelessWidget {
  const _ExploreCategoryTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? OtohaColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? OtohaColors.text : OtohaColors.mutedText,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
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
    final l10n = AppLocalizations.of(context)!;
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
                  message: l10n.scrollSectionLeft(widget.section.title),
                  child: IconButton(
                    key: Key('youtube-feed-scroll-left-${widget.sectionIndex}'),
                    onPressed: () => _scrollBy(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
                Tooltip(
                  message: l10n.scrollSectionRight(widget.section.title),
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
    final l10n = AppLocalizations.of(context)!;
    final profile = item.isProfile;
    return SizedBox(
      width: 168,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Column(
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
                            dimension: 168,
                            child: ClipOval(
                              key: Key(
                                'youtube-feed-profile-artwork-${item.id}',
                              ),
                              child: ArtworkImage(
                                assetPath: item.thumbnailUrl ?? '',
                                semanticLabel: l10n.profileImage(item.title),
                              ),
                            ),
                          ),
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppMetrics.radius,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              if (item.itemType == 'category' &&
                                  item.thumbnailUrl == null)
                                Semantics(
                                  label: l10n.moodAndGenreLabel(item.title),
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
                                  semanticLabel: l10n.artwork(item.title),
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
                  item.subtitle ?? _typeLabel(item.itemType, l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppMetrics.radius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key('youtube-feed-${item.itemType}-${item.id}'),
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppMetrics.radius),
                  child: const SizedBox.expand(),
                ),
              ),
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
    final l10n = AppLocalizations.of(context)!;
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
                  message: l10n.back,
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
                        _typeLabel(detail.itemType, l10n).toUpperCase(),
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
                  l10n.tracksCount(detail.tracks.length),
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
            separatorBuilder: (_, _) => const SizedBox(height: 2),
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
                      playerController.currentTrack?.id == tracks[index].id,
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
    final l10n = AppLocalizations.of(context)!;
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
                  message: l10n.back,
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
    lyrics: const <String>[],
    youtubeVideoId: track.videoId,
  );
}

String _typeLabel(String type, AppLocalizations l10n) {
  return switch (type) {
    'album' => l10n.album,
    'artist' => l10n.artist,
    'category' => l10n.moodAndGenre,
    'episode' => l10n.episode,
    'playlist' => l10n.playlist,
    'song' => l10n.song,
    'video' => l10n.musicVideo,
    _ => l10n.youtubeMusic,
  };
}

String _detailArtwork(String? trackArtwork, String? collectionArtwork) {
  if (trackArtwork != null && trackArtwork.isNotEmpty) {
    return trackArtwork;
  }
  return collectionArtwork ?? '';
}
