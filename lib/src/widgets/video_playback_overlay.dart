import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../services/audio_playback_engine.dart';
import '../state/desktop_shell_controllers.dart';

class VideoPlaybackOverlay extends StatelessWidget {
  const VideoPlaybackOverlay({
    required this.track,
    required this.playerController,
    required this.shellController,
    this.videoController,
    @visibleForTesting this.videoStateOverride,
    super.key,
  }) : assert(videoController == null || videoStateOverride == null);

  final Track track;
  final PlayerController playerController;
  final ShellController shellController;
  final VideoController? videoController;
  final VideoState? videoStateOverride;

  @override
  Widget build(BuildContext context) {
    final controller = videoController;
    return ColoredBox(
      key: const Key('video-playback-overlay'),
      color: Colors.black,
      child: controller == null
          ? Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const Center(
                  child: Icon(
                    Icons.videocam_off_rounded,
                    key: Key('video-playback-surface-unavailable'),
                    color: OtohaColors.mutedText,
                    size: 44,
                  ),
                ),
                _OtohaVideoControls(
                  track: track,
                  playerController: playerController,
                  shellController: shellController,
                  videoState: videoStateOverride,
                ),
              ],
            )
          : Video(
              key: const Key('video-playback-surface'),
              controller: controller,
              fit: BoxFit.contain,
              fill: Colors.black,
              controls: (videoState) => _OtohaVideoControls(
                track: track,
                playerController: playerController,
                shellController: shellController,
                videoState: videoState,
              ),
            ),
    );
  }
}

class _OtohaVideoControls extends StatefulWidget {
  const _OtohaVideoControls({
    required this.track,
    required this.playerController,
    required this.shellController,
    this.videoState,
  });

  final Track track;
  final PlayerController playerController;
  final ShellController shellController;
  final VideoState? videoState;

  @override
  State<_OtohaVideoControls> createState() => _OtohaVideoControlsState();
}

