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
import '../widgets/youtube_track_list_row.dart';

enum YouTubeFeedKind { home, explore }

const String _forYouFilterId = '__for_you__';

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
    final filterOptions = isHome
        ? <_FeedFilterOption>[
            if (controller.homeFilters.isNotEmpty)
              _FeedFilterOption(id: _forYouFilterId, label: l10n.forYou),
            for (final filter in controller.homeFilters)
              _FeedFilterOption(id: filter, label: filter),
          ]
        : <_FeedFilterOption>[
            if (controller.exploreCategories.isNotEmpty)
              _FeedFilterOption(id: _forYouFilterId, label: l10n.forYou),
            for (final category in controller.exploreCategories)
              _FeedFilterOption(
                id: category.browseIdentity,
                label: category.title,
              ),
          ];
    final selectedFilterId = isHome
        ? controller.selectedHomeFilter ??
              (filterOptions.isEmpty ? null : _forYouFilterId)
        : controller.selectedExploreCategoryId ??
              (filterOptions.isEmpty ? null : _forYouFilterId);

    void selectFilter(String id) {
      if (isHome) {
        unawaited(
          id == _forYouFilterId
              ? controller.loadHome(forceRefresh: true)
              : controller.selectHomeFilter(id),
        );
        return;
      }
      if (id == _forYouFilterId) {
        unawaited(controller.loadExplore(forceRefresh: true));
        return;
      }
      final category = controller.exploreCategories.firstWhere(
        (item) => item.browseIdentity == id,
      );
      unawaited(controller.openFeedBrowse(category, source: kind.name));
    }

    return _FeedBackdrop(
      key: Key('youtube-${kind.name}-backdrop'),
      identity: '${kind.name}:${selectedFilterId ?? 'default'}',
      artworkUrl: _firstFeedArtwork(sections),
      reduceMotion: shellController.reduceMotion,
      child: NotificationListener<ScrollNotification>(
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
            if (filterOptions.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.workspacePadding,
                  24,
                  AppMetrics.workspacePadding,
                  16,
                ),
                sliver: SliverToBoxAdapter(
                  child: _FeedFilterTabs(
                    key: Key('youtube-${kind.name}-tabs'),
                    kind: kind,
                    options: filterOptions,
                    selectedId: selectedFilterId,
                    reduceMotion: shellController.reduceMotion,
                    onSelected: selectFilter,
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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

class _FeedFilterOption {
  const _FeedFilterOption({required this.id, required this.label});

  final String id;
  final String label;
}

class _FeedFilterTabs extends StatefulWidget {
  const _FeedFilterTabs({
    required this.kind,
    required this.options,
    required this.selectedId,
    required this.reduceMotion,
    required this.onSelected,
    super.key,
  });

  final YouTubeFeedKind kind;
  final List<_FeedFilterOption> options;
  final String? selectedId;
  final bool reduceMotion;
  final ValueChanged<String> onSelected;

  @override
  State<_FeedFilterTabs> createState() => _FeedFilterTabsState();
}

class _FeedFilterTabsState extends State<_FeedFilterTabs> {
  late final ScrollController _scrollController;
  final Map<String, GlobalKey> _optionKeys = <String, GlobalKey>{};
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_updateScrollActions);
    _afterLayout();
  }

  @override
  void didUpdateWidget(covariant _FeedFilterTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _afterLayout(
      ensureSelectionVisible: oldWidget.selectedId != widget.selectedId,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollActions);
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
    if (widget.reduceMotion) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _afterLayout({bool ensureSelectionVisible = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateScrollActions();
      if (!ensureSelectionVisible || widget.selectedId == null) {
        return;
      }
      final selectedContext = _optionKeys[widget.selectedId]?.currentContext;
      if (selectedContext != null) {
        Scrollable.ensureVisible(
          selectedContext,
          alignment: 0.5,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _updateScrollActions() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final canScrollLeft = position.pixels > 0.5;
    final canScrollRight = position.pixels < position.maxScrollExtent - 0.5;
    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }
    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 44,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _afterLayout();
          return false;
        },
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  colors: <Color>[
                    _canScrollLeft ? Colors.transparent : Colors.white,
                    Colors.white,
                    Colors.white,
                    _canScrollRight ? Colors.transparent : Colors.white,
                  ],
                  stops: const <double>[0, 0.06, 0.86, 1],
                ).createShader(bounds),
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(2, 0, 80, 0),
                  itemCount: widget.options.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final option = widget.options[index];
                    return _FeedFilterTab(
                      key: _optionKeys.putIfAbsent(
                        option.id,
                        () => GlobalKey(),
                      ),
                      tabKey: Key(
                        'youtube-${widget.kind.name}-tab-${option.id}',
                      ),
                      label: option.label,
                      selected: widget.selectedId == option.id,
                      reduceMotion: widget.reduceMotion,
                      onTap: widget.selectedId == option.id
                          ? null
                          : () => widget.onSelected(option.id),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _FilterScrollButton(
                    key: Key('youtube-${widget.kind.name}-tabs-left'),
                    tooltip: l10n.scrollFeedFiltersLeft,
                    enabled: _canScrollLeft,
                    icon: Icons.chevron_left_rounded,
                    onPressed: () => _scrollBy(-1),
                  ),
                  _FilterScrollButton(
                    key: Key('youtube-${widget.kind.name}-tabs-right'),
                    tooltip: l10n.scrollFeedFiltersRight,
                    enabled: _canScrollRight,
                    icon: Icons.chevron_right_rounded,
                    onPressed: () => _scrollBy(1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterScrollButton extends StatelessWidget {
  const _FilterScrollButton({
    required this.tooltip,
    required this.enabled,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final bool enabled;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        iconSize: 22,
        color: OtohaColors.text,
        disabledColor: OtohaColors.mutedText.withValues(alpha: 0.4),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
      ),
    );
  }
}

class _FeedFilterTab extends StatelessWidget {
  const _FeedFilterTab({
    required this.tabKey,
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
    super.key,
  });

  final Key tabKey;
  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const tabRadius = BorderRadius.all(Radius.circular(22));
    return ClipRRect(
      borderRadius: tabRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AnimatedContainer(
          key: tabKey,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.linear,
          constraints: const BoxConstraints(minWidth: 64),
          decoration: BoxDecoration(
            color: selected
                ? OtohaColors.text.withValues(alpha: 0.92)
                : OtohaColors.surfaceRaised.withValues(alpha: 0.62),
            borderRadius: tabRadius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.linear,
                    style: TextStyle(
                      color: selected ? OtohaColors.canvas : OtohaColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    child: Text(label, maxLines: 1),
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

class _FeedSection extends StatefulWidget {
  const _FeedSection({
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
  State<_FeedSection> createState() => _FeedSectionState();
}

class _FeedSectionState extends State<_FeedSection> {
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
    _scrollController = ScrollController()..addListener(_updateScrollActions);
    _updateScrollActionsAfterLayout();
  }

  @override
  void didUpdateWidget(covariant _FeedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.items.length != widget.section.items.length ||
        oldWidget.section.itemsPerColumn != widget.section.itemsPerColumn) {
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
    final canScrollLeft = position.pixels > 0.5;
    final canScrollRight = position.pixels < position.maxScrollExtent - 0.5;
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
    final itemExtent = widget.section.itemsPerColumn > 1
        ? _compactColumnExtent
        : _cardItemExtent;
    final visibleItemCount = (position.viewportDimension / itemExtent).floor();
    final pageExtent =
        (visibleItemCount < 1 ? 1 : visibleItemCount) * itemExtent;
    final targetPage = direction > 0
        ? ((position.pixels + 0.5) / pageExtent).floor() + 1
        : ((position.pixels - 0.5) / pageExtent).ceil() - 1;
    final target = (targetPage * pageExtent)
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
    final itemsPerColumn = widget.section.itemsPerColumn.clamp(1, 6);
    final usesCompactRows = itemsPerColumn > 1;
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
            child: ListView.separated(
              key: Key('youtube-feed-section-list-${widget.sectionIndex}'),
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(
                right: AppMetrics.workspacePadding,
              ),
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
    return SizedBox(
      height: _FeedSectionState._compactRowHeight,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('youtube-feed-${item.itemType}-${item.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
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
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle ?? _typeLabel(item.itemType, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isLoading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (item.durationSeconds > 0)
                  Text(
                    _formatFeedDuration(item.durationSeconds),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
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
