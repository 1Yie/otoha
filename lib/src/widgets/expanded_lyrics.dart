import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import 'artwork_image.dart';

class ExpandedLyricsOverlay extends StatefulWidget {
  const ExpandedLyricsOverlay({
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    this.readLyricsFile = _readLyricsFile,
    super.key,
  });

  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;
  final Future<String> Function(String path) readLyricsFile;

  @override
  State<ExpandedLyricsOverlay> createState() => _ExpandedLyricsOverlayState();
}

class _ExpandedLyricsOverlayState extends State<ExpandedLyricsOverlay> {
  final ScrollController _scrollController = ScrollController();
  late String _trackId;
  late List<GlobalKey> _lineKeys;
  late List<YouTubeLyricLine> _lyrics;
  late bool _usesRemoteLyrics;
  late bool _usesTimedLyrics;
  late bool _isLoadingLocalLyrics;
  late bool _isPlaying;
  late bool _isBuffering;
  int _activeLine = 0;
  int _positionSeconds = 0;

  @override
  void initState() {
    super.initState();
    _resetForCurrentTrack();
    widget.playerController.addListener(_syncLyrics);
    widget.youtubeLibraryController.addListener(_syncRemoteLyrics);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _requestLyrics(widget.playerController.currentTrack!);
      _scrollToActiveLine();
    });
  }

  @override
  void dispose() {
    widget.playerController.removeListener(_syncLyrics);
    widget.youtubeLibraryController.removeListener(_syncRemoteLyrics);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final track = widget.playerController.currentTrack!;
    final videoId = _videoIdFor(track);
    final usesLocalLyrics = track.localLyricsPath?.isNotEmpty ?? false;
    final hasResolvedLyrics = usesLocalLyrics
        ? !_isLoadingLocalLyrics
        : widget.youtubeLibraryController.lyricsVideoId == videoId &&
              !widget.youtubeLibraryController.isLoadingLyrics;
    final isLoadingLyrics = usesLocalLyrics
        ? _isLoadingLocalLyrics
        : videoId != null &&
              widget.youtubeLibraryController.isSignedIn &&
              !hasResolvedLyrics;
    return Material(
      key: const Key('expanded-lyrics-overlay'),
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: OtohaColors.canvas),
          ClipRect(
            child: Transform.scale(
              scale: 1.16,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: ArtworkImage(
                  assetPath: track.artworkAsset,
                  semanticLabel: l10n.backgroundArtwork(track.title),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xB3101110),
                  Color(0xE8101110),
                  Color(0xF8101110),
                ],
                stops: <double>[0, 0.55, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 88, 48, 132),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: _TrackSummary(track: track),
                    ),
                  ),
                ),
                const SizedBox(width: 64),
                Expanded(
                  flex: 4,
                  child: _LyricsScroller(
                    lines: _lyrics,
                    activeLine: _activeLine,
                    lineKeys: _lineKeys,
                    scrollController: _scrollController,
                    reduceMotion: widget.shellController.reduceMotion,
                    isLoading: isLoadingLyrics,
                    isRemote: _usesRemoteLyrics,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: AppMetrics.titleBarHeight,
            child: GestureDetector(
              key: const Key('expanded-lyrics-drag-area'),
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => _startDragging(),
            ),
          ),
          Positioned(
            top: 4,
            right: 8,
            child: Tooltip(
              message: l10n.closeFullLyrics,
              child: IconButton(
                key: const Key('expanded-lyrics-close'),
                onPressed: widget.shellController.closeExpandedLyrics,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                iconSize: 32,
              ),
            ),
          ),
          Positioned(
            left: 48,
            right: 48,
            bottom: 28,
            child: _ExpandedPlaybackControls(
              playerController: widget.playerController,
              positionSeconds: _positionSeconds,
            ),
          ),
        ],
      ),
    );
  }

  void _resetForCurrentTrack() {
    final track = widget.playerController.currentTrack!;
    _trackId = track.id;
    final videoId = _videoIdFor(track);
    final localLyricsPath = track.localLyricsPath;
    _usesRemoteLyrics =
        (localLyricsPath == null || localLyricsPath.isEmpty) && videoId != null;
    _usesTimedLyrics = _usesRemoteLyrics || localLyricsPath?.isNotEmpty == true;
    _isLoadingLocalLyrics = localLyricsPath?.isNotEmpty == true;
    _lyrics = localLyricsPath?.isNotEmpty == true
        ? const <YouTubeLyricLine>[]
        : videoId != null &&
              widget.youtubeLibraryController.lyricsVideoId == videoId
        ? widget.youtubeLibraryController.lyricsLines
        : videoId != null
        ? const <YouTubeLyricLine>[]
        : const <YouTubeLyricLine>[];
    _lineKeys = List<GlobalKey>.generate(_lyrics.length, (_) => GlobalKey());
    _activeLine = _activeLineFor(track);
    _positionSeconds = widget.playerController.positionSeconds;
    _isPlaying = widget.playerController.isPlaying;
    _isBuffering = widget.playerController.isBuffering;
  }

  void _syncLyrics() {
    final track = widget.playerController.currentTrack!;
    if (track.id != _trackId) {
      setState(_resetForCurrentTrack);
      _requestLyrics(track);
      _scheduleScroll();
      return;
    }

    final activeLine = _activeLineFor(track);
    final positionSeconds = widget.playerController.positionSeconds;
    final isPlaying = widget.playerController.isPlaying;
    final isBuffering = widget.playerController.isBuffering;
    if (activeLine == _activeLine &&
        positionSeconds == _positionSeconds &&
        isPlaying == _isPlaying &&
        isBuffering == _isBuffering) {
      return;
    }
    final activeLineChanged = activeLine != _activeLine;

    setState(() {
      _activeLine = activeLine;
      _positionSeconds = positionSeconds;
      _isPlaying = isPlaying;
      _isBuffering = isBuffering;
    });
    if (activeLineChanged) {
      _scheduleScroll();
    }
  }

  void _syncRemoteLyrics() {
    final track = widget.playerController.currentTrack!;
    final videoId = _videoIdFor(track);
    if (!_usesRemoteLyrics ||
        videoId == null ||
        widget.youtubeLibraryController.lyricsVideoId != videoId) {
      return;
    }

    final lyrics = widget.youtubeLibraryController.lyricsLines;
    if (listEquals(lyrics, _lyrics)) {
      return;
    }
    setState(() {
      _lyrics = lyrics;
      _lineKeys = List<GlobalKey>.generate(lyrics.length, (_) => GlobalKey());
      _activeLine = _activeLineFor(track);
    });
    _scheduleScroll();
  }

  void _requestLyrics(Track track) {
    final localLyricsPath = track.localLyricsPath;
    if (localLyricsPath != null && localLyricsPath.isNotEmpty) {
      unawaited(_loadLocalLyrics(track.id, localLyricsPath));
      return;
    }
    final videoId = _videoIdFor(track);
    if (videoId != null) {
      widget.youtubeLibraryController.loadLyrics(
        videoId: videoId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationSeconds: track.durationSeconds,
      );
    }
  }

  Future<void> _loadLocalLyrics(String trackId, String path) async {
    var lines = const <YouTubeLyricLine>[];
    try {
      lines = _parseBundledLyrics(await widget.readLyricsFile(path));
    } on Object {
      lines = const <YouTubeLyricLine>[];
    }
    if (!mounted || widget.playerController.currentTrack?.id != trackId) {
      return;
    }
    setState(() {
      _lyrics = lines;
      _lineKeys = List<GlobalKey>.generate(lines.length, (_) => GlobalKey());
      _isLoadingLocalLyrics = false;
      _activeLine = _activeLineFor(widget.playerController.currentTrack!);
    });
    _scheduleScroll();
  }

  int _activeLineFor(Track track) {
    if (_lyrics.isEmpty) return -1;
    if (_usesTimedLyrics) {
      var activeLine = -1;
      for (var index = 0; index < _lyrics.length; index += 1) {
        final startSeconds = _lyrics[index].startSeconds;
        if (startSeconds == null ||
            startSeconds > widget.playerController.positionSeconds) {
          continue;
        }
        activeLine = index;
      }
      return activeLine;
    }
    if (track.durationSeconds <= 0) return -1;
    return (widget.playerController.positionSeconds /
            track.durationSeconds *
            _lyrics.length)
        .floor()
        .clamp(0, _lyrics.length - 1)
        .toInt();
  }

  String? _videoIdFor(Track track) {
    final youtubeVideoId = track.youtubeVideoId;
    if (youtubeVideoId != null && youtubeVideoId.isNotEmpty) {
      return youtubeVideoId;
    }
    final id = track.id.startsWith('youtube:')
        ? track.id.substring('youtube:'.length)
        : track.id;
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveLine());
  }

  void _scrollToActiveLine() {
    if (!mounted || _activeLine < 0 || _activeLine >= _lineKeys.length) {
      return;
    }

    final lineContext = _lineKeys[_activeLine].currentContext;
    if (lineContext == null) {
      return;
    }

    Scrollable.ensureVisible(
      lineContext,
      alignment: 0.42,
      duration: widget.shellController.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _startDragging() {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      windowManager.startDragging();
    }
  }
}

