import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../models/offline_library.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/offline_library_controller.dart';
import '../widgets/artwork_image.dart';
import '../widgets/playlist_card.dart';
import '../widgets/youtube_track_list_row.dart';

class OfflinePlaylistsWorkspace extends StatefulWidget {
  const OfflinePlaylistsWorkspace({
    required this.controller,
    required this.playerController,
    super.key,
  });

  final OfflineLibraryController controller;
  final PlayerController playerController;

  @override
  State<OfflinePlaylistsWorkspace> createState() =>
      _OfflinePlaylistsWorkspaceState();
}

class _OfflinePlaylistsWorkspaceState extends State<OfflinePlaylistsWorkspace> {
  String? _selectedPlaylistId;

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
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        widget.playerController,
      ]),
      builder: (context, _) {
        if (!widget.controller.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        final matchingPlaylists = _selectedPlaylistId == null
            ? const <OfflinePlaylist>[]
            : widget.controller.playlists
                  .where((item) => item.id == _selectedPlaylistId)
                  .toList(growable: false);
        final playlist = matchingPlaylists.isEmpty
            ? null
            : matchingPlaylists.first;
        if (_selectedPlaylistId != null && playlist == null) {
          _selectedPlaylistId = null;
        }
        return playlist == null ? _playlistList() : _playlistDetail(playlist);
      },
    );
  }

  Widget _playlistList() {
    final l10n = AppLocalizations.of(context)!;
    final playlists = widget.controller.playlists;
    return CustomScrollView(
      key: const Key('offline-playlists-scroll'),
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
                        l10n.playlists,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: l10n.newPlaylist,
                  child: IconButton(
                    key: const Key('create-offline-playlist'),
                    onPressed: _createPlaylist,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        if (playlists.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                l10n.noOfflinePlaylists,
                key: const Key('offline-playlists-empty'),
                style: const TextStyle(color: OtohaColors.mutedText),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.workspacePadding,
            ),
            sliver: SliverGrid(
              key: const Key('offline-playlist-grid'),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 244,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final playlist = playlists[index];
                return PlaylistCard(
                  cardKey: Key('offline-playlist-${playlist.id}'),
                  title: playlist.name,
                  subtitle: l10n.tracksCount(playlist.trackVideoIds.length),
                  artworkPath: _playlistArtwork(playlist),
                  onTap: () => setState(() {
                    _selectedPlaylistId = playlist.id;
                  }),
                );
              }, childCount: playlists.length),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _playlistDetail(OfflinePlaylist playlist) {
    final l10n = AppLocalizations.of(context)!;
    final downloadsById = <String, DownloadedTrack>{
      for (final track in widget.controller.downloads) track.videoId: track,
    };
    final tracks = playlist.trackVideoIds
        .map((videoId) => downloadsById[videoId])
        .whereType<DownloadedTrack>()
        .toList(growable: false);
    return CustomScrollView(
      key: const Key('offline-playlist-detail-scroll'),
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
                Tooltip(
                  message: l10n.back,
                  child: IconButton(
                    key: const Key('back-to-offline-playlists'),
                    onPressed: () => setState(() {
                      _selectedPlaylistId = null;
                    }),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox.square(
                  key: const Key('offline-playlist-detail-artwork'),
                  dimension: 144,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppMetrics.radius,
                          ),
                          child: ArtworkImage(
                            assetPath: _playlistArtwork(playlist),
                            semanticLabel: l10n.artwork(playlist.name),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Material(
                          color: OtohaColors.surfaceRaised,
                          shape: const CircleBorder(),
                          child: Tooltip(
                            message: l10n.choosePlaylistCover,
                            child: IconButton(
                              key: Key(
                                'choose-offline-playlist-cover-${playlist.id}',
                              ),
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () => _choosePlaylistArtwork(
                                      playlist,
                                      tracks,
                                    ),
                              icon: const Icon(Icons.image_outlined),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                        playlist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.tracksCount(tracks.length),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: l10n.renamePlaylist,
                  child: IconButton(
                    key: Key('rename-offline-playlist-${playlist.id}'),
                    onPressed: () => _renamePlaylist(playlist),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
                Tooltip(
                  message: l10n.deletePlaylist,
                  child: IconButton(
                    key: Key('delete-offline-playlist-${playlist.id}'),
                    onPressed: () => _confirmDeletePlaylist(playlist),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
        if (tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                l10n.noDownloadedTracksInPlaylist,
                style: const TextStyle(color: OtohaColors.mutedText),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.workspacePadding,
            ),
            sliver: SliverList.builder(
              itemCount: tracks.length * 2 - 1,
              itemBuilder: (context, index) {
                if (index.isOdd) {
                  return const SizedBox(height: 2);
                }
                final trackIndex = index ~/ 2;
                final track = tracks[trackIndex];
                return YouTubeTrackListRow(
                  rowKey: Key(
                    'offline-playlist-track-${playlist.id}-${track.videoId}',
                  ),
                  index: trackIndex + 1,
                  track: _asListTrack(track),
                  artworkFallback: track.artworkAsset,
                  isSelected:
                      widget.playerController.currentTrack?.localFilePath ==
                      track.filePath,
                  onTap: () => _play(playlist, track),
                  trailing: Tooltip(
                    message: l10n.removeFromPlaylist,
                    child: IconButton(
                      key: Key(
                        'remove-offline-playlist-track-${playlist.id}-${track.videoId}',
                      ),
                      onPressed: () =>
                          _confirmRemoveFromPlaylist(playlist, track),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                  ),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Future<void> _createPlaylist() async {
    final l10n = AppLocalizations.of(context)!;
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newPlaylist),
        content: TextFormField(
          key: const Key('offline-playlist-name'),
          autofocus: true,
          onChanged: (value) => enteredName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
          decoration: InputDecoration(labelText: l10n.playlistName),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredName),
            child: Text(l10n.createPlaylist),
          ),
        ],
      ),
    );
    if (mounted && name != null) {
      await widget.controller.createPlaylist(name);
    }
  }

  Future<void> _renamePlaylist(OfflinePlaylist playlist) async {
    final l10n = AppLocalizations.of(context)!;
    var enteredName = playlist.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renamePlaylist),
        content: TextFormField(
          key: const Key('offline-playlist-rename'),
          initialValue: playlist.name,
          autofocus: true,
          onChanged: (value) => enteredName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
          decoration: InputDecoration(labelText: l10n.playlistName),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredName),
            child: Text(l10n.renamePlaylist),
          ),
        ],
      ),
    );
    if (mounted && name != null) {
      await widget.controller.renamePlaylist(playlist: playlist, name: name);
    }
  }

  Future<void> _choosePlaylistArtwork(
    OfflinePlaylist playlist,
    List<DownloadedTrack> tracks,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final selectedVideoId = playlist.artworkVideoId ?? tracks.first.videoId;
    final videoId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.choosePlaylistCover),
        content: SizedBox(
          width: 440,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: tracks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return ListTile(
                key: Key('offline-playlist-cover-${track.videoId}'),
                selected: track.videoId == selectedVideoId,
                onTap: () => Navigator.pop(context, track.videoId),
                leading: SizedBox.square(
                  dimension: 48,
                  child: ArtworkImage(
                    assetPath: track.artworkAsset,
                    semanticLabel: l10n.artwork(track.album),
                  ),
                ),
                title: Text(track.title),
                subtitle: Text(track.artist),
                trailing: track.videoId == selectedVideoId
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
              );
            },
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
    if (videoId != null) {
      await widget.controller.setPlaylistArtwork(
        playlist: playlist,
        videoId: videoId,
      );
    }
  }

  Future<void> _confirmDeletePlaylist(OfflinePlaylist playlist) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-offline-playlist-confirmation'),
        title: Text(l10n.deletePlaylist),
        content: Text(l10n.deletePlaylistConfirmation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.close),
          ),
          FilledButton(
            key: const Key('confirm-delete-offline-playlist'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deletePlaylist),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await widget.controller.deletePlaylist(playlist);
    }
  }

  Future<void> _confirmRemoveFromPlaylist(
    OfflinePlaylist playlist,
    DownloadedTrack track,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('remove-from-offline-playlist-confirmation'),
        title: Text(l10n.removeFromPlaylist),
        content: Text(l10n.removeFromPlaylistConfirmation),
        actions: <Widget>[
          TextButton(
            key: const Key('cancel-remove-from-offline-playlist'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.close),
          ),
          FilledButton(
            key: const Key('confirm-remove-from-offline-playlist'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.removeFromPlaylist),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await widget.controller.removeFromPlaylist(
        playlist: playlist,
        videoId: track.videoId,
      );
    }
  }

  void _play(OfflinePlaylist playlist, DownloadedTrack selectedTrack) {
    final downloadsById = <String, DownloadedTrack>{
      for (final track in widget.controller.downloads) track.videoId: track,
    };
    final tracks = playlist.trackVideoIds
        .map((videoId) => downloadsById[videoId])
        .whereType<DownloadedTrack>()
        .map((track) => track.toTrack())
        .toList(growable: false);
    widget.playerController.playTracks(tracks);
    widget.playerController.selectTrack(selectedTrack.toTrack());
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

  YouTubeTrack _asListTrack(DownloadedTrack track) => YouTubeTrack(
    videoId: track.videoId,
    title: track.title,
    artists: <String>[track.artist],
    album: track.album,
    durationSeconds: track.durationSeconds,
  );
}
