import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../models/offline_library.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/offline_library_controller.dart';
import '../widgets/artwork_image.dart';
import '../widgets/youtube_track_list_row.dart';

class OfflineLibraryWorkspace extends StatefulWidget {
  const OfflineLibraryWorkspace({
    required this.controller,
    required this.playerController,
    super.key,
  });

  final OfflineLibraryController controller;
  final PlayerController playerController;

  @override
  State<OfflineLibraryWorkspace> createState() =>
      _OfflineLibraryWorkspaceState();
}

class _OfflineLibraryWorkspaceState extends State<OfflineLibraryWorkspace> {
  final Set<String> _selectedVideoIds = <String>{};
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        widget.playerController,
      ]),
      builder: (context, _) {
        if (!widget.controller.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        final downloads = widget.controller.downloads;
        return CustomScrollView(
          key: const Key('offline-library-scroll'),
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.yourSpace,
                            style: const TextStyle(
                              color: OtohaColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.downloads,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        ],
                      ),
                    ),
                    if (downloads.isNotEmpty)
                      Tooltip(
                        message: _isSelecting
                            ? l10n.exitDownloadSelection
                            : l10n.selectDownloads,
                        child: IconButton(
                          key: const Key('offline-selection-toggle'),
                          onPressed: _toggleSelectionMode,
                          icon: Icon(
                            _isSelecting
                                ? Icons.close_rounded
                                : Icons.checklist_rounded,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isSelecting)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.workspacePadding,
                  16,
                  AppMetrics.workspacePadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      color: OtohaColors.surface,
                      border: Border.symmetric(
                        horizontal: BorderSide(color: OtohaColors.border),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Tooltip(
                          message: l10n.selectAllDownloads,
                          child: Checkbox(
                            key: const Key('offline-select-all'),
                            value:
                                downloads.isNotEmpty &&
                                _selectedVideoIds.length == downloads.length,
                            onChanged: (_) => _toggleSelectAll(downloads),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.selectedDownloadsCount(_selectedVideoIds.length),
                          key: const Key('offline-selected-count'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        if (widget.controller.playlists.isNotEmpty)
                          Tooltip(
                            message: l10n.addSelectedToPlaylist,
                            child: IconButton(
                              key: const Key('offline-batch-add'),
                              onPressed: _selectedVideoIds.isEmpty
                                  ? null
                                  : _addSelectedToPlaylist,
                              icon: const Icon(Icons.playlist_add_rounded),
                            ),
                          ),
                        Tooltip(
                          message: l10n.deleteSelectedDownloads,
                          child: IconButton(
                            key: const Key('offline-batch-delete'),
                            onPressed: _selectedVideoIds.isEmpty
                                ? null
                                : _confirmRemoveSelected,
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            if (downloads.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    l10n.noDownloads,
                    key: const Key('offline-library-empty'),
                    style: const TextStyle(color: OtohaColors.mutedText),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.workspacePadding,
                  0,
                  AppMetrics.workspacePadding,
                  40,
                ),
                sliver: SliverList.builder(
                  itemCount: downloads.length * 2 - 1,
                  itemBuilder: (context, index) {
                    if (index.isOdd) {
                      return const SizedBox(height: 2);
                    }
                    final trackIndex = index ~/ 2;
                    final download = downloads[trackIndex];
                    return YouTubeTrackListRow(
                      rowKey: Key('offline-track-${download.videoId}'),
                      index: trackIndex + 1,
                      track: _asListTrack(download),
                      artworkFallback: download.artworkAsset,
                      isSelected: _isSelecting
                          ? _selectedVideoIds.contains(download.videoId)
                          : widget
                                    .playerController
                                    .currentTrack
                                    ?.localFilePath ==
                                download.filePath,
                      onTap: () => _isSelecting
                          ? _toggleSelection(download)
                          : _play(download),
                      trailing: _isSelecting
                          ? Checkbox(
                              key: Key('offline-select-${download.videoId}'),
                              value: _selectedVideoIds.contains(
                                download.videoId,
                              ),
                              onChanged: (_) => _toggleSelection(download),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (widget.controller.playlists.isNotEmpty)
                                  Tooltip(
                                    message: l10n.addToPlaylist,
                                    child: IconButton(
                                      key: Key(
                                        'offline-add-${download.videoId}',
                                      ),
                                      onPressed: () => _addToPlaylist(download),
                                      icon: const Icon(
                                        Icons.playlist_add_rounded,
                                      ),
                                    ),
                                  ),
                                Tooltip(
                                  message: l10n.deleteDownload,
                                  child: IconButton(
                                    key: Key(
                                      'offline-delete-${download.videoId}',
                                    ),
                                    onPressed: () => _confirmRemove(download),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelecting = !_isSelecting;
      if (!_isSelecting) {
        _selectedVideoIds.clear();
      }
    });
  }

  void _toggleSelection(DownloadedTrack track) {
    setState(() {
      if (!_selectedVideoIds.add(track.videoId)) {
        _selectedVideoIds.remove(track.videoId);
      }
    });
  }

  void _toggleSelectAll(List<DownloadedTrack> downloads) {
    setState(() {
      if (_selectedVideoIds.length == downloads.length) {
        _selectedVideoIds.clear();
      } else {
        _selectedVideoIds
          ..clear()
          ..addAll(downloads.map((track) => track.videoId));
      }
    });
  }

  List<DownloadedTrack> get _selectedDownloads => widget.controller.downloads
      .where((track) => _selectedVideoIds.contains(track.videoId))
      .toList(growable: false);

  void _clearSelection() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isSelecting = false;
      _selectedVideoIds.clear();
    });
  }

  YouTubeTrack _asListTrack(DownloadedTrack track) => YouTubeTrack(
    videoId: track.videoId,
    title: track.title,
    artists: <String>[track.artist],
    album: track.album,
    durationSeconds: track.durationSeconds,
  );

  void _play(DownloadedTrack track) {
    final downloads = widget.controller.downloads;
    final tracks = downloads
        .map((download) => download.toTrack())
        .toList(growable: false);
    widget.playerController.playTracks(
      tracks,
      initialIndex: downloads.indexWhere(
        (download) => download.videoId == track.videoId,
      ),
    );
  }

  Future<void> _confirmRemove(DownloadedTrack track) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-download-confirmation'),
        title: Text(l10n.deleteDownload),
        content: Text(l10n.deleteDownloadConfirmation(track.title)),
        actions: <Widget>[
          TextButton(
            key: const Key('cancel-delete-download'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-delete-download'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteDownload),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await widget.controller.remove(track);
    }
  }

  Future<void> _confirmRemoveSelected() async {
    final selected = _selectedDownloads;
    if (selected.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-downloads-confirmation'),
        title: Text(l10n.deleteSelectedDownloads),
        content: Text(
          l10n.deleteSelectedDownloadsConfirmation(selected.length),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('cancel-delete-downloads'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-delete-downloads'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteSelectedDownloads),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await widget.controller.removeMany(selected);
      _clearSelection();
    }
  }

  Future<void> _addToPlaylist(DownloadedTrack track) async {
    final playlist = await _choosePlaylist();
    if (playlist != null) {
      await widget.controller.addToPlaylist(playlist: playlist, track: track);
    }
  }

  Future<void> _addSelectedToPlaylist() async {
    final selected = _selectedDownloads;
    if (selected.isEmpty) {
      return;
    }
    final playlist = await _choosePlaylist();
    if (playlist != null) {
      await widget.controller.addManyToPlaylist(
        playlist: playlist,
        tracks: selected,
      );
      _clearSelection();
    }
  }

  Future<OfflinePlaylist?> _choosePlaylist() {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<OfflinePlaylist>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addToPlaylist),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.controller.playlists.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final playlist = widget.controller.playlists[index];
                return ListTile(
                  key: Key('offline-playlist-option-${playlist.id}'),
                  onTap: () => Navigator.pop(context, playlist),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(AppMetrics.radius),
                    child: SizedBox.square(
                      key: Key(
                        'offline-playlist-option-artwork-${playlist.id}',
                      ),
                      dimension: 52,
                      child: ArtworkImage(
                        assetPath: _playlistArtwork(playlist),
                        semanticLabel: l10n.artwork(playlist.name),
                      ),
                    ),
                  ),
                  title: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    l10n.tracksCount(playlist.trackVideoIds.length),
                  ),
                );
              },
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  String _playlistArtwork(OfflinePlaylist playlist) {
    if (playlist.trackVideoIds.isEmpty) {
      return '';
    }
    final videoId =
        playlist.artworkVideoId != null &&
            playlist.trackVideoIds.contains(playlist.artworkVideoId)
        ? playlist.artworkVideoId!
        : playlist.trackVideoIds.first;
    final matchingTracks = widget.controller.downloads
        .where((track) => track.videoId == videoId)
        .toList(growable: false);
    return matchingTracks.isEmpty ? '' : matchingTracks.first.artworkAsset;
  }
}
