import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../app/youtube_library_error_localizations.dart';
import '../models/catalog.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/artwork_image.dart';
import '../widgets/workspace_filter_tabs.dart';
import '../widgets/workspace_result_row.dart';
import '../widgets/youtube_track_list_row.dart';

enum YouTubeFeedKind { home, explore }

const String _forYouFilterId = '__for_you__';
const String _moodAndGenreRootBrowseId = 'FEmusic_moods_and_genres';

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
      return YouTubeFeedCollectionDetailView(
        detail: collection!,
        playerController: playerController,
        isSaved: controller.isAlbumSaved(collection.id),
        isSaving: controller.albumLibraryWriteId == collection.id,
        canToggleLibrary:
            controller.albumLibraryWriteId == null &&
            !controller.isAccountWriteCoolingDown,
        onToggleLibrary: () =>
            unawaited(controller.toggleAlbumLibrary(collection)),
        onBack: controller.closeFeedDetail,
      );
    }
    final podcast = controller.selectedPodcastShow;
    if (podcast?.source == kind.name) {
      return YouTubePodcastShowDetailView(
        detail: podcast!,
        loadingItemId: controller.loadingFeedItemId,
        isLoadingMore: controller.isLoadingMorePodcast,
        isSaved: controller.isPodcastSaved(podcast.id),
        isSaving: controller.podcastLibraryWriteId == podcast.id,
        canToggleLibrary:
            controller.podcastLibraryWriteId == null &&
            !controller.isAccountWriteCoolingDown,
        onBack: controller.closeFeedDetail,
        onLoadMore: controller.loadMorePodcastShow,
        onToggleLibrary: () =>
            unawaited(controller.togglePodcastLibrary(podcast)),
        onTap: _actionFor,
      );
    }
    final browse = controller.selectedFeedBrowse;
    if (browse?.source == kind.name) {
      return YouTubeFeedBrowseDetailView(
        detail: browse!,
        playerController: playerController,
        youtubeLibraryController: controller,
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

    final isHome = kind == YouTubeFeedKind.home;
    final isLoadingMore = isHome
        ? controller.isLoadingMoreHome
        : controller.isLoadingMoreExplore;
    final exploreCategories = controller.exploreCategories
        .where((item) => item.id != _moodAndGenreRootBrowseId)
        .toList(growable: false);
    final filterOptions = isHome
        ? <WorkspaceFilterTabOption<String>>[
            if (controller.homeFilters.isNotEmpty)
              WorkspaceFilterTabOption<String>(
                value: _forYouFilterId,
                label: l10n.forYou,
                tabKey: Key('youtube-${kind.name}-tab-$_forYouFilterId'),
              ),
            for (final filter in controller.homeFilters)
              WorkspaceFilterTabOption<String>(
                value: filter,
                label: filter,
                tabKey: Key('youtube-${kind.name}-tab-$filter'),
              ),
          ]
        : <WorkspaceFilterTabOption<String>>[
            if (exploreCategories.isNotEmpty)
              WorkspaceFilterTabOption<String>(
                value: _forYouFilterId,
                label: l10n.forYou,
                tabKey: Key('youtube-${kind.name}-tab-$_forYouFilterId'),
              ),
            for (final category in exploreCategories)
              WorkspaceFilterTabOption<String>(
                value: category.browseIdentity,
                label: category.title,
                tabKey: Key(
                  'youtube-${kind.name}-tab-${category.browseIdentity}',
                ),
              ),
          ];
    final selectedFilterId = isHome
        ? controller.selectedHomeFilter ??
              (filterOptions.isEmpty ? null : _forYouFilterId)
        : controller.selectedExploreCategoryId ??
              (filterOptions.isEmpty ? null : _forYouFilterId);

    void selectFilter(String id, {bool forceRefresh = false}) {
      if (isHome) {
        unawaited(
          id == _forYouFilterId
              ? controller.loadHome(forceRefresh: true)
              : controller.selectHomeFilter(id, forceRefresh: forceRefresh),
        );
        return;
      }
      if (id == _forYouFilterId) {
        unawaited(controller.loadExplore(forceRefresh: true));
        return;
      }
      final category = exploreCategories.firstWhere(
        (item) => item.browseIdentity == id,
      );
      unawaited(controller.openFeedBrowse(category, source: kind.name));
    }

    void refresh() {
      if (selectedFilterId == null || selectedFilterId == _forYouFilterId) {
        unawaited(
          isHome
              ? controller.loadHome(forceRefresh: true)
              : controller.loadExplore(forceRefresh: true),
        );
        return;
      }
      selectFilter(selectedFilterId, forceRefresh: true);
    }

    return _FeedBackdrop(
      key: Key('youtube-${kind.name}-backdrop'),
      identity: '${kind.name}:${selectedFilterId ?? 'default'}',
      artworkUrl: _firstFeedArtwork(sections),
      reduceMotion: shellController.reduceMotion,
      child: _FeedPaginationScroll(
        youtubeLibraryController: controller,
        isHome: isHome,
        scrollKey: Key('youtube-${kind.name}-feed'),
        slivers: <Widget>[
          if (filterOptions.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                24,
                AppMetrics.workspacePadding,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: WorkspaceFilterTabs<String>(
                  key: Key('youtube-${kind.name}-tabs'),
                  options: filterOptions,
                  selectedValue: selectedFilterId,
                  reduceMotion: shellController.reduceMotion,
                  onSelected: selectFilter,
                  scrollLeftKey: Key('youtube-${kind.name}-tabs-left'),
                  scrollRightKey: Key('youtube-${kind.name}-tabs-right'),
                  scrollLeftTooltip: l10n.scrollFeedFiltersLeft,
                  scrollRightTooltip: l10n.scrollFeedFiltersRight,
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              filterOptions.isEmpty ? AppMetrics.workspacePadding : 16,
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
                return YouTubeFeedSectionView(
                  key: ValueKey<String>(
                    '${kind.name}:${selectedFilterId ?? 'default'}:'
                    '${section.title}:$index',
                  ),
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
    if (tracks.length == 1 && item.itemType != 'album') {
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
    playerController.playTracks(<Track>[
      _asSimulatedYouTubeTrack(
        track,
        artistFallback: item.artists,
        subtitleFallback: item.subtitle,
        itemTypeFallback: item.itemType,
      ),
    ]);
  }
}

class _FeedPaginationScroll extends StatefulWidget {
  const _FeedPaginationScroll({
    required this.youtubeLibraryController,
    required this.isHome,
    required this.scrollKey,
    required this.slivers,
  });

  final YouTubeLibraryController youtubeLibraryController;
  final bool isHome;
  final Key scrollKey;
  final List<Widget> slivers;

  @override
  State<_FeedPaginationScroll> createState() => _FeedPaginationScrollState();
}

class _FeedPaginationScrollState extends State<_FeedPaginationScroll> {
  final ScrollController _scrollController = ScrollController();
  bool _checkScheduled = false;
  bool _isRequesting = false;
  bool _autoRetryBlocked = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    widget.youtubeLibraryController.addListener(_schedulePaginationCheck);
    _schedulePaginationCheck();
  }

  @override
  void didUpdateWidget(covariant _FeedPaginationScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeLibraryController != widget.youtubeLibraryController) {
      oldWidget.youtubeLibraryController.removeListener(
        _schedulePaginationCheck,
      );
      widget.youtubeLibraryController.addListener(_schedulePaginationCheck);
    }
    _schedulePaginationCheck();
  }

  @override
  void dispose() {
    widget.youtubeLibraryController.removeListener(_schedulePaginationCheck);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _schedulePaginationCheck() {
    if (_checkScheduled) {
      return;
    }
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) {
        _checkPagination();
      }
    });
  }

  void _handleScroll() {
    if (!_isRequesting) {
      _autoRetryBlocked = false;
    }
    _checkPagination(isUserScroll: true);
  }

  void _checkPagination({bool isUserScroll = false}) {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 640 ||
        _isRequesting ||
        (_autoRetryBlocked && !isUserScroll)) {
      return;
    }
    final controller = widget.youtubeLibraryController;
    if (widget.isHome) {
      if (controller.hasMoreHome &&
          !controller.isLoadingHome &&
          !controller.isLoadingMoreHome) {
        unawaited(_loadMore(controller.loadMoreHome));
      }
      return;
    }
    if (controller.hasMoreExplore &&
        !controller.isLoadingExplore &&
        !controller.isLoadingMoreExplore) {
      unawaited(_loadMore(controller.loadMoreExplore));
    }
  }

  Future<void> _loadMore(Future<void> Function() request) async {
    _isRequesting = true;
    await request();
    if (!mounted) {
      return;
    }
    final controller = widget.youtubeLibraryController;
    _autoRetryBlocked = widget.isHome
        ? controller.homeErrorMessage != null
        : controller.exploreErrorMessage != null;
    _isRequesting = false;
    if (!_autoRetryBlocked) {
      _schedulePaginationCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: widget.scrollKey,
      controller: _scrollController,
      slivers: widget.slivers,
    );
  }
}

class _FeedBackdrop extends StatefulWidget {
  const _FeedBackdrop({
    required this.identity,
    required this.artworkUrl,
    required this.reduceMotion,
    required this.child,
    super.key,
  });

  final String identity;
  final String? artworkUrl;
  final bool reduceMotion;
  final Widget child;

  @override
  State<_FeedBackdrop> createState() => _FeedBackdropState();
}

class _FeedBackdropState extends State<_FeedBackdrop> {
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(widget.identity);
    final duration = widget.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 520);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ValueListenableBuilder<double>(
          valueListenable: _scrollOffset,
          builder: (context, scrollOffset, child) {
            final travel = scrollOffset.clamp(0.0, 320.0);
            final opacity = (1 - scrollOffset / 260).clamp(0.0, 1.0);
            return Positioned(
              top: -travel * 0.65 - 72,
              left: -72,
              right: -72,
              height: 392,
              child: IgnorePointer(
                child: Opacity(
                  opacity: opacity,
                  child: RepaintBoundary(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                      child: AnimatedSwitcher(
                        key: const Key('youtube-feed-backdrop-switcher'),
                        duration: duration,
                        switchInCurve: Curves.linear,
                        switchOutCurve: Curves.linear,
                        transitionBuilder: (child, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            child: child,
                            builder: (context, child) {
                              final progress = animation.value;
                              return Opacity(
                                opacity: progress,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    child!,
                                    if (progress < 1)
                                      ColoredBox(
                                        color: OtohaColors.canvas.withValues(
                                          alpha: (1 - progress) * 0.5,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        child: SizedBox.expand(
                          key: ValueKey<String>(widget.identity),
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: <Color>[
                                      palette.$1.withValues(alpha: 0.42),
                                      palette.$2.withValues(alpha: 0.28),
                                      OtohaColors.canvas.withValues(alpha: 0),
                                    ],
                                    stops: const <double>[0, 0.48, 1],
                                  ),
                                ),
                              ),
                              if (widget.artworkUrl != null)
                                Image.network(
                                  key: Key(
                                    'youtube-feed-backdrop-artwork:'
                                    '${widget.artworkUrl}',
                                  ),
                                  widget.artworkUrl!,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                  filterQuality: FilterQuality.low,
                                  gaplessPlayback: true,
                                  frameBuilder: (context, child, frame, _) {
                                    return TweenAnimationBuilder<double>(
                                      key: ValueKey<String>(
                                        'youtube-feed-backdrop-frame:'
                                        '${widget.artworkUrl}',
                                      ),
                                      duration: widget.reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 420),
                                      curve: Curves.linear,
                                      tween: Tween<double>(
                                        begin: 0,
                                        end: frame == null ? 0 : 1,
                                      ),
                                      builder: (context, opacity, artwork) =>
                                          Opacity(
                                            opacity: opacity,
                                            child: artwork,
                                          ),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: <Widget>[
                                          child,
                                          ColoredBox(
                                            color: OtohaColors.canvas
                                                .withValues(alpha: 0.4),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) =>
                                      const SizedBox.shrink(),
                                ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: <Color>[
                                      OtohaColors.canvas.withValues(
                                        alpha: 0.04,
                                      ),
                                      OtohaColors.canvas.withValues(alpha: 0.5),
                                      OtohaColors.canvas,
                                    ],
                                    stops: const <double>[0, 0.58, 1],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              final next = notification.metrics.pixels.clamp(0.0, 320.0);
              if ((next - _scrollOffset.value).abs() >= 1) {
                _scrollOffset.value = next;
              }
            }
            return false;
          },
          child: widget.child,
        ),
      ],
    );
  }

  (Color, Color) _paletteFor(String identity) {
    const palettes = <(Color, Color)>[
      (Color(0xFF796333), Color(0xFF31584B)),
      (Color(0xFF704744), Color(0xFF68703D)),
      (Color(0xFF365A61), Color(0xFF6A4D5E)),
      (Color(0xFF53693C), Color(0xFF765039)),
    ];
    final hash = identity.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return palettes[hash % palettes.length];
  }
}

class YouTubeFeedSectionView extends StatefulWidget {
  const YouTubeFeedSectionView({
    required this.section,
    required this.sectionIndex,
    required this.loadingItemId,
    required this.reduceMotion,
    required this.onTap,
    super.key,
  });

  final YouTubeFeedSection section;
  final int sectionIndex;
  final String? loadingItemId;
  final bool reduceMotion;
  final VoidCallback? Function(YouTubeFeedItem item) onTap;

  @override
  State<YouTubeFeedSectionView> createState() => _YouTubeFeedSectionViewState();
}

class _YouTubeFeedSectionViewState extends State<YouTubeFeedSectionView> {
  static const double _cardItemExtent = 188;
  static const double _compactColumnWidth = 360;
  static const double _compactColumnExtent = 380;
  static const double _compactRowHeight = 64;
  static const double _compactRowGap = 8;

  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(keepScrollOffset: false)
      ..addListener(_updateScrollActions);
    _updateScrollActionsAfterLayout();
  }

  @override
  void didUpdateWidget(covariant YouTubeFeedSectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.items.length != widget.section.items.length ||
        oldWidget.section.itemsPerColumn != widget.section.itemsPerColumn ||
        _sectionUsesCompactRows(oldWidget.section) != _usesCompactRows) {
      _updateScrollActionsAfterLayout();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollActions);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollActionsAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateScrollActions();
      }
    });
  }

  void _updateScrollActions() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final maxScrollOffset = _alignedMaxScrollOffset(position);
    final canScrollLeft = position.pixels > 0.5;
    final canScrollRight = position.pixels < maxScrollOffset - 0.5;
    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }
    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  void _scrollBy(double direction) {
    if (!_scrollController.hasClients ||
        (direction < 0 && !_canScrollLeft) ||
        (direction > 0 && !_canScrollRight)) {
      return;
    }
    final position = _scrollController.position;
    final itemExtent = _itemExtent;
    final visibleItemCount = (position.viewportDimension / itemExtent).floor();
    final pageExtent =
        (visibleItemCount < 1 ? 1 : visibleItemCount) * itemExtent;
    final targetPage = direction > 0
        ? ((position.pixels + 0.5) / pageExtent).floor() + 1
        : ((position.pixels - 0.5) / pageExtent).ceil() - 1;
    final target = (targetPage * pageExtent)
        .clamp(0.0, _alignedMaxScrollOffset(position))
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

  bool get _usesCompactRows => _sectionUsesCompactRows(widget.section);

  int get _effectiveItemsPerColumn {
    final configured = widget.section.itemsPerColumn.clamp(1, 6);
    if (configured > 1 || !_usesCompactRows) {
      return configured;
    }
    return widget.section.items.length.clamp(1, 4);
  }

  static bool _sectionUsesCompactRows(YouTubeFeedSection section) {
    return section.itemsPerColumn > 1 ||
        section.items.any((item) => item.rank != null);
  }

  double get _itemExtent =>
      _usesCompactRows ? _compactColumnExtent : _cardItemExtent;

  int get _scrollItemCount => _usesCompactRows
      ? (widget.section.items.length / _effectiveItemsPerColumn).ceil()
      : widget.section.items.length;

  double _alignedMaxScrollOffset(ScrollPosition position) {
    final itemCount = _scrollItemCount;
    if (itemCount <= 0) {
      return 0;
    }
    final contentExtent = itemCount * _itemExtent - 20;
    final overflow = contentExtent - position.viewportDimension;
    if (overflow <= 0) {
      return 0;
    }
    return (overflow / _itemExtent).ceil() * _itemExtent;
  }

  double _trailingPadding(double viewportDimension) {
    final itemCount = _scrollItemCount;
    if (itemCount <= 0) {
      return AppMetrics.workspacePadding;
    }
    final contentExtent = itemCount * _itemExtent - 20;
    final overflow = contentExtent - viewportDimension;
    if (overflow <= 0) {
      return AppMetrics.workspacePadding;
    }
    final alignedOffset = (overflow / _itemExtent).ceil() * _itemExtent;
    final requiredPadding = alignedOffset + viewportDimension - contentExtent;
    return requiredPadding > AppMetrics.workspacePadding
        ? requiredPadding
        : AppMetrics.workspacePadding;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final itemsPerColumn = _effectiveItemsPerColumn;
    final usesCompactRows = _usesCompactRows;
    final columnCount = (widget.section.items.length / itemsPerColumn).ceil();
    final contentHeight = usesCompactRows
        ? itemsPerColumn * _compactRowHeight +
              (itemsPerColumn - 1) * _compactRowGap
        : 224.0;
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (widget.section.subtitle case final subtitle?
                          when subtitle.isNotEmpty) ...<Widget>[
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        widget.section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: l10n.scrollSectionLeft(widget.section.title),
                  child: IconButton(
                    key: Key('youtube-feed-scroll-left-${widget.sectionIndex}'),
                    color: OtohaColors.text,
                    disabledColor: OtohaColors.mutedText.withValues(alpha: 0.4),
                    onPressed: _canScrollLeft ? () => _scrollBy(-1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
                Tooltip(
                  message: l10n.scrollSectionRight(widget.section.title),
                  child: IconButton(
                    key: Key(
                      'youtube-feed-scroll-right-${widget.sectionIndex}',
                    ),
                    color: OtohaColors.text,
                    disabledColor: OtohaColors.mutedText.withValues(alpha: 0.4),
                    onPressed: _canScrollRight ? () => _scrollBy(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: contentHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trailingPadding = _trailingPadding(constraints.maxWidth);
                return ListView.separated(
                  key: Key('youtube-feed-section-list-${widget.sectionIndex}'),
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.only(right: trailingPadding),
                  itemCount: usesCompactRows
                      ? columnCount
                      : widget.section.items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 20),
                  itemBuilder: (context, index) {
                    if (usesCompactRows) {
                      final start = index * itemsPerColumn;
                      final end = (start + itemsPerColumn).clamp(
                        0,
                        widget.section.items.length,
                      );
                      final items = widget.section.items.sublist(start, end);
                      return SizedBox(
                        key: Key(
                          'youtube-feed-compact-column-'
                          '${widget.sectionIndex}-$index',
                        ),
                        width: _compactColumnWidth,
                        child: Column(
                          children: <Widget>[
                            for (
                              var rowIndex = 0;
                              rowIndex < items.length;
                              rowIndex++
                            ) ...<Widget>[
                              _FeedCompactRow(
                                item: items[rowIndex],
                                isLoading:
                                    widget.loadingItemId == items[rowIndex].id,
                                onTap: widget.onTap(items[rowIndex]),
                              ),
                              if (rowIndex < items.length - 1)
                                const SizedBox(height: _compactRowGap),
                            ],
                          ],
                        ),
                      );
                    }
                    final item = widget.section.items[index];
                    return YouTubeFeedItemCard(
                      item: item,
                      isLoading: widget.loadingItemId == item.id,
                      onTap: widget.onTap(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedCompactRow extends StatelessWidget {
  const _FeedCompactRow({
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
    final landscapeArtwork = const <String>{
      'video',
      'non_music_track',
    }.contains(item.itemType);
    return WorkspaceResultRow(
      actionKey: Key('youtube-feed-${item.itemType}-${item.id}'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (item.rank case final rank?) ...<Widget>[
            _FeedChartRank(itemId: item.id, rank: rank, trend: item.trend),
            const SizedBox(width: 8),
          ],
          ClipRRect(
            key: Key('youtube-feed-compact-artwork-${item.id}'),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: landscapeArtwork ? 72 : 48,
              height: 48,
              child: ArtworkImage(
                assetPath: item.thumbnailUrl ?? '',
                semanticLabel: l10n.artwork(item.title),
              ),
            ),
          ),
        ],
      ),
      title: item.title,
      subtitle: item.subtitle ?? _typeLabel(item.itemType, l10n),
      trailing: item.durationSeconds > 0
          ? Text(
              _formatFeedDuration(item.durationSeconds),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      isLoading: isLoading,
      loadingOverlayKey: const Key('youtube-feed-compact-loading-overlay'),
      onTap: onTap,
    );
  }
}

class _FeedChartRank extends StatelessWidget {
  const _FeedChartRank({
    required this.itemId,
    required this.rank,
    required this.trend,
  });

  final String itemId;
  final int rank;
  final YouTubeChartTrend? trend;

  static const _downColor = Color(0xFFFF315A);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trendLabel = switch (trend) {
      YouTubeChartTrend.up => l10n.chartTrendUp,
      YouTubeChartTrend.down => l10n.chartTrendDown,
      YouTubeChartTrend.neutral => l10n.chartTrendNeutral,
      null => null,
    };
    final trendIcon = switch (trend) {
      YouTubeChartTrend.up => Icons.arrow_drop_up_rounded,
      YouTubeChartTrend.down => Icons.arrow_drop_down_rounded,
      YouTubeChartTrend.neutral => Icons.circle,
      null => null,
    };
    final trendColor = switch (trend) {
      YouTubeChartTrend.up => OtohaColors.accent,
      YouTubeChartTrend.down => _downColor,
      YouTubeChartTrend.neutral || null => OtohaColors.mutedText,
    };

    return Semantics(
      key: Key('youtube-feed-chart-rank-$itemId'),
      label: <String>[l10n.chartRank(rank), ?trendLabel].join(', '),
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (trendIcon != null) ...<Widget>[
              SizedBox.square(
                key: Key('youtube-feed-chart-trend-slot-$itemId'),
                dimension: 22,
                child: Icon(
                  trendIcon,
                  key: Key('youtube-feed-chart-trend-$itemId'),
                  size: trend == YouTubeChartTrend.neutral ? 7 : 22,
                  color: trendColor,
                ),
              ),
              const SizedBox(width: 2),
            ],
            Text('$rank', style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

class YouTubeFeedItemCard extends StatelessWidget {
  const YouTubeFeedItemCard({
    required this.item,
    required this.isLoading,
    required this.onTap,
    super.key,
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
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (profile)
                        ClipOval(
                          key: Key('youtube-feed-profile-artwork-${item.id}'),
                          child: ArtworkImage(
                            assetPath: item.thumbnailUrl ?? '',
                            semanticLabel: l10n.profileImage(item.title),
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

class YouTubeFeedCollectionDetailView extends StatelessWidget {
  const YouTubeFeedCollectionDetailView({
    required this.detail,
    required this.playerController,
    required this.isSaved,
    required this.isSaving,
    required this.canToggleLibrary,
    required this.onToggleLibrary,
    required this.onBack,
    super.key,
  });

  final YouTubeFeedCollectionDetail detail;
  final PlayerController playerController;
  final bool isSaved;
  final bool isSaving;
  final bool canToggleLibrary;
  final VoidCallback onToggleLibrary;
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
    return KeyedSubtree(
      key: const Key('youtube-feed-collection-detail'),
      child: CustomScrollView(
        key: ObjectKey(detail),
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
                  if (detail.itemType == 'album') ...<Widget>[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      key: const Key('youtube-album-library-toggle'),
                      onPressed: canToggleLibrary ? onToggleLibrary : null,
                      icon: isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isSaved
                                  ? Icons.library_add_check_rounded
                                  : Icons.library_add_rounded,
                            ),
                      label: Text(
                        isSaved ? l10n.removeFromLibrary : l10n.saveToLibrary,
                      ),
                    ),
                  ],
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
                    onTap: () => playerController.playTracks(
                      tracks,
                      initialIndex: index,
                    ),
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class YouTubeFeedBrowseDetailView extends StatelessWidget {
  const YouTubeFeedBrowseDetailView({
    required this.detail,
    required this.playerController,
    required this.youtubeLibraryController,
    required this.loadingItemId,
    required this.reduceMotion,
    required this.onBack,
    required this.onTap,
    super.key,
  });

  final YouTubeFeedBrowseDetail detail;
  final PlayerController playerController;
  final YouTubeLibraryController youtubeLibraryController;
  final String? loadingItemId;
  final bool reduceMotion;
  final VoidCallback onBack;
  final VoidCallback? Function(YouTubeFeedItem item) onTap;

  @override
  Widget build(BuildContext context) {
    final artistItems = _artistItems();
    return KeyedSubtree(
      key: const Key('youtube-feed-browse-detail'),
      child: CustomScrollView(
        key: ObjectKey(detail),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              24,
            ),
            sliver: SliverToBoxAdapter(
              child: _FeedBrowseDetailHeader(
                detail: detail,
                controller: youtubeLibraryController,
                onShuffle: artistItems.isEmpty
                    ? null
                    : () => unawaited(_shuffleArtistTracks(artistItems)),
                onBack: onBack,
              ),
            ),
          ),
          SliverList.builder(
            itemCount: detail.sections.length,
            itemBuilder: (context, index) => YouTubeFeedSectionView(
              section: detail.sections[index],
              sectionIndex: index,
              loadingItemId: loadingItemId,
              reduceMotion: reduceMotion,
              onTap: onTap,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  List<YouTubeFeedItem> _artistItems() {
    if (detail.itemType != 'artist') {
      return const <YouTubeFeedItem>[];
    }
    final seenVideoIds = <String>{};
    final items = <YouTubeFeedItem>[];
    for (final section in detail.sections) {
      for (final item in section.items) {
        final videoId = item.videoId;
        if (!item.isPlayable || videoId == null || !seenVideoIds.add(videoId)) {
          continue;
        }
        items.add(item);
      }
    }
    return List<YouTubeFeedItem>.unmodifiable(items);
  }

  Future<void> _shuffleArtistTracks(List<YouTubeFeedItem> items) async {
    final tracks = <Track>[];
    for (final item in items) {
      final track = await youtubeLibraryController.resolveFeedTrack(item);
      tracks.add(
        _asSimulatedYouTubeTrack(
          track,
          artworkFallback: detail.thumbnailUrl,
          albumFallback: detail.title,
          artistFallback: item.artists.isEmpty
              ? <String>[detail.title]
              : item.artists,
          subtitleFallback: item.subtitle,
          itemTypeFallback: item.itemType,
        ),
      );
    }
    if (tracks.isEmpty) {
      return;
    }
    tracks.shuffle();
    playerController.playTracks(tracks);
  }
}

class _FeedBrowseDetailHeader extends StatelessWidget {
  const _FeedBrowseDetailHeader({
    required this.detail,
    required this.controller,
    required this.onShuffle,
    required this.onBack,
  });

  final YouTubeFeedBrowseDetail detail;
  final YouTubeLibraryController controller;
  final VoidCallback? onShuffle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final thumbnailUrl = detail.thumbnailUrl;
    final isArtist = detail.itemType == 'artist';
    final subscriberCount = isArtist ? detail.subscriberCount : null;
    final audience = isArtist ? detail.audience : null;
    final channelId = isArtist ? detail.channelId : null;
    final subtitle = isArtist ? audience : detail.subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Tooltip(
          message: l10n.back,
          child: IconButton(
            key: const Key('youtube-feed-browse-back'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) ...<Widget>[
          const SizedBox(width: 16),
          ClipOval(
            child: SizedBox.square(
              key: const Key('youtube-feed-browse-artwork'),
              dimension: 88,
              child: ArtworkImage(
                assetPath: thumbnailUrl,
                semanticLabel: l10n.profileImage(detail.title),
              ),
            ),
          ),
        ],
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                detail.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              if (subtitle case final value? when value.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  isArtist ? _artistAudienceText(value, l10n) : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (subscriberCount case final value?
                  when value.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  _subscriberCountText(value, l10n),
                  key: const Key('youtube-artist-subscriber-count'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: OtohaColors.mutedText,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isArtist && onShuffle != null) ...<Widget>[
          const SizedBox(width: 12),
          Tooltip(
            message: l10n.shuffle,
            child: IconButton(
              key: const Key('youtube-artist-shuffle'),
              onPressed: onShuffle,
              icon: const Icon(Icons.shuffle_rounded),
            ),
          ),
        ],
        if (channelId case final value?) ...<Widget>[
          const SizedBox(width: 20),
          _ArtistFollowButton(controller: controller, channelId: value),
        ],
      ],
    );
  }
}

String _artistAudienceText(String value, AppLocalizations l10n) {
  if (RegExp(
    r'monthly|audience|listener|观众|聽眾|听众|每月|月度',
    caseSensitive: false,
  ).hasMatch(value)) {
    return value;
  }
  return l10n.monthlyAudience(value);
}

String _subscriberCountText(String value, AppLocalizations l10n) {
  if (RegExp(
    r'subscriber|follower|订阅|關注|关注',
    caseSensitive: false,
  ).hasMatch(value)) {
    return value;
  }
  return l10n.subscriberCount(value);
}

class _ArtistFollowButton extends StatelessWidget {
  const _ArtistFollowButton({
    required this.controller,
    required this.channelId,
  });

  final YouTubeLibraryController controller;
  final String channelId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isFollowing = controller.isFollowingArtist(channelId);
        final isUpdating = controller.followingArtistId == channelId;
        return SizedBox(
          width: 120,
          child: isFollowing
              ? OutlinedButton.icon(
                  key: const Key('youtube-artist-following'),
                  onPressed: isUpdating || controller.isAccountWriteCoolingDown
                      ? null
                      : () =>
                            unawaited(controller.toggleArtistFollow(channelId)),
                  icon: isUpdating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(l10n.following),
                )
              : FilledButton.icon(
                  key: const Key('youtube-artist-follow'),
                  onPressed: isUpdating || controller.isAccountWriteCoolingDown
                      ? null
                      : () =>
                            unawaited(controller.toggleArtistFollow(channelId)),
                  icon: isUpdating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(l10n.follow),
                ),
        );
      },
    );
  }
}

class YouTubePodcastShowDetailView extends StatelessWidget {
  const YouTubePodcastShowDetailView({
    required this.detail,
    required this.loadingItemId,
    required this.isLoadingMore,
    required this.isSaved,
    required this.isSaving,
    required this.canToggleLibrary,
    required this.onBack,
    required this.onLoadMore,
    required this.onToggleLibrary,
    required this.onTap,
    super.key,
  });

  final YouTubePodcastShowDetail detail;
  final String? loadingItemId;
  final bool isLoadingMore;
  final bool isSaved;
  final bool isSaving;
  final bool canToggleLibrary;
  final VoidCallback onBack;
  final Future<void> Function() onLoadMore;
  final VoidCallback onToggleLibrary;
  final VoidCallback? Function(YouTubeFeedItem item) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 480 &&
            detail.hasMore &&
            !isLoadingMore) {
          unawaited(onLoadMore());
        }
        return false;
      },
      child: CustomScrollView(
        key: const Key('youtube-podcast-show-detail'),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              32,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Tooltip(
                    message: l10n.back,
                    child: IconButton(
                      key: const Key('youtube-podcast-show-back'),
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppMetrics.radius),
                    child: SizedBox.square(
                      dimension: 144,
                      child: ArtworkImage(
                        assetPath: detail.thumbnailUrl ?? '',
                        semanticLabel: l10n.artwork(detail.title),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.podcast,
                            style: const TextStyle(
                              color: OtohaColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            detail.title,
                            key: const Key('youtube-podcast-show-title'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          if (detail.subtitle case final subtitle?
                              when subtitle.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                          if (detail.description case final description?
                              when description.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            key: const Key('youtube-podcast-library-toggle'),
                            onPressed: canToggleLibrary
                                ? onToggleLibrary
                                : null,
                            icon: isSaving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    isSaved
                                        ? Icons.library_add_check_rounded
                                        : Icons.library_add_rounded,
                                  ),
                            label: Text(
                              isSaved
                                  ? l10n.removeFromLibrary
                                  : l10n.saveToLibrary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              0,
              AppMetrics.workspacePadding,
              12,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                l10n.podcastEpisodes,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          if (detail.episodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(l10n.noPodcastEpisodes)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.workspacePadding,
              ),
              sliver: SliverList.builder(
                itemCount: detail.episodes.length,
                itemBuilder: (context, index) {
                  final episode = detail.episodes[index];
                  return _PodcastEpisodeRow(
                    episode: episode,
                    isLoading: loadingItemId == episode.id,
                    onTap: onTap(episode),
                  );
                },
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
    );
  }
}

class _PodcastEpisodeRow extends StatelessWidget {
  const _PodcastEpisodeRow({
    required this.episode,
    required this.isLoading,
    required this.onTap,
  });

  final YouTubeFeedItem episode;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 96,
                    height: 56,
                    child: ArtworkImage(
                      assetPath: episode.thumbnailUrl ?? '',
                      semanticLabel: l10n.artwork(episode.title),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        episode.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (episode.subtitle case final subtitle?
                          when subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (episode.description case final description?
                          when description.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: OtohaColors.mutedText),
                        ),
                      ],
                    ],
                  ),
                ),
                if (episode.durationSeconds > 0) ...<Widget>[
                  const SizedBox(width: 16),
                  Text(
                    _formatFeedDuration(episode.durationSeconds),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (isLoading)
            const Positioned.fill(
              key: Key('youtube-podcast-episode-loading-overlay'),
              child: ColoredBox(
                color: Color(0x99000000),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: Key('youtube-podcast-episode-${episode.id}'),
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
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
  String? subtitleFallback,
  String? itemTypeFallback,
}) {
  final artists = track.artists.isNotEmpty
      ? track.artists
      : artistFallback.isNotEmpty
      ? artistFallback
      : subtitleFallback == null
      ? const <String>[]
      : <String>[subtitleFallback];
  return Track(
    id: 'youtube:${track.videoId}',
    title: track.title,
    artist: artists.isEmpty ? 'YouTube Music' : artists.join(', '),
    album: track.album ?? albumFallback ?? 'YouTube Music',
    artworkAsset: _detailArtwork(track.thumbnailUrl, artworkFallback),
    durationSeconds: track.durationSeconds,
    lyrics: const <String>[],
    youtubeVideoId: track.videoId,
    videoAvailable: track.isVideo || itemTypeFallback == 'video',
  );
}

String _typeLabel(String type, AppLocalizations l10n) {
  return switch (type) {
    'album' => l10n.album,
    'artist' => l10n.artist,
    'category' => l10n.moodAndGenre,
    'episode' => l10n.episode,
    'playlist' => l10n.playlist,
    'podcast' => l10n.podcast,
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

String? _firstFeedArtwork(List<YouTubeFeedSection> sections) {
  for (final section in sections) {
    for (final item in section.items) {
      final artworkUrl = item.thumbnailUrl;
      final uri = artworkUrl == null ? null : Uri.tryParse(artworkUrl);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        return artworkUrl;
      }
    }
  }
  return null;
}

String _formatFeedDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final remainingSeconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:$minutes:$remainingSeconds';
  }
  return '${duration.inMinutes}:$remainingSeconds';
}