Future<String> _readLyricsFile(String path) => File(path).readAsString();

List<YouTubeLyricLine> _parseBundledLyrics(String value) {
  final timestamp = RegExp(r'\[(\d+):(\d{2}(?:\.\d{1,3})?)\]');
  final lines = <YouTubeLyricLine>[];
  for (final rawLine in value.split(RegExp(r'\r?\n'))) {
    final matches = timestamp.allMatches(rawLine).toList(growable: false);
    final text = rawLine.replaceAll(timestamp, '').trim();
    if (text.isEmpty) {
      continue;
    }
    if (matches.isEmpty) {
      lines.add(YouTubeLyricLine(text: text));
      continue;
    }
    for (final match in matches) {
      lines.add(
        YouTubeLyricLine(
          text: text,
          startSeconds:
              int.parse(match.group(1)!) * 60 + double.parse(match.group(2)!),
        ),
      );
    }
  }
  return lines;
}

class _TrackSummary extends StatelessWidget {
  const _TrackSummary({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppMetrics.radius),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: ArtworkImage(
              key: const Key('expanded-lyrics-artwork'),
              assetPath: track.artworkAsset,
              semanticLabel: l10n.artwork(track.album),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          track.title,
          key: const Key('expanded-lyrics-track-title'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '${track.artist} - ${track.album}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: OtohaColors.mutedText),
        ),
      ],
    );
  }
}

