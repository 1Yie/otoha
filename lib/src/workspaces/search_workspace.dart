import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../app/youtube_library_error_localizations.dart';
import '../data/mock_catalog.dart';
import '../models/catalog.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/artwork_image.dart';
import '../widgets/workspace_filter_tabs.dart';
import '../widgets/workspace_result_row.dart';
import 'youtube_feed_workspace.dart';

class SearchWorkspace extends StatefulWidget {
  const SearchWorkspace({
    required this.workspaceController,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    super.key,
  });

  final WorkspaceController workspaceController;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  State<SearchWorkspace> createState() => _SearchWorkspaceState();
}

class _SearchWorkspaceState extends State<SearchWorkspace> {
  late final TextEditingController _queryController;
  final FocusNode _queryFocusNode = FocusNode();
  Timer? _searchDebounce;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: widget.youtubeLibraryController.searchQuery,
    );
    widget.youtubeLibraryController.addListener(_onLibraryChanged);
  }

  @override
  void didUpdateWidget(covariant SearchWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeLibraryController != widget.youtubeLibraryController) {
      oldWidget.youtubeLibraryController.removeListener(_onLibraryChanged);
      widget.youtubeLibraryController.addListener(_onLibraryChanged);
      _queryController.text = widget.youtubeLibraryController.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    widget.youtubeLibraryController.removeListener(_onLibraryChanged);
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = widget.youtubeLibraryController;
    final collection = controller.selectedFeedCollection;
    if (collection?.source == 'search') {
      return YouTubeFeedCollectionDetailView(
        detail: collection!,
        playerController: widget.playerController,
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
    if (podcast?.source == 'search') {
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
    if (browse?.source == 'search') {
      return YouTubeFeedBrowseDetailView(
        detail: browse!,
        playerController: widget.playerController,
        youtubeLibraryController: controller,
        loadingItemId: controller.loadingFeedItemId,
        reduceMotion: widget.shellController.reduceMotion,
        onBack: controller.closeFeedDetail,
        onTap: _actionFor,
      );
    }
    final items = _items(l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 720
            ? 24.0
            : AppMetrics.workspacePadding;
        return CustomScrollView(
          key: const Key('search-workspace'),
          slivers: <Widget>[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppMetrics.workspacePadding,
                horizontalPadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    KeyedSubtree(
                      key: const Key('search-filter-scroll'),
                      child: WorkspaceFilterTabs<YouTubeMusicSearchFilter>(
                        key: const Key('search-filters'),
                        options:
                            <
                              WorkspaceFilterTabOption<YouTubeMusicSearchFilter>
                            >[
                              for (final filter
                                  in YouTubeMusicSearchFilter.values)
                                WorkspaceFilterTabOption<
                                  YouTubeMusicSearchFilter
                                >(
                                  value: filter,
                                  label: _filterLabel(filter, l10n),
                                  tabKey: Key('search-filter-${filter.name}'),
                                ),
                            ],
                        selectedValue:
                            widget.youtubeLibraryController.searchFilter,
                        reduceMotion: widget.shellController.reduceMotion,
                        onSelected: _selectFilter,
                        scrollLeftKey: const Key('search-filters-left'),
                        scrollRightKey: const Key('search-filters-right'),
                        scrollLeftTooltip: l10n.scrollFeedFiltersLeft,
                        scrollRightTooltip: l10n.scrollFeedFiltersRight,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      l10n.search,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 16),
                    CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(
                          LogicalKeyboardKey.arrowDown,
                        ): () =>
                            _moveSelection(1),
                        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                            _moveSelection(-1),
                        const SingleActivator(LogicalKeyboardKey.enter): () =>
                            _activate(items),
                      },
                      child: TextField(
                        key: const Key('search-field'),
                        controller: _queryController,
                        focusNode: _queryFocusNode,
                        autofocus: true,
                        onChanged: _onQueryChanged,
                        decoration: InputDecoration(
                          hintText: l10n.searchSongsArtistsAlbumsOrCommands,
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _queryController.text.isEmpty
                              ? null
                              : Tooltip(
                                  message: l10n.close,
                                  child: IconButton(
                                    key: const Key('search-clear'),
                                    onPressed: _clearQuery,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (widget.youtubeLibraryController.searchErrorMessage
                        case final message?)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          localizeYouTubeLibraryError(message, l10n),
                          key: const Key('search-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (widget.youtubeLibraryController.isSearching) ...<Widget>[
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(key: Key('search-loading-rail')),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ..._buildResultSlivers(items, l10n, horizontalPadding),
          ],
        );
      },
    );
  }

  List<Widget> _buildResultSlivers(
    List<_SearchItem> items,
    AppLocalizations l10n,
    double horizontalPadding,
  ) {
    if (items.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            key: const Key('search-empty'),
            child: Text(
              widget.youtubeLibraryController.isSignedIn
                  ? l10n.noYouTubeMusicMatches
                  : l10n.noLocalMatches,
              style: const TextStyle(color: OtohaColors.mutedText),
            ),
          ),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          8,
        ),
        sliver: SliverToBoxAdapter(
          child: Text(
            _filterLabel(
              widget.youtubeLibraryController.searchFilter,
              l10n,
            ).toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: OtohaColors.mutedText),
          ),
        ),
      ),
      SliverPadding(
        key: const Key('search-results'),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          24,
        ),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final columnCount = constraints.crossAxisExtent >= 760 ? 2 : 1;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                mainAxisExtent: 64,
                mainAxisSpacing: 8,
                crossAxisSpacing: 24,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = items[index];
                final loadingItemId =
                    widget.youtubeLibraryController.loadingFeedItemId;
                return _SearchResultRow(
                  key: Key('search-result-${item.id}'),
                  item: item,
                  selected: index == _selectedIndex,
                  isLoading:
                      loadingItemId != null &&
                      item.youtubeItem?.id == loadingItemId,
                  onPressed: () => unawaited(_activateItem(item)),
                );
              }, childCount: items.length),
            );
          },
        ),
      ),
    ];
  }

  List<_SearchItem> _items(AppLocalizations l10n) {
    final query = _queryController.text.trim();
    final controller = widget.youtubeLibraryController;
    final filter = controller.searchFilter;
    final musicItems = controller.isSignedIn
        ? controller.searchQuery == query && controller.searchFilter == filter
              ? controller.searchResults
                    .map((item) => _SearchItem.youtube(item, l10n))
                    .toList(growable: false)
              : const <_SearchItem>[]
        : _localItems(query, filter, l10n);
    if (filter != YouTubeMusicSearchFilter.all) {
      return musicItems;
    }
    final normalizedQuery = query.toLowerCase();
    final workspaces = WorkspacePage.values
        .where(
          (page) =>
              page != WorkspacePage.search &&
              (normalizedQuery.isEmpty ||
                  _workspaceLabel(
                    page,
                    l10n,
                  ).toLowerCase().contains(normalizedQuery)),
        )
        .map((page) => _SearchItem.workspace(page, l10n))
        .toList(growable: false);
    return <_SearchItem>[...musicItems, ...workspaces];
  }

  List<_SearchItem> _localItems(
    String query,
    YouTubeMusicSearchFilter filter,
    AppLocalizations l10n,
  ) {
    if (filter == YouTubeMusicSearchFilter.all ||
        filter == YouTubeMusicSearchFilter.song) {
      return MockCatalog.search(
        query,
      ).map((track) => _SearchItem.track(track, l10n)).toList(growable: false);
    }
    final normalizedQuery = query.toLowerCase();
    if (filter == YouTubeMusicSearchFilter.album) {
      return _groupTracks((track) => track.album).entries
          .where((entry) {
            final artists = entry.value.map((track) => track.artist).join(' ');
            return normalizedQuery.isEmpty ||
                '${entry.key} $artists'.toLowerCase().contains(normalizedQuery);
          })
          .map(
            (entry) => _SearchItem.localGroup(
              id: 'local-album-${_slug(entry.key)}',
              title: entry.key,
              subtitle: entry.value
                  .map((track) => track.artist)
                  .toSet()
                  .join(', '),
              kind: l10n.album,
              icon: Icons.album_rounded,
              tracks: entry.value,
            ),
          )
          .toList(growable: false);
    }
    if (filter == YouTubeMusicSearchFilter.artist) {
      return _groupTracks((track) => track.artist).entries
          .where((entry) {
            final albums = entry.value.map((track) => track.album).join(' ');
            return normalizedQuery.isEmpty ||
                '${entry.key} $albums'.toLowerCase().contains(normalizedQuery);
          })
          .map(
            (entry) => _SearchItem.localGroup(
              id: 'local-artist-${_slug(entry.key)}',
              title: entry.key,
              subtitle: l10n.tracksCount(entry.value.length),
              kind: l10n.artist,
              icon: Icons.person_rounded,
              tracks: entry.value,
            ),
          )
          .toList(growable: false);
    }
    return const <_SearchItem>[];
  }

  Map<String, List<Track>> _groupTracks(String Function(Track track) keyFor) {
    final groups = <String, List<Track>>{};
    for (final track in MockCatalog.tracks) {
      groups.putIfAbsent(keyFor(track), () => <Track>[]).add(track);
    }
    return groups;
  }

  void _moveSelection(int offset) {
    final itemCount = _items(AppLocalizations.of(context)!).length;
    if (itemCount == 0) {
      return;
    }
    setState(() {
      _selectedIndex = (_selectedIndex + offset) % itemCount;
      if (_selectedIndex < 0) {
        _selectedIndex += itemCount;
      }
    });
  }

  void _activate(List<_SearchItem> items) {
    if (items.isEmpty) {
      return;
    }
    unawaited(_activateItem(items[_selectedIndex.clamp(0, items.length - 1)]));
  }

  void _onLibraryChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      final itemCount = _items(AppLocalizations.of(context)!).length;
      _selectedIndex = itemCount == 0
          ? 0
          : _selectedIndex.clamp(0, itemCount - 1);
    });
  }

  void _onQueryChanged(String query) {
    setState(() => _selectedIndex = 0);
    _searchDebounce?.cancel();
    final controller = widget.youtubeLibraryController;
    if (!controller.isSignedIn || query.trim().isEmpty) {
      unawaited(controller.searchMusic(query, filter: controller.searchFilter));
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(
        controller.searchMusic(query, filter: controller.searchFilter),
      ),
    );
  }

  void _selectFilter(YouTubeMusicSearchFilter filter) {
    _searchDebounce?.cancel();
    setState(() => _selectedIndex = 0);
    unawaited(
      widget.youtubeLibraryController.searchMusic(
        _queryController.text,
        filter: filter,
      ),
    );
  }

  void _clearQuery() {
    _searchDebounce?.cancel();
    _queryController.clear();
    widget.youtubeLibraryController.clearSearchResults();
    setState(() => _selectedIndex = 0);
    _queryFocusNode.requestFocus();
  }

  Future<void> _activateItem(_SearchItem item) async {
    if (item.localTracks != null) {
      widget.playerController.playTracks(item.localTracks!);
      return;
    }
    if (item.workspace != null) {
      widget.workspaceController.navigateTo(item.workspace!);
      return;
    }
    if (item.youtubeItem case final youtubeItem?) {
      final action = _actionFor(youtubeItem);
      if (action != null) {
        action();
      }
    }
  }

  VoidCallback? _actionFor(YouTubeFeedItem item) {
    if (item.isCollection) {
      return () => unawaited(_openCollection(item));
    }
    if (item.isBrowsable) {
      return () => unawaited(
        widget.youtubeLibraryController.openFeedBrowse(item, source: 'search'),
      );
    }
    if (item.isPlayable) {
      return () => unawaited(_playFeedItem(item));
    }
    return null;
  }

  Future<void> _openCollection(YouTubeFeedItem item) async {
    final tracks = await widget.youtubeLibraryController.openFeedCollection(
      item,
      source: 'search',
    );
    if (tracks.length == 1 && item.itemType != 'album') {
      widget.playerController.playTracks(<Track>[
        _asSimulatedTrack(tracks.first, item),
      ]);
    }
  }

  Future<void> _playFeedItem(YouTubeFeedItem item) async {
    final track = await widget.youtubeLibraryController.resolveFeedTrack(item);
    widget.playerController.playTracks(<Track>[_asSimulatedTrack(track, item)]);
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.item,
    required this.selected,
    required this.isLoading,
    required this.onPressed,
    super.key,
  });

  final _SearchItem item;
  final bool selected;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final artworkPath = item.artworkPath;
    return WorkspaceResultRow(
      actionKey: Key('search-result-action-${item.id}'),
      leading: artworkPath != null
          ? SizedBox.square(
              dimension: 48,
              child: item.isProfile
                  ? ClipOval(
                      child: ArtworkImage(
                        assetPath: artworkPath,
                        semanticLabel: l10n.profileImage(item.title),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppMetrics.radius),
                      ),
                      child: ArtworkImage(
                        assetPath: artworkPath,
                        semanticLabel: l10n.artwork(item.title),
                      ),
                    ),
            )
          : Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: OtohaColors.surfaceRaised,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppMetrics.radius),
                ),
              ),
              child: Icon(item.icon, color: OtohaColors.accent),
            ),
      title: item.title,
      subtitle: item.subtitle,
      trailing: SizedBox(
        width: 84,
        child: Text(
          item.kind,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: const TextStyle(color: OtohaColors.mutedText, fontSize: 12),
        ),
      ),
      selected: selected,
      isLoading: isLoading,
      loadingOverlayKey: Key('search-result-loading-overlay-${item.id}'),
      onTap: onPressed,
    );
  }
}

