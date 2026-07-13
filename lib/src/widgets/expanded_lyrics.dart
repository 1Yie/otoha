import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../state/desktop_shell_controllers.dart';
import 'artwork_image.dart';

class ExpandedLyricsOverlay extends StatefulWidget {
  const ExpandedLyricsOverlay({
    required this.playerController,
    required this.shellController,
    super.key,
  });

  final PlayerController playerController;
  final ShellController shellController;

  @override
  State<ExpandedLyricsOverlay> createState() => _ExpandedLyricsOverlayState();
}

class _ExpandedLyricsOverlayState extends State<ExpandedLyricsOverlay> {
  final ScrollController _scrollController = ScrollController();
  late String _trackId;
  late List<GlobalKey> _lineKeys;
  int _activeLine = 0;

  @override
  void initState() {
    super.initState();
    _resetForCurrentTrack();
    widget.playerController.addListener(_syncLyrics);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveLine());
  }

  @override
  void dispose() {
    widget.playerController.removeListener(_syncLyrics);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playerController.currentTrack;
    return Material(
      key: const Key('expanded-lyrics-overlay'),
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
            child: ArtworkImage(
              assetPath: track.artworkAsset,
              semanticLabel: '${track.title} background artwork',
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
            padding: const EdgeInsets.fromLTRB(48, 40, 48, 48),
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
                const VerticalDivider(width: 96),
                Expanded(
                  flex: 4,
                  child: _LyricsScroller(
                    lines: track.lyrics,
                    activeLine: _activeLine,
                    lineKeys: _lineKeys,
                    scrollController: _scrollController,
                    reduceMotion: widget.shellController.reduceMotion,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 16,
            right: 24,
            child: Tooltip(
              message: 'Close full lyrics',
              child: IconButton(
                key: const Key('expanded-lyrics-close'),
                onPressed: widget.shellController.closeExpandedLyrics,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                iconSize: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetForCurrentTrack() {
    final track = widget.playerController.currentTrack;
    _trackId = track.id;
    _lineKeys = List<GlobalKey>.generate(
      track.lyrics.length,
      (_) => GlobalKey(),
    );
    _activeLine = _activeLineFor(track);
  }

  void _syncLyrics() {
    final track = widget.playerController.currentTrack;
    if (track.id != _trackId) {
      setState(_resetForCurrentTrack);
      _scheduleScroll();
      return;
    }

    final activeLine = _activeLineFor(track);
    if (activeLine == _activeLine) {
      return;
    }

    setState(() => _activeLine = activeLine);
    _scheduleScroll();
  }

  int _activeLineFor(Track track) {
    if (track.lyrics.isEmpty || track.durationSeconds <= 0) {
      return 0;
    }
    return (widget.playerController.positionSeconds /
            track.durationSeconds *
            track.lyrics.length)
        .floor()
        .clamp(0, track.lyrics.length - 1)
        .toInt();
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveLine());
  }

  void _scrollToActiveLine() {
    if (!mounted || _lineKeys.isEmpty) {
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
}

class _TrackSummary extends StatelessWidget {
  const _TrackSummary({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
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
              assetPath: track.artworkAsset,
              semanticLabel: '${track.album} artwork',
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(track.title, style: Theme.of(context).textTheme.headlineMedium),
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

class _LyricsScroller extends StatelessWidget {
  const _LyricsScroller({
    required this.lines,
    required this.activeLine,
    required this.lineKeys,
    required this.scrollController,
    required this.reduceMotion,
  });

  final List<String> lines;
  final int activeLine;
  final List<GlobalKey> lineKeys;
  final ScrollController scrollController;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Lyrics', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
        Expanded(
          child: Scrollbar(
            controller: scrollController,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.only(right: 24, bottom: 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List<Widget>.generate(lines.length, (index) {
                  final isActive = index == activeLine;
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
                      child: Text(lines[index]),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
