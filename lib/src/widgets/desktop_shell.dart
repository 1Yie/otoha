import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../state/app_locale_controller.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/offline_library_controller.dart';
import '../state/youtube_library_controller.dart';
import '../workspaces/workspace_views.dart';
import 'player_bar.dart';
import 'expanded_lyrics.dart';
import 'right_panel.dart';
import 'search_palette.dart';
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
            shellController.openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            shellController.openSearch,
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: shellController,
                  builder: (context, _) {
                    final duration = shellController.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220);
                    return AnimatedSwitcher(
                      duration: duration,
                      reverseDuration: duration,
                      transitionBuilder: (child, animation) {
                        return SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(0, 1),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                          child: child,
                        );
                      },
                      child:
                          shellController.isExpandedLyricsOpen &&
                              playerController.currentTrack != null
                          ? playerController.currentTrack!.isVideo
                                ? VideoPlaybackOverlay(
                                    key: const ValueKey<String>(
                                      'expanded-video',
                                    ),
                                    track: playerController.currentTrack!,
                                    playerController: playerController,
                                    shellController: shellController,
                                    videoController:
                                        playerController.videoController,
                                  )
                                : ExpandedLyricsOverlay(
                                    key: const ValueKey<String>(
                                      'expanded-lyrics',
                                    ),
                                    playerController: playerController,
                                    shellController: shellController,
                                    youtubeLibraryController:
                                        youtubeLibraryController,
                                  )
                          : const SizedBox(
                              key: ValueKey<String>('no-expanded-media'),
                            ),
                    );
                  },
                ),
              ),
              AnimatedBuilder(
                animation: shellController,
                builder: (context, _) {
                  if (!shellController.isSearchOpen) {
                    return const SizedBox.shrink();
                  }
                  return SearchPalette(
                    workspaceController: workspaceController,
                    playerController: playerController,
                    shellController: shellController,
                    youtubeLibraryController: youtubeLibraryController,
                    reduceMotion: shellController.reduceMotion,
                  );
                },
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
        shellController.isSearchOpen ||
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
