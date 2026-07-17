import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/youtube_track_list_row.dart';

class YouTubeHistoryWorkspace extends StatefulWidget {
  const YouTubeHistoryWorkspace({
    required this.controller,
    required this.playerController,
    required this.shellController,
    super.key,
  });

  final YouTubeLibraryController controller;
  final PlayerController playerController;
  final ShellController shellController;

  @override
  State<YouTubeHistoryWorkspace> createState() =>
      _YouTubeHistoryWorkspaceState();
}

class _YouTubeHistoryWorkspaceState extends State<YouTubeHistoryWorkspace> {
  late bool _wasSignedIn;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = widget.controller.isSignedIn;
    widget.controller.addListener(_loadAfterSignIn);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  @override
  void didUpdateWidget(covariant YouTubeHistoryWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_loadAfterSignIn);
      _wasSignedIn = widget.controller.isSignedIn;
      widget.controller.addListener(_loadAfterSignIn);
      _loadHistory();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_loadAfterSignIn);
    super.dispose();
  }

  void _loadAfterSignIn() {
    final isSignedIn = widget.controller.isSignedIn;
    if (isSignedIn && !_wasSignedIn) {
      _loadHistory();
    }
    _wasSignedIn = isSignedIn;
  }

  void _loadHistory() {
    unawaited(widget.controller.loadHistory());
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
        if (!widget.controller.isSignedIn) {
          return Center(
            key: const Key('youtube-history-signed-out'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.history,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('youtube-history-sign-in'),
                  onPressed: () =>
                      widget.shellController.togglePanel(SidePanel.account),
                  icon: const Icon(Icons.login_rounded),
                  label: Text(l10n.signInToYouTubeMusic),
                ),
              ],
            ),
          );
        }

        final tracks = widget.controller.historyTracks;
        final playbackTracks = tracks
            .map(_asPlaybackTrack)
            .toList(growable: false);
        return KeyedSubtree(
          key: const Key('youtube-history-workspace'),
          child: _HistoryBody(
            tracks: tracks,
            playbackTracks: playbackTracks,
            controller: widget.controller,
            playerController: widget.playerController,
          ),
        );
      },
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.tracks,
    required this.playbackTracks,
    required this.controller,
    required this.playerController,
  });

  final List<YouTubeTrack> tracks;
  final List<Track> playbackTracks;
  final YouTubeLibraryController controller;
  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLoading =
        controller.isLoadingHistory || controller.isLoadingMoreHistory;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 480 &&
            controller.hasMoreHistory &&
            !controller.isLoadingMoreHistory) {
          unawaited(controller.loadMoreHistory());
        }
        return false;
      },
      child: CustomScrollView(
        key: const Key('youtube-history-scroll'),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              AppMetrics.workspacePadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _HistoryHeader(
                isLoading: isLoading,
                onRefresh: () =>
                    unawaited(controller.loadHistory(forceRefresh: true)),
              ),
            ),
          ),
          if (isLoading) ...<Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(
                key: Key('youtube-history-loading-rail'),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          if (controller.isLoadingHistory && tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.historyErrorMessage != null && tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: TextButton.icon(
                  onPressed: () =>
                      unawaited(controller.loadHistory(forceRefresh: true)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.loadHistoryAgain),
                ),
              ),
            )
          else if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  l10n.noPlaybackHistoryFound,
                  style: Theme.of(context).textTheme.bodySmall,
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
                    rowKey: Key('youtube-history-track-${track.videoId}'),
                    index: trackIndex + 1,
                    track: track,
                    isSelected:
                        playerController.currentTrack?.id == track.videoId,
                    onTap: () => playerController.playTracks(
                      playbackTracks,
                      initialIndex: trackIndex,
                    ),
                  );
                },
              ),
            ),
          if (controller.isLoadingMoreHistory)
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
          if (tracks.isNotEmpty)
            const SliverToBoxAdapter(
              child: SizedBox(
                key: Key('youtube-history-bottom-padding'),
                height: 40,
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.isLoading, required this.onRefresh});

  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      key: const Key('youtube-history-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.yourActivity,
                    style: const TextStyle(
                      color: OtohaColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.history,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ],
              ),
            ),
            Tooltip(
              message: l10n.refreshHistory,
              child: IconButton(
                key: const Key('youtube-history-refresh'),
                onPressed: isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Track _asPlaybackTrack(YouTubeTrack track) {
  return Track(
    id: track.videoId,
    title: track.title,
    artist: track.artists.isEmpty ? 'YouTube Music' : track.artists.join(', '),
    album: track.album ?? 'YouTube history',
    artworkAsset: track.thumbnailUrl ?? '',
    durationSeconds: track.durationSeconds,
    lyrics: const <String>[],
    youtubeVideoId: track.videoId,
    videoAvailable: track.isVideo,
  );
}
