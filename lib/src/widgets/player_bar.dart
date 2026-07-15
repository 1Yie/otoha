import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../services/audio_playback_engine.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/offline_library_controller.dart';
import '../workspaces/workspace_views.dart';
import 'artwork_image.dart';

class MusicPlayerBar extends StatelessWidget {
  const MusicPlayerBar({
    required this.playerController,
    required this.shellController,
    this.offlineLibraryController,
    super.key,
  });

  final PlayerController playerController;
  final ShellController shellController;
  final OfflineLibraryController? offlineLibraryController;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('player-bar'),
      height: AppMetrics.playerHeight,
      color: OtohaColors.surface,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          playerController,
          shellController,
        ]),
        builder: (context, _) {
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox.expand(
                  child: Stack(
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _TransportControls(
                          playerController: playerController,
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: _NowPlaying(
                            playerController: playerController,
                            onOpenLyrics: shellController.toggleExpandedLyrics,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _TrackActions(
                              playerController: playerController,
                              shellController: shellController,
                              offlineLibraryController:
                                  offlineLibraryController,
                            ),
                            const SizedBox(width: 8),
                            _PlaybackActions(
                              playerController: playerController,
                              shellController: shellController,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _PlaybackProgress(
                  playerController: playerController,
                  reduceMotion: shellController.reduceMotion,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({
    required this.playerController,
    required this.reduceMotion,
  });

  final PlayerController playerController;
  final bool reduceMotion;

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isScrubbing = false;
  late final AnimationController _bufferPulse;

  @override
  void initState() {
    super.initState();
    _bufferPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncBufferPulse();
  }

  @override
  void didUpdateWidget(covariant _PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBufferPulse();
  }

  @override
  void dispose() {
    _bufferPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playerController.currentTrack;
    final durationSeconds = track?.durationSeconds ?? 0;
    final progress = durationSeconds <= 0
        ? 0.0
        : (widget.playerController.positionSeconds / durationSeconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final isActive = track != null && (_isHovered || _isScrubbing);
    final isBuffering = widget.playerController.isBuffering;
    final trackHeight = isActive ? 6.0 : (isBuffering ? 3.0 : 2.0);
    final thumbDiameter = _isScrubbing ? 18.0 : 14.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final thumbLeft =
              (constraints.maxWidth * progress - thumbDiameter / 2)
                  .clamp(0.0, constraints.maxWidth - thumbDiameter)
                  .toDouble();
          return Listener(
            onPointerDown: (_) => setState(() => _isScrubbing = true),
            onPointerUp: (_) => setState(() => _isScrubbing = false),
            onPointerCancel: (_) => setState(() => _isScrubbing = false),
            child: GestureDetector(
              key: const Key('player-progress'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                setState(() => _isScrubbing = true);
                _seekToPosition(details.localPosition.dx, constraints.maxWidth);
              },
              onTapUp: (_) => setState(() => _isScrubbing = false),
              onTapCancel: () => setState(() => _isScrubbing = false),
              onHorizontalDragStart: (_) => setState(() => _isScrubbing = true),
              onHorizontalDragUpdate: (details) => _seekToPosition(
                details.localPosition.dx,
                constraints.maxWidth,
              ),
              onHorizontalDragEnd: (_) => setState(() => _isScrubbing = false),
              onHorizontalDragCancel: () =>
                  setState(() => _isScrubbing = false),
              child: SizedBox(
                height: 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: trackHeight,
                        color: OtohaColors.border,
                      ),
                    ),
                    if (isBuffering)
                      Positioned(
                        key: const Key('player-progress-buffering'),
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedBuilder(
                          animation: _bufferPulse,
                          builder: (context, _) {
                            final opacity = widget.reduceMotion
                                ? 0.42
                                : 0.22 + _bufferPulse.value * 0.55;
                            return Container(
                              height: trackHeight,
                              color: OtohaColors.accent.withValues(
                                alpha: opacity,
                              ),
                            );
                          },
                        ),
                      ),
                    if (!isBuffering)
                      Positioned(
                        key: const Key('player-progress-elapsed'),
                        top: 0,
                        left: 0,
                        width: constraints.maxWidth * progress,
                        child: Container(
                          height: trackHeight,
                          color: OtohaColors.accent,
                        ),
                      ),
                    if (isActive && !isBuffering)
                      Positioned(
                        key: const Key('player-progress-thumb'),
                        top: (trackHeight - thumbDiameter) / 2,
                        left: thumbLeft,
                        child: AnimatedContainer(
                          key: _isScrubbing
                              ? const Key('player-progress-thumb-selected')
                              : null,
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          width: thumbDiameter,
                          height: thumbDiameter,
                          decoration: BoxDecoration(
                            color: OtohaColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              if (_isScrubbing)
                                BoxShadow(
                                  color: OtohaColors.accent.withValues(
                                    alpha: 0.55,
                                  ),
                                  blurRadius: 16,
                                  spreadRadius: 3,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _seekToPosition(double position, double width) {
    final track = widget.playerController.currentTrack;
    if (track == null || width == 0 || track.durationSeconds <= 0) {
      return;
    }
    final progress = (position / width).clamp(0.0, 1.0).toDouble();
    widget.playerController.seekTo((track.durationSeconds * progress).round());
  }

  void _syncBufferPulse() {
    if (widget.playerController.isBuffering && !widget.reduceMotion) {
      _bufferPulse.repeat(reverse: true);
    } else {
      _bufferPulse.stop();
      _bufferPulse.value = 0;
    }
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final track = playerController.currentTrack;
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: l10n.shortcutTooltip(l10n.previous, '←'),
          child: IconButton(
            onPressed: track == null ? null : playerController.previous,
            icon: const Icon(Icons.skip_previous_rounded),
            iconSize: 30,
          ),
        ),
        Tooltip(
          message: l10n.shortcutTooltip(
            playerController.isPlaying ? l10n.pause : l10n.play,
            'Space',
          ),
          child: IconButton(
            key: const Key('player-play'),
            onPressed: track == null ? null : playerController.togglePlaying,
            icon: Icon(
              playerController.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            iconSize: 42,
          ),
        ),
        Tooltip(
          message: l10n.shortcutTooltip(l10n.next, '→'),
          child: IconButton(
            key: const Key('player-next'),
            onPressed: track == null ? null : playerController.next,
            icon: const Icon(Icons.skip_next_rounded),
            iconSize: 30,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 160,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                key: const Key('player-time'),
                '${formatDuration(playerController.positionSeconds)} / '
                '${track == null || track.durationSeconds <= 0 ? l10n.unknownDuration : formatDuration(track.durationSeconds)}',
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: OtohaColors.mutedText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({
    required this.playerController,
    required this.onOpenLyrics,
  });

  final PlayerController playerController;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    final track = playerController.currentTrack;
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: track == null
          ? l10n.noTrackSelected
          : track.isVideo
          ? l10n.openVideo
          : l10n.openFullLyrics,
      child: InkWell(
        key: const Key('player-now-playing'),
        onTap: track == null ? null : onOpenLyrics,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppMetrics.radius),
        ),
        child: SizedBox(
          height: 68,
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppMetrics.radius),
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: track == null
                      ? const ColoredBox(
                          color: OtohaColors.surfaceRaised,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: OtohaColors.mutedText,
                          ),
                        )
                      : ArtworkImage(
                          assetPath: track.artworkAsset,
                          semanticLabel: l10n.artwork(track.album),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      track?.title ?? l10n.noTrackSelected,
                      key: const Key('player-track'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track == null
                          ? ''
                          : playerController.playbackError == null
                          ? '${track.artist} - ${track.album}'
                          : _playbackErrorLabel(
                              playerController.playbackError!,
                              l10n,
                              isVideo: track.isVideo,
                            ),
                      key: const Key('player-playback-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: playerController.playbackError == null
                            ? OtohaColors.mutedText
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _playbackErrorLabel(
  AudioPlaybackFailure error,
  AppLocalizations l10n, {
  required bool isVideo,
}) => isVideo
    ? switch (error) {
        AudioPlaybackFailure.engineCouldNotPlay => l10n.videoEngineCouldNotPlay,
        AudioPlaybackFailure.streamUnavailable => l10n.videoStreamUnavailable,
        AudioPlaybackFailure.startFailed => l10n.unableToStartVideoPlayback,
      }
    : switch (error) {
        AudioPlaybackFailure.engineCouldNotPlay => l10n.audioEngineCouldNotPlay,
        AudioPlaybackFailure.streamUnavailable => l10n.audioStreamUnavailable,
        AudioPlaybackFailure.startFailed => l10n.unableToStartAudioPlayback,
      };

class _TrackActions extends StatelessWidget {
  const _TrackActions({
    required this.playerController,
    required this.shellController,
    required this.offlineLibraryController,
  });

  final PlayerController playerController;
  final ShellController shellController;
  final OfflineLibraryController? offlineLibraryController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = offlineLibraryController;
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _buildActions(context, l10n, controller),
      );
    }
    return _buildActions(context, l10n, null);
  }

  Widget _buildActions(
    BuildContext context,
    AppLocalizations l10n,
    OfflineLibraryController? offlineLibraryController,
  ) {
    final track = playerController.currentTrack;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (track?.canPlayVideo ?? false)
          Tooltip(
            message: track!.isVideo ? l10n.switchToAudio : l10n.switchToVideo,
            child: IconButton(
              key: const Key('player-media-mode'),
              color: track.isVideo ? OtohaColors.accent : null,
              onPressed: playerController.toggleVideoMode,
              icon: Icon(
                track.isVideo
                    ? Icons.music_note_rounded
                    : Icons.videocam_rounded,
              ),
            ),
          ),
        Tooltip(
          message: l10n.queue,
          child: IconButton(
            key: const Key('player-queue'),
            color: shellController.activePanel == SidePanel.queue
                ? OtohaColors.accent
                : null,
            onPressed: () => shellController.togglePanel(SidePanel.queue),
            icon: const Icon(Icons.playlist_add_rounded),
          ),
        ),
        if (offlineLibraryController case final controller?
            when track?.youtubeVideoId != null &&
                controller.youtubeLibraryController.isSignedIn)
          Tooltip(
            message: controller.isDownloaded(track!.youtubeVideoId!)
                ? l10n.downloaded
                : l10n.downloadCurrentTrack,
            child: IconButton(
              key: const Key('player-download'),
              onPressed:
                  controller.downloadingVideoId == null &&
                      !controller.isDownloaded(track.youtubeVideoId!)
                  ? () => controller.download(track)
                  : null,
              icon: controller.downloadingVideoId == track.youtubeVideoId
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      controller.isDownloaded(track.youtubeVideoId!)
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                    ),
            ),
          ),
      ],
    );
  }
}

class _PlaybackActions extends StatelessWidget {
  const _PlaybackActions({
    required this.playerController,
    required this.shellController,
  });

  final PlayerController playerController;
  final ShellController shellController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _VolumeButton(playerController: playerController),
        Tooltip(
          message: l10n.outputDeviceWithValue(
            l10n.outputDevice,
            _outputDeviceLabel(playerController, l10n),
          ),
          child: IconButton(
            key: const Key('player-devices'),
            color: shellController.activePanel == SidePanel.devices
                ? OtohaColors.accent
                : null,
            onPressed: () => shellController.togglePanel(SidePanel.devices),
            icon: const Icon(Icons.speaker_group_outlined),
          ),
        ),
        Tooltip(
          message: l10n.shortcutTooltip(
            _repeatLabel(playerController.repeatMode, l10n),
            '/',
          ),
          child: IconButton(
            color: playerController.repeatMode == PlaybackRepeatMode.off
                ? null
                : OtohaColors.accent,
            onPressed: playerController.currentTrack == null
                ? null
                : playerController.cycleRepeatMode,
            icon: Icon(
              playerController.repeatMode == PlaybackRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
            ),
          ),
        ),
        Tooltip(
          message: l10n.shuffle,
          child: IconButton(
            color: playerController.isShuffled ? OtohaColors.accent : null,
            onPressed: playerController.currentTrack == null
                ? null
                : playerController.toggleShuffle,
            icon: const Icon(Icons.shuffle_rounded),
          ),
        ),
      ],
    );
  }

  String _repeatLabel(PlaybackRepeatMode mode, AppLocalizations l10n) =>
      switch (mode) {
        PlaybackRepeatMode.off => l10n.repeatOff,
        PlaybackRepeatMode.all => l10n.repeatAll,
        PlaybackRepeatMode.one => l10n.repeatOne,
      };

  String _outputDeviceLabel(
    PlayerController playerController,
    AppLocalizations l10n,
  ) {
    final device = playerController.selectedOutputDevice;
    if (device == null) {
      return l10n.outputUnavailable;
    }
    if (device.isSystemDefault) {
      return l10n.systemDefault;
    }
    return device.description.isEmpty ? device.id : device.description;
  }
}

class _VolumeButton extends StatefulWidget {
  const _VolumeButton({required this.playerController});

  final PlayerController playerController;

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;

  @override
  void dispose() {
    _menuEntry?.remove();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuEntry != null) {
      _hideMenu();
      return;
    }

    _menuEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideMenu,
            child: Stack(
              children: <Widget>[
                CompositedTransformFollower(
                  link: _layerLink,
                  targetAnchor: Alignment.topCenter,
                  followerAnchor: Alignment.bottomCenter,
                  offset: const Offset(0, -8),
                  showWhenUnlinked: false,
                  child: GestureDetector(
                    onTap: () {},
                    child: _VolumePopup(
                      playerController: widget.playerController,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_menuEntry!);
    setState(() {});
  }

  void _hideMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final volume = widget.playerController.volume;
    final l10n = AppLocalizations.of(context)!;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: l10n.volume,
        child: IconButton(
          key: const Key('player-volume'),
          color: _menuEntry == null ? null : OtohaColors.accent,
          onPressed: _toggleMenu,
          icon: Icon(_volumeIcon(volume)),
        ),
      ),
    );
  }

  IconData _volumeIcon(double volume) {
    if (volume == 0) {
      return Icons.volume_off_rounded;
    }
    if (volume < 0.5) {
      return Icons.volume_down_rounded;
    }
    return Icons.volume_up_rounded;
  }
}

class _VolumePopup extends StatelessWidget {
  const _VolumePopup({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      key: const Key('player-volume-popup'),
      color: OtohaColors.surfaceRaised,
      elevation: 8,
      borderRadius: const BorderRadius.all(Radius.circular(AppMetrics.radius)),
      child: SizedBox(
        width: 224,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedBuilder(
            animation: playerController,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        l10n.volume,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        l10n.volumePercentage(
                          (playerController.volume * 100).round(),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    key: const Key('player-volume-slider'),
                    value: playerController.volume,
                    onChanged: playerController.setVolume,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
