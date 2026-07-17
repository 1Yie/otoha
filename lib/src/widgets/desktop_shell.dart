import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../state/app_locale_controller.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/offline_library_controller.dart';
import '../state/youtube_library_controller.dart';
import '../workspaces/workspace_views.dart';
import 'player_bar.dart';
import 'expanded_lyrics.dart';
import 'right_panel.dart';
import 'sidebar.dart';
import 'title_bar.dart';
import 'video_playback_overlay.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    required this.workspaceController,
    required this.playerController,
    required this.shellController,
    required this.focusNode,
    required this.youtubeLibraryController,
    required this.offlineLibraryController,
    required this.localeController,
    super.key,
  });

  final WorkspaceController workspaceController;
  final PlayerController playerController;
  final ShellController shellController;
  final FocusNode focusNode;
  final YouTubeLibraryController youtubeLibraryController;
  final OfflineLibraryController offlineLibraryController;
  final AppLocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.escape):
            shellController.closeTopmostOverlay,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            workspaceController.goBack,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            workspaceController.goForward,
      },
      child: Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: _handlePlaybackShortcut,
        child: Scaffold(
          body: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  DesktopTitleBar(
                    workspaceController: workspaceController,
                    shellController: shellController,
                    youtubeLibraryController: youtubeLibraryController,
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        AnimatedBuilder(
                          animation: shellController,
                          builder: (context, _) {
                            return AppSidebar(
                              workspaceController: workspaceController,
                              reduceMotion: shellController.reduceMotion,
                            );
                          },
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: ClipRect(
                            key: const Key('workspace-clip'),
                            child: _WorkspaceRegion(
                              workspaceController: workspaceController,
                              playerController: playerController,
                              shellController: shellController,
                              youtubeLibraryController:
                                  youtubeLibraryController,
                              offlineLibraryController:
                                  offlineLibraryController,
                              localeController: localeController,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  MusicPlayerBar(
                    playerController: playerController,
                    shellController: shellController,
                    offlineLibraryController: offlineLibraryController,
                    youtubeLibraryController: youtubeLibraryController,
                  ),
                ],
              ),
              Positioned(
                top: AppMetrics.titleBarHeight,
                right: 0,
                bottom: AppMetrics.playerHeight,
                child: AnimatedBuilder(
                  animation: shellController,
                  builder: (context, _) {
                    return RightPanelHost(
                      activePanel: shellController.activePanel,
                      playerController: playerController,
                      shellController: shellController,
                      youtubeLibraryController: youtubeLibraryController,
                      reduceMotion: shellController.reduceMotion,
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: _ExpandedMediaTransition(
                  playerController: playerController,
                  shellController: shellController,
                  youtubeLibraryController: youtubeLibraryController,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _handlePlaybackShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        _focusedControlConsumes(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        playerController.togglePlaying();
      case LogicalKeyboardKey.arrowLeft:
        playerController.previous();
      case LogicalKeyboardKey.arrowRight:
        playerController.next();
      case LogicalKeyboardKey.slash:
        playerController.cycleRepeatMode();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _openSearch() {
    shellController.closeExpandedLyrics();
    workspaceController.navigateTo(WorkspacePage.search);
  }

  bool _focusedControlConsumes(LogicalKeyboardKey key) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    var consumes = _widgetConsumesKey(focusContext.widget, key);
    focusContext.visitAncestorElements((element) {
      consumes = consumes || _widgetConsumesKey(element.widget, key);
      return !consumes;
    });
    return consumes;
  }

  bool _widgetConsumesKey(Widget widget, LogicalKeyboardKey key) {
    if (widget is EditableText) {
      return true;
    }
    if (key == LogicalKeyboardKey.space &&
        (widget is ButtonStyleButton ||
            widget is IconButton ||
            widget is InkWell ||
            widget is Checkbox ||
            widget is Switch)) {
      return true;
    }
    return (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        widget is Slider;
  }
}

class _ExpandedMediaTransition extends StatefulWidget {
  const _ExpandedMediaTransition({
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
  });

  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  State<_ExpandedMediaTransition> createState() =>
      _ExpandedMediaTransitionState();
}

class _ExpandedMediaTransitionState extends State<_ExpandedMediaTransition>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 280);

  late final AnimationController _controller;
  late final Animation<Offset> _position;
  Track? _presentedTrack;
  bool _targetOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener(_handleAnimationStatus);
    _position = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    widget.shellController.addListener(_syncPresentation);
    widget.playerController.addListener(_syncPresentation);
    _targetOpen = _shouldOpen;
    if (_targetOpen) {
      _presentedTrack = widget.playerController.currentTrack;
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _ExpandedMediaTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shellController != widget.shellController) {
      oldWidget.shellController.removeListener(_syncPresentation);
      widget.shellController.addListener(_syncPresentation);
    }
    if (oldWidget.playerController != widget.playerController) {
      oldWidget.playerController.removeListener(_syncPresentation);
      widget.playerController.addListener(_syncPresentation);
    }
    _syncPresentation();
  }

  @override
  void dispose() {
    widget.shellController.removeListener(_syncPresentation);
    widget.playerController.removeListener(_syncPresentation);
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  bool get _shouldOpen =>
      widget.shellController.isExpandedLyricsOpen &&
      widget.playerController.currentTrack != null;

  void _syncPresentation() {
    if (!mounted) {
      return;
    }
    final shouldOpen = _shouldOpen;
    final track = widget.playerController.currentTrack;
    final wasOpen = _targetOpen;
    final previousTrack = _presentedTrack;
    _targetOpen = shouldOpen;

    var mediaKindChanged = false;
    if (shouldOpen && track != null) {
      mediaKindChanged =
          previousTrack != null && previousTrack.isVideo != track.isVideo;
      final keepOutgoingVideo =
          previousTrack?.isVideo == true && !track.isVideo;
      if (!keepOutgoingVideo && !identical(previousTrack, track)) {
        setState(() => _presentedTrack = track);
      }
    }

    if (widget.shellController.reduceMotion) {
      _controller.value = shouldOpen ? 1 : 0;
      if (!shouldOpen && _presentedTrack != null) {
        setState(() => _presentedTrack = null);
      }
      return;
    }

    _controller.duration = _duration;
    if (shouldOpen) {
      if (!wasOpen || mediaKindChanged) {
        _controller.forward(from: 0);
      } else if (!_controller.isCompleted) {
        _controller.forward();
      }
      return;
    }
    if (_presentedTrack != null && !_controller.isDismissed) {
      _controller.reverse();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed ||
        _targetOpen ||
        _presentedTrack == null ||
        !mounted) {
      return;
    }
    setState(() => _presentedTrack = null);
  }

  @override
  Widget build(BuildContext context) {
    final track = _presentedTrack;
    if (track == null) {
      return const SizedBox(key: ValueKey<String>('no-expanded-media'));
    }
    return ClipRect(
      child: IgnorePointer(
        ignoring: !_targetOpen,
        child: SlideTransition(
          key: const Key('expanded-media-slide'),
          position: _position,
          child: track.isVideo
              ? VideoPlaybackOverlay(
                  key: const ValueKey<String>('expanded-video'),
                  track: track,
                  playerController: widget.playerController,
                  shellController: widget.shellController,
                  videoController: widget.playerController.videoController,
                )
              : ExpandedLyricsOverlay(
                  key: const ValueKey<String>('expanded-lyrics'),
                  playerController: widget.playerController,
                  shellController: widget.shellController,
                  youtubeLibraryController: widget.youtubeLibraryController,
                ),
        ),
      ),
    );
  }
}

class _WorkspaceRegion extends StatelessWidget {
  const _WorkspaceRegion({
    required this.workspaceController,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    required this.offlineLibraryController,
    required this.localeController,
  });

  final WorkspaceController workspaceController;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;
  final OfflineLibraryController offlineLibraryController;
  final AppLocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        workspaceController,
        shellController,
        youtubeLibraryController,
        offlineLibraryController,
        localeController,
      ]),
      builder: (context, _) {
        final duration = shellController.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200);
        return AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOut,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.015, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<WorkspacePage>(workspaceController.current),
            child: WorkspaceView(
              page: workspaceController.current,
              workspaceController: workspaceController,
              playerController: playerController,
              shellController: shellController,
              youtubeLibraryController: youtubeLibraryController,
              offlineLibraryController: offlineLibraryController,
              localeController: localeController,
            ),
          ),
        );
      },
    );
  }
}
