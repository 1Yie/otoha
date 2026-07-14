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
                      isSelected:
                          widget.playerController.currentTrack?.localFilePath ==
                          download.filePath,
                      onTap: () => _play(download),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (widget.controller.playlists.isNotEmpty)
                            Tooltip(
                              message: l10n.addToPlaylist,
                              child: IconButton(
                                key: Key('offline-add-${download.videoId}'),
                                onPressed: () => _addToPlaylist(download),
                                icon: const Icon(Icons.playlist_add_rounded),
                              ),
                            ),
                          Tooltip(
                            message: l10n.deleteDownload,
                            child: IconButton(
                              key: Key('offline-delete-${download.videoId}'),
                              onPressed: () => _confirmRemove(download),
                              icon: const Icon(Icons.delete_outline_rounded),
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

  YouTubeTrack _asListTrack(DownloadedTrack track) => YouTubeTrack(
    videoId: track.videoId,
    title: track.title,
    artists: <String>[track.artist],
    album: track.album,
    durationSeconds: track.durationSeconds,
  );

  void _play(DownloadedTrack track) {
    final tracks = widget.controller.downloads
        .map((download) => download.toTrack())
        .toList(growable: false);
    widget.playerController.playTracks(tracks);
    widget.playerController.selectTrack(track.toTrack());
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

  Future<void> _addToPlaylist(DownloadedTrack track) async {
    final l10n = AppLocalizations.of(context)!;
    final playlist = await showDialog<OfflinePlaylist>(
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
    if (playlist != null) {
      await widget.controller.addToPlaylist(playlist: playlist, track: track);
    }
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
