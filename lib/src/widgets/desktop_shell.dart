import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../workspaces/workspace_views.dart';
import 'player_bar.dart';
import 'expanded_lyrics.dart';
import 'right_panel.dart';
import 'search_palette.dart';
import 'sidebar.dart';
import 'title_bar.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    required this.workspaceController,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    super.key,
  });

  final WorkspaceController workspaceController;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

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
        autofocus: true,
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
                          child: _WorkspaceRegion(
                            workspaceController: workspaceController,
                            playerController: playerController,
                            shellController: shellController,
                            youtubeLibraryController: youtubeLibraryController,
                          ),
                        ),
                      ],
                    ),
                  ),
                  MusicPlayerBar(
                    playerController: playerController,
                    shellController: shellController,
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
                top: AppMetrics.titleBarHeight,
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
                      child: shellController.isExpandedLyricsOpen
                          ? ExpandedLyricsOverlay(
                              key: const ValueKey<String>('expanded-lyrics'),
                              playerController: playerController,
                              shellController: shellController,
                            )
                          : const SizedBox(
                              key: ValueKey<String>('no-expanded-lyrics'),
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
}

class _WorkspaceRegion extends StatelessWidget {
  const _WorkspaceRegion({
    required this.workspaceController,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
  });

  final WorkspaceController workspaceController;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        workspaceController,
        shellController,
        youtubeLibraryController,
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
            ),
          ),
        );
      },
    );
  }
}