class _SearchItem {
  const _SearchItem._({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.icon,
    this.localTracks,
    this.workspace,
    this.youtubeItem,
  });

  factory _SearchItem.track(Track track, AppLocalizations l10n) {
    return _SearchItem._(
      id: 'track-${track.id}',
      title: track.title,
      subtitle: '${track.artist} - ${track.album}',
      kind: l10n.song,
      icon: Icons.music_note_rounded,
      localTracks: <Track>[track],
    );
  }

  factory _SearchItem.localGroup({
    required String id,
    required String title,
    required String subtitle,
    required String kind,
    required IconData icon,
    required List<Track> tracks,
  }) {
    return _SearchItem._(
      id: id,
      title: title,
      subtitle: subtitle,
      kind: kind,
      icon: icon,
      localTracks: List<Track>.unmodifiable(tracks),
    );
  }

  factory _SearchItem.workspace(WorkspacePage page, AppLocalizations l10n) {
    return _SearchItem._(
      id: 'page-${page.name}',
      title: _workspaceLabel(page, l10n),
      subtitle: l10n.openWorkspace,
      kind: l10n.command,
      icon: switch (page) {
        WorkspacePage.home => Icons.home_outlined,
        WorkspacePage.search => Icons.search_rounded,
        WorkspacePage.explore => Icons.explore_outlined,
        WorkspacePage.library => Icons.library_music_outlined,
        WorkspacePage.history => Icons.history_rounded,
        WorkspacePage.downloads => Icons.download_outlined,
        WorkspacePage.playlists => Icons.queue_music_outlined,
        WorkspacePage.channel => Icons.account_circle_outlined,
        WorkspacePage.settings => Icons.settings_outlined,
      },
      workspace: page,
    );
  }

