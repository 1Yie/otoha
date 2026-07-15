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
import 'artwork_image.dart';

class SearchPalette extends StatefulWidget {
  const SearchPalette({
    required this.workspaceController,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    required this.reduceMotion,
    super.key,
  });

  final WorkspaceController workspaceController;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;
  final bool reduceMotion;

  @override
  State<SearchPalette> createState() => _SearchPaletteState();
}

class _SearchPaletteState extends State<SearchPalette> {
  final TextEditingController _queryController = TextEditingController();
  Timer? _searchDebounce;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.youtubeLibraryController.addListener(_onLibraryChanged);
  }

  List<_SearchItem> get _items {
    final l10n = AppLocalizations.of(context)!;
    final query = _queryController.text;
    final online = widget.youtubeLibraryController.isSignedIn;
    final tracks = online
        ? widget.youtubeLibraryController.searchQuery == query.trim()
              ? widget.youtubeLibraryController.searchResults
                    .map((item) => _SearchItem.youtube(item, l10n))
                    .toList(growable: false)
              : const <_SearchItem>[]
        : MockCatalog.search(query)
              .map((track) => _SearchItem.track(track, l10n))
              .toList(growable: false);
    final workspaces = WorkspacePage.values
        .where((page) {
          return query.trim().isEmpty ||
              _workspaceLabel(
                page,
                l10n,
              ).toLowerCase().contains(query.trim().toLowerCase());
        })
        .map((page) => _SearchItem.workspace(page, l10n))
        .toList(growable: false);
    return <_SearchItem>[...tracks, ...workspaces];
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    widget.youtubeLibraryController.removeListener(_onLibraryChanged);
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _items;
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.shellController.closeSearch,
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 72),
              child: TweenAnimationBuilder<double>(
                duration: widget.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                tween: Tween<double>(begin: 0.98, end: 1),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(scale: value, child: child),
                  );
                },
                child: SizedBox(
                  width: 640,
                  child: Material(
                    color: OtohaColors.surface,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppMetrics.radius),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: OtohaColors.border),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppMetrics.radius),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: CallbackShortcuts(
                              bindings: <ShortcutActivator, VoidCallback>{
                                const SingleActivator(
                                  LogicalKeyboardKey.arrowDown,
                                ): () =>
                                    _moveSelection(1),
                                const SingleActivator(
                                  LogicalKeyboardKey.arrowUp,
                                ): () =>
                                    _moveSelection(-1),
                                const SingleActivator(
                                  LogicalKeyboardKey.enter,
                                ): () =>
                                    _activate(items),
                                const SingleActivator(
                                  LogicalKeyboardKey.escape,
                                ): widget.shellController.closeSearch,
                              },
                              child: TextField(
                                key: const Key('search-field'),
                                controller: _queryController,
                                autofocus: true,
                                onChanged: _onQueryChanged,
                                decoration: InputDecoration(
                                  hintText:
                                      l10n.searchSongsArtistsAlbumsOrCommands,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          if (widget.youtubeLibraryController.isSearching)
                            const LinearProgressIndicator(),
                          if (widget.youtubeLibraryController.searchErrorMessage
                              case final message?)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Text(
                                localizeYouTubeLibraryError(message, l10n),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 432),
                            child: items.isEmpty
                                ? Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      widget.youtubeLibraryController.isSignedIn
                                          ? l10n.noYouTubeMusicMatches
                                          : l10n.noLocalMatches,
                                      style: TextStyle(
                                        color: OtohaColors.mutedText,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return _SearchResultRow(
                                        key: Key('search-result-${item.id}'),
                                        item: item,
                                        selected: index == _selectedIndex,
                                        onPressed: () =>
                                            unawaited(_activateItem(item)),
                                      );
                                    },
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
        ],
      ),
    );
  }

  void _moveSelection(int offset) {
    final itemCount = _items.length;
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
    if (mounted) {
      setState(() {});
    }
  }

  void _onQueryChanged(String query) {
    setState(() => _selectedIndex = 0);
    _searchDebounce?.cancel();
    if (!widget.youtubeLibraryController.isSignedIn || query.trim().isEmpty) {
      widget.youtubeLibraryController.clearSearchResults();
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(widget.youtubeLibraryController.searchMusic(query)),
    );
  }

  Future<void> _activateItem(_SearchItem item) async {
    if (item.track != null) {
      widget.playerController.selectTrack(item.track!);
    } else if (item.workspace != null) {
      widget.workspaceController.navigateTo(item.workspace!);
    } else if (item.youtubeItem case final youtubeItem?) {
      if (youtubeItem.isPlayable) {
        final track = await widget.youtubeLibraryController.resolveFeedTrack(
          youtubeItem,
        );
        widget.playerController.playTracks(<Track>[
          _asSimulatedTrack(track, youtubeItem),
        ]);
      } else if (youtubeItem.isCollection) {
        final tracks = await widget.youtubeLibraryController.openFeedCollection(
          youtubeItem,
          source: 'home',
        );
        if (tracks.length == 1) {
          widget.playerController.playTracks(<Track>[
            _asSimulatedTrack(tracks.single, youtubeItem),
          ]);
        }
        widget.workspaceController.navigateTo(WorkspacePage.home);
      } else if (youtubeItem.isBrowsable) {
        await widget.youtubeLibraryController.openFeedBrowse(
          youtubeItem,
          source: 'home',
        );
        widget.workspaceController.navigateTo(WorkspacePage.home);
      }
    }
    widget.shellController.closeSearch();
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.item,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final _SearchItem item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: selected ? OtohaColors.surfaceRaised : Colors.transparent,
          child: Row(
            children: <Widget>[
              if (item.artworkPath case final artworkPath?)
                SizedBox.square(
                  dimension: 40,
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
              else
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: OtohaColors.surfaceRaised,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppMetrics.radius),
                    ),
                  ),
                  child: Icon(item.icon, color: OtohaColors.accent),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                item.kind,
                style: const TextStyle(
                  color: OtohaColors.mutedText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
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
    this.track,
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
      track: track,
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
        WorkspacePage.explore => Icons.explore_outlined,
        WorkspacePage.library => Icons.library_music_outlined,
        WorkspacePage.history => Icons.history_rounded,
        WorkspacePage.downloads => Icons.download_outlined,
        WorkspacePage.playlists => Icons.queue_music_outlined,
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
  final Track? track;
  final WorkspacePage? workspace;
  final YouTubeFeedItem? youtubeItem;

  String? get artworkPath => track?.artworkAsset ?? youtubeItem?.thumbnailUrl;
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
    videoAvailable: track.isVideo || source.isVideo,
  );
}

String _workspaceLabel(WorkspacePage page, AppLocalizations l10n) =>
    switch (page) {
      WorkspacePage.home => l10n.home,
      WorkspacePage.explore => l10n.explore,
      WorkspacePage.library => l10n.library,
      WorkspacePage.history => l10n.history,
      WorkspacePage.downloads => l10n.downloads,
      WorkspacePage.playlists => l10n.playlists,
      WorkspacePage.settings => l10n.settings,
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
