import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../state/desktop_shell_controllers.dart';
import '../workspaces/workspace_views.dart';
import 'artwork_image.dart';

class MusicPlayerBar extends StatelessWidget {
  const MusicPlayerBar({
    required this.playerController,
    required this.shellController,
    super.key,
  });

  final PlayerController playerController;
  final ShellController shellController;

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
                            _TrackActions(shellController: shellController),
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

class _PlaybackProgressState extends State<_PlaybackProgress> {
  bool _isHovered = false;
  bool _isScrubbing = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.playerController.currentTrack;
    final progress = track.durationSeconds <= 0
        ? 0.0
        : (widget.playerController.positionSeconds / track.durationSeconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final isActive = _isHovered || _isScrubbing;
    final trackHeight = isActive ? 6.0 : 2.0;
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
                    Positioned(
                      top: 0,
                      left: 0,
                      width: constraints.maxWidth * progress,
                      child: Container(
                        height: trackHeight,
                        color: OtohaColors.accent,
                      ),
                    ),
                    if (isActive)
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
    if (width == 0 ||
        widget.playerController.currentTrack.durationSeconds <= 0) {
      return;
    }
    final progress = (position / width).clamp(0.0, 1.0).toDouble();
    widget.playerController.seekTo(
      (widget.playerController.currentTrack.durationSeconds * progress).round(),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final track = playerController.currentTrack;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: 'Previous',
          child: IconButton(
            onPressed: playerController.previous,
            icon: const Icon(Icons.skip_previous_rounded),
            iconSize: 30,
          ),
        ),
        Tooltip(
          message: playerController.isPlaying ? 'Pause' : 'Play',
          child: IconButton(
            key: const Key('player-play'),
            onPressed: playerController.togglePlaying,
            icon: Icon(
              playerController.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            iconSize: 42,
          ),
        ),
        Tooltip(
          message: 'Next',
          child: IconButton(
            key: const Key('player-next'),
            onPressed: playerController.next,
            icon: const Icon(Icons.skip_next_rounded),
            iconSize: 30,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 88,
          child: Text(
            '${formatDuration(playerController.positionSeconds)} / '
            '${track.durationSeconds <= 0 ? '--:--' : formatDuration(track.durationSeconds)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: OtohaColors.mutedText),
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
    return Tooltip(
      message: 'Open full lyrics',
      child: InkWell(
        key: const Key('player-now-playing'),
        onTap: onOpenLyrics,
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
                  child: ArtworkImage(
                    assetPath: track.artworkAsset,
                    semanticLabel: '${track.album} artwork',
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
                      track.title,
                      key: const Key('player-track'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.artist} - ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: OtohaColors.mutedText,
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

class _TrackActions extends StatelessWidget {
  const _TrackActions({required this.shellController});

  final ShellController shellController;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: 'Queue',
          child: IconButton(
            key: const Key('player-queue'),
            color: shellController.activePanel == SidePanel.queue
                ? OtohaColors.accent
                : null,
            onPressed: () => shellController.togglePanel(SidePanel.queue),
            icon: const Icon(Icons.playlist_add_rounded),
          ),
        ),
        Tooltip(
          message: 'Lyrics',
          child: IconButton(
            key: const Key('player-lyrics'),
            color: shellController.activePanel == SidePanel.lyrics
                ? OtohaColors.accent
                : null,
            onPressed: () => shellController.togglePanel(SidePanel.lyrics),
            icon: const Icon(Icons.lyrics_outlined),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _VolumeButton(playerController: playerController),
        Tooltip(
          message: 'Output: ${shellController.selectedDevice}',
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
          message: _repeatLabel(playerController.repeatMode),
          child: IconButton(
            color: playerController.repeatMode == PlaybackRepeatMode.off
                ? null
                : OtohaColors.accent,
            onPressed: playerController.cycleRepeatMode,
            icon: Icon(
              playerController.repeatMode == PlaybackRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
            ),
          ),
        ),
        Tooltip(
          message: 'Shuffle',
          child: IconButton(
            color: playerController.isShuffled ? OtohaColors.accent : null,
            onPressed: playerController.toggleShuffle,
            icon: const Icon(Icons.shuffle_rounded),
          ),
        ),
      ],
    );
  }

  String _repeatLabel(PlaybackRepeatMode mode) => switch (mode) {
    PlaybackRepeatMode.off => 'Repeat off',
    PlaybackRepeatMode.all => 'Repeat all',
    PlaybackRepeatMode.one => 'Repeat one',
  };
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
    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: 'Volume',
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
                        'Volume',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${(playerController.volume * 100).round()}%',
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