  factory _SearchItem.youtube(YouTubeFeedItem item, AppLocalizations l10n) {
    return _SearchItem._(
      id: 'youtube-${item.itemType}-${item.id}',
      title: item.title,
      subtitle:
          item.subtitle ??
          (item.artists.isEmpty ? l10n.youtubeMusic : item.artists.join(', ')),
      kind: _youtubeKind(item.itemType, l10n),
      icon: _youtubeIcon(item.itemType),
      youtubeItem: item,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final String kind;
  final IconData icon;
  final List<Track>? localTracks;
  final WorkspacePage? workspace;
  final YouTubeFeedItem? youtubeItem;

  String? get artworkPath =>
      localTracks?.first.artworkAsset ?? youtubeItem?.thumbnailUrl;
  bool get isProfile => youtubeItem?.isProfile ?? false;
}

Track _asSimulatedTrack(YouTubeTrack track, YouTubeFeedItem source) {
  final artists = track.artists.isNotEmpty ? track.artists : source.artists;
  return Track(
    id: track.videoId,
    title: track.title,
    artist: artists.isEmpty ? 'YouTube Music' : artists.join(', '),
    album: track.album ?? source.album ?? source.title,
    artworkAsset: track.thumbnailUrl ?? source.thumbnailUrl ?? '',
    durationSeconds: track.durationSeconds,
    lyrics: const <String>[],
    youtubeVideoId: track.videoId,
    isVideo: track.isVideo || source.isVideo,
    videoAvailable: track.isVideo || source.isVideo,
  );
}

String _workspaceLabel(WorkspacePage page, AppLocalizations l10n) =>
    switch (page) {
      WorkspacePage.home => l10n.home,
      WorkspacePage.search => l10n.search,
      WorkspacePage.explore => l10n.explore,
      WorkspacePage.library => l10n.library,
      WorkspacePage.history => l10n.history,
      WorkspacePage.downloads => l10n.downloads,
      WorkspacePage.playlists => l10n.playlists,
      WorkspacePage.channel => l10n.myChannel,
      WorkspacePage.settings => l10n.settings,
    };

String _filterLabel(YouTubeMusicSearchFilter filter, AppLocalizations l10n) =>
    switch (filter) {
      YouTubeMusicSearchFilter.all => l10n.all,
      YouTubeMusicSearchFilter.song => l10n.song,
      YouTubeMusicSearchFilter.album => l10n.album,
      YouTubeMusicSearchFilter.artist => l10n.artist,
      YouTubeMusicSearchFilter.playlist => l10n.playlists,
      YouTubeMusicSearchFilter.video => l10n.musicVideo,
    };

String _youtubeKind(String itemType, AppLocalizations l10n) =>
    switch (itemType) {
      'album' => l10n.album,
      'artist' || 'channel' || 'subscriber' => l10n.artist,
      'playlist' => l10n.playlist,
      'podcast' => l10n.podcast,
      'category' => l10n.genre,
      'episode' || 'non_music_track' => l10n.episode,
      'video' => l10n.musicVideo,
      _ => l10n.song,
    };

IconData _youtubeIcon(String itemType) => switch (itemType) {
  'album' => Icons.album_rounded,
  'artist' || 'channel' || 'subscriber' => Icons.person_rounded,
  'playlist' => Icons.queue_music_rounded,
  'podcast' => Icons.podcasts_rounded,
  'category' => Icons.tune_rounded,
  'episode' || 'non_music_track' => Icons.podcasts_rounded,
  'video' => Icons.videocam_rounded,
  _ => Icons.music_note_rounded,
};

String _slug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');