class _OtohaVideoControlsState extends State<_OtohaVideoControls>
    with WindowListener {
  Timer? _hideTimer;
  bool _isVisible = true;
  bool _isFullscreen = false;
  Future<void>? _fullscreenTransition;
  double _lastAudibleVolume = 0.72;

  @override
  void initState() {
    super.initState();
    if (widget.playerController.volume > 0) {
      _lastAudibleVolume = widget.playerController.volume;
    }
    if (_usesNativeDesktopFullscreen && widget.videoState != null) {
      windowManager.addListener(this);
      unawaited(_syncNativeFullscreen());
    } else {
      _isFullscreen = widget.videoState?.isFullscreen() ?? false;
    }
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant _OtohaVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_usesNativeDesktopFullscreen) {
      _isFullscreen = widget.videoState?.isFullscreen() ?? false;
      return;
    }
    if (oldWidget.videoState == null && widget.videoState != null) {
      windowManager.addListener(this);
      unawaited(_syncNativeFullscreen());
    } else if (oldWidget.videoState != null && widget.videoState == null) {
      windowManager.removeListener(this);
      _isFullscreen = false;
    }
  }

  @override
  void dispose() {
    if (_usesNativeDesktopFullscreen && widget.videoState != null) {
      windowManager.removeListener(this);
    }
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) {
      setState(() => _isFullscreen = true);
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) {
      setState(() => _isFullscreen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        cursor: _isVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: (_) => _showControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTap: widget.videoState == null ? null : _toggleFullscreen,
          child: AnimatedBuilder(
            animation: widget.playerController,
            builder: (context, _) {
              if (!widget.playerController.isPlaying && !_isVisible) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _showControls(scheduleHide: false);
                  }
                });
              }
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (widget.playerController.isBuffering)
                    const Center(
                      child: SizedBox.square(
                        dimension: 34,
                        child: CircularProgressIndicator(
                          key: Key('video-buffering-indicator'),
                          color: OtohaColors.accent,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  if (widget.playerController.playbackError case final error?)
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 440),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.video_file_outlined,
                              color: OtohaColors.mutedText,
                              size: 38,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _videoPlaybackErrorLabel(
                                error,
                                AppLocalizations.of(context)!,
                              ),
                              key: const Key('video-playback-error'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: OtohaColors.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: _isVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !_isVisible,
                      child: Column(
                        children: <Widget>[
                          _buildTopBar(context),
                          const Spacer(),
                          _buildBottomBar(context),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      key: const Key('video-playback-drag-area'),
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _startDragging(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 16, 36),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xC9000000), Colors.transparent],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: OtohaColors.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: OtohaColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _ControlButton(
              buttonKey: const Key('close-video-playback'),
              tooltip: l10n.collapseVideo,
              icon: Icons.keyboard_arrow_down_rounded,
              onPressed: _close,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = widget.playerController;
    final totalSeconds = controller.currentTrack?.durationSeconds ?? 0;
    final sliderMaximum = totalSeconds > 0
        ? totalSeconds.toDouble()
        : controller.positionSeconds.clamp(1, 1 << 31).toDouble();
    final sliderValue = controller.positionSeconds
        .clamp(0, sliderMaximum.round())
        .toDouble();
    final isFullscreen = _usesNativeDesktopFullscreen
        ? _isFullscreen
        : widget.videoState?.isFullscreen() ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Color(0xE6111210)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: OtohaColors.accent,
              inactiveTrackColor: Colors.white30,
              thumbColor: OtohaColors.accent,
              overlayColor: OtohaColors.accent.withValues(alpha: 0.14),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: const Key('video-playback-progress'),
              value: sliderValue,
              max: sliderMaximum,
              onChanged: (value) => controller.seekTo(value.round()),
            ),
          ),
          Row(
            children: <Widget>[
              _ControlButton(
                buttonKey: const Key('video-play-pause'),
                tooltip: controller.isPlaying ? l10n.pause : l10n.play,
                icon: controller.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: controller.togglePlaying,
              ),
              const SizedBox(width: 4),
              _ControlButton(
                buttonKey: const Key('video-volume-toggle'),
                tooltip: l10n.volume,
                icon: controller.volume == 0
                    ? Icons.volume_off_rounded
                    : controller.volume < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
                onPressed: _toggleMuted,
              ),
              SizedBox(
                width: 92,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: OtohaColors.text,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: OtohaColors.text,
                    overlayColor: Colors.white10,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    key: const Key('video-volume'),
                    value: controller.volume,
                    onChanged: (value) {
                      if (value > 0) {
                        _lastAudibleVolume = value;
                      }
                      controller.setVolume(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_formatTime(controller.positionSeconds)} / '
                '${_formatTime(totalSeconds)}',
                key: const Key('video-playback-time'),
                style: const TextStyle(
                  color: OtohaColors.text,
                  fontSize: 12,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              _ControlButton(
                buttonKey: const Key('video-switch-to-audio'),
                tooltip: l10n.switchToAudio,
                icon: Icons.music_note_rounded,
                onPressed: () => unawaited(_switchToAudio()),
              ),
              const Spacer(),
              if (widget.videoState != null)
                _ControlButton(
                  buttonKey: const Key('video-fullscreen'),
                  tooltip: isFullscreen
                      ? l10n.exitFullscreen
                      : l10n.enterFullscreen,
                  icon: isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  onPressed: _toggleFullscreen,
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleMuted() {
    final controller = widget.playerController;
    if (controller.volume > 0) {
      _lastAudibleVolume = controller.volume;
      controller.setVolume(0);
    } else {
      controller.setVolume(_lastAudibleVolume);
    }
    _showControls();
  }

  Future<void> _toggleFullscreen() async {
    final videoState = widget.videoState;
    if (videoState == null || _fullscreenTransition != null) {
      return;
    }
    final transition = _performFullscreenToggle(videoState);
    _fullscreenTransition = transition;
    try {
      await transition;
    } finally {
      if (identical(_fullscreenTransition, transition)) {
        _fullscreenTransition = null;
      }
    }
  }

  Future<void> _close() async {
    final videoState = widget.videoState;
    try {
      await _fullscreenTransition;
      if (_usesNativeDesktopFullscreen && videoState != null) {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      } else if (videoState?.isFullscreen() ?? false) {
        await videoState!.exitFullscreen();
      }
    } on Object catch (error) {
      debugPrint('Unable to exit video fullscreen: $error');
    } finally {
      if (mounted) {
        setState(() => _isFullscreen = false);
      }
      widget.shellController.closeExpandedLyrics();
    }
  }

  Future<void> _switchToAudio() async {
    await _close();
    widget.playerController.setVideoMode(false);
  }

  void _startDragging() {
    if (_usesNativeDesktopFullscreen && !_isFullscreen) {
      unawaited(windowManager.startDragging());
    }
  }

  Future<void> _performFullscreenToggle(VideoState videoState) async {
    try {
      if (_usesNativeDesktopFullscreen) {
        final nextFullscreen = !await windowManager.isFullScreen();
        await windowManager.setFullScreen(nextFullscreen);
        if (mounted) {
          setState(() => _isFullscreen = nextFullscreen);
        }
      } else {
        await videoState.toggleFullscreen();
        if (mounted) {
          setState(() => _isFullscreen = videoState.isFullscreen());
        }
      }
    } on Object catch (error) {
      debugPrint('Unable to toggle video fullscreen: $error');
    } finally {
      if (mounted) {
        _showControls();
      }
    }
  }

  Future<void> _syncNativeFullscreen() async {
    try {
      final isFullscreen = await windowManager.isFullScreen();
      if (mounted) {
        setState(() => _isFullscreen = isFullscreen);
      }
    } on Object {
      // The desktop channel is unavailable in widget tests and early startup.
    }
  }

  void _toggleControls() {
    if (_isVisible && widget.playerController.isPlaying) {
      _hideTimer?.cancel();
      setState(() => _isVisible = false);
    } else {
      _showControls();
    }
  }

  void _showControls({bool scheduleHide = true}) {
    _hideTimer?.cancel();
    if (!_isVisible && mounted) {
      setState(() => _isVisible = true);
    }
    if (scheduleHide) {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.playerController.isPlaying) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.playerController.isPlaying) {
        setState(() => _isVisible = false);
      }
    });
  }
}

bool get _usesNativeDesktopFullscreen =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: buttonKey,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: OtohaColors.text,
          fixedSize: const Size.square(40),
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 24),
      ),
    );
  }
}

String _formatTime(int totalSeconds) {
  final duration = Duration(seconds: totalSeconds.clamp(0, 1 << 31));
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _videoPlaybackErrorLabel(
  AudioPlaybackFailure error,
  AppLocalizations l10n,
) => switch (error) {
  AudioPlaybackFailure.engineCouldNotPlay => l10n.videoEngineCouldNotPlay,
  AudioPlaybackFailure.streamUnavailable => l10n.videoStreamUnavailable,
  AudioPlaybackFailure.startFailed => l10n.unableToStartVideoPlayback,
};