class _ExpandedPlaybackControls extends StatelessWidget {
  const _ExpandedPlaybackControls({
    required this.playerController,
    required this.positionSeconds,
  });

  final PlayerController playerController;
  final int positionSeconds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final track = playerController.currentTrack!;
    final progress = track.durationSeconds <= 0
        ? 0.0
        : (positionSeconds / track.durationSeconds).clamp(0.0, 1.0).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _PlaybackProgressControl(
          playerController: playerController,
          progress: progress,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Tooltip(
              message: l10n.previousTrack,
              child: IconButton(
                key: const Key('expanded-lyrics-previous'),
                onPressed: playerController.previous,
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 30,
              ),
            ),
            const SizedBox(width: 16),
            Material(
              color: OtohaColors.accent,
              shape: const CircleBorder(),
              child: Tooltip(
                message: playerController.isPlaying ? l10n.pause : l10n.play,
                child: IconButton(
                  key: const Key('expanded-lyrics-toggle-playing'),
                  onPressed: playerController.togglePlaying,
                  color: const Color(0xFF1A210F),
                  icon: Icon(
                    playerController.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  iconSize: 32,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Tooltip(
              message: l10n.nextTrack,
              child: IconButton(
                key: const Key('expanded-lyrics-next'),
                onPressed: playerController.next,
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 30,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaybackProgressControl extends StatelessWidget {
  const _PlaybackProgressControl({
    required this.playerController,
    required this.progress,
  });

  final PlayerController playerController;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: l10n.playbackProgress,
      slider: true,
      value: l10n.volumePercentage((progress * 100).round()),
      child: LayoutBuilder(
        builder: (context, constraints) {
          void seekTo(double dx) {
            final duration = playerController.currentTrack!.durationSeconds;
            if (duration <= 0 || constraints.maxWidth <= 0) {
              return;
            }
            final position = (dx / constraints.maxWidth).clamp(0.0, 1.0);
            playerController.seekTo((duration * position).round());
          }

          return GestureDetector(
            key: const Key('expanded-lyrics-playback-progress'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => seekTo(details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
                seekTo(details.localPosition.dx),
            child: SizedBox(
              height: 28,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  Container(
                    height: 3,
                    color: OtohaColors.text.withValues(alpha: 0.28),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(height: 3, color: OtohaColors.accent),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LyricsScroller extends StatelessWidget {
  const _LyricsScroller({
    required this.lines,
    required this.activeLine,
    required this.lineKeys,
    required this.scrollController,
    required this.reduceMotion,
    required this.isLoading,
    required this.isRemote,
  });

  final List<YouTubeLyricLine> lines;
  final int activeLine;
  final List<GlobalKey> lineKeys;
  final ScrollController scrollController;
  final bool reduceMotion;
  final bool isLoading;
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: isLoading
              ? const Center(
                  child: SizedBox(
                    key: Key('expanded-lyrics-loading'),
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                )
              : lines.isEmpty
              ? Center(
                  child: Text(
                    isRemote
                        ? l10n.lyricsUnavailableForTrack
                        : l10n.lyricsUnavailable,
                    key: const Key('expanded-lyrics-unavailable'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: OtohaColors.mutedText,
                    ),
                  ),
                )
              : _LyricsViewport(
                  child: ScrollConfiguration(
                    key: const Key('expanded-lyrics-scroll-configuration'),
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      key: const Key('expanded-lyrics-scroll'),
                      controller: scrollController,
                      padding: const EdgeInsets.only(
                        top: 64,
                        right: 24,
                        bottom: 96,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List<Widget>.generate(lines.length, (index) {
                          final isActive =
                              index == activeLine && activeLine >= 0;
                          return Padding(
                            key: lineKeys[index],
                            padding: const EdgeInsets.only(bottom: 22),
                            child: AnimatedDefaultTextStyle(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                color: isActive
                                    ? OtohaColors.accent
                                    : OtohaColors.text.withValues(alpha: 0.48),
                                fontSize: isActive ? 30 : 24,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                height: 1.25,
                              ),
                              child: Text(lines[index].text),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _LyricsViewport extends StatelessWidget {
  const _LyricsViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: <double>[0, 0.12, 0.88, 1],
          ).createShader(bounds),
          child: child,
        ),
        const _LyricsEdgeFade(
          key: Key('expanded-lyrics-top-fade'),
          isTop: true,
        ),
        const _LyricsEdgeFade(
          key: Key('expanded-lyrics-bottom-fade'),
          isTop: false,
        ),
      ],
    );
  }
}

class _LyricsEdgeFade extends StatelessWidget {
  const _LyricsEdgeFade({required this.isTop, super.key});

  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: 0,
      right: 0,
      height: 56,
      child: IgnorePointer(
        child: ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const <Color>[Colors.white, Colors.transparent],
            ).createShader(bounds),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
