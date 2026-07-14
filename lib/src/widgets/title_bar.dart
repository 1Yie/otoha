import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    required this.workspaceController,
    required this.shellController,
    required this.youtubeLibraryController,
    super.key,
  });

  final WorkspaceController workspaceController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ColoredBox(
      color: OtohaColors.canvas,
      child: SizedBox(
        height: AppMetrics.titleBarHeight,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: _startDragging,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: workspaceController,
                builder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.graphic_eq_rounded,
                          color: OtohaColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.appTitle,
                          style: TextStyle(
                            color: OtohaColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 1,
                          height: 16,
                          color: OtohaColors.border,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          _workspaceLabel(workspaceController.current, l10n),
                          style: const TextStyle(
                            color: OtohaColors.mutedText,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 480,
                child: _SearchTrigger(onPressed: shellController.openSearch),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedBuilder(
                animation: workspaceController,
                builder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Tooltip(
                          message: l10n.back,
                          child: IconButton(
                            key: const Key('history-back'),
                            onPressed: workspaceController.canGoBack
                                ? workspaceController.goBack
                                : null,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        Tooltip(
                          message: l10n.forward,
                          child: IconButton(
                            key: const Key('history-forward'),
                            onPressed: workspaceController.canGoForward
                                ? workspaceController.goForward
                                : null,
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                        ),
                        Tooltip(
                          message: l10n.settings,
                          child: IconButton(
                            key: const Key('open-settings'),
                            onPressed: () => workspaceController.navigateTo(
                              WorkspacePage.settings,
                            ),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ),
                        Tooltip(
                          message: l10n.profile,
                          child: IconButton(
                            key: const Key('open-account'),
                            onPressed: () =>
                                shellController.togglePanel(SidePanel.account),
                            icon: AnimatedBuilder(
                              animation: youtubeLibraryController,
                              builder: (context, _) {
                                final avatarUrl =
                                    youtubeLibraryController.profileAvatarUrl;
                                return CircleAvatar(
                                  radius: 12,
                                  backgroundColor:
                                      youtubeLibraryController.isSignedIn
                                      ? OtohaColors.accent
                                      : OtohaColors.surfaceRaised,
                                  foregroundImage:
                                      avatarUrl != null && avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: Icon(
                                    youtubeLibraryController.isSignedIn
                                        ? Icons.person_rounded
                                        : Icons.person_outline_rounded,
                                    size: 15,
                                    color: youtubeLibraryController.isSignedIn
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : OtohaColors.mutedText,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        if (_isDesktopPlatform()) const _WindowControls(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _workspaceLabel(WorkspacePage page, AppLocalizations l10n) =>
      switch (page) {
        WorkspacePage.home => l10n.home,
        WorkspacePage.explore => l10n.explore,
        WorkspacePage.library => l10n.library,
        WorkspacePage.history => l10n.history,
        WorkspacePage.downloads => l10n.downloads,
        WorkspacePage.playlists => l10n.playlists,
        WorkspacePage.settings => l10n.settings,
      };

  void _startDragging(DragStartDetails details) {
    if (_isDesktopPlatform()) {
      windowManager.startDragging();
    }
  }
}

class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.searchShortcut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('search-trigger'),
          onTap: onPressed,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppMetrics.radius),
          ),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: OtohaColors.surfaceRaised,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppMetrics.radius),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: OtohaColors.mutedText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.searchYourMusic,
                    style: const TextStyle(
                      color: OtohaColors.mutedText,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Text(
                  'Ctrl K',
                  style: TextStyle(color: OtohaColors.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: <Widget>[
        Tooltip(
          message: l10n.minimize,
          child: IconButton(
            onPressed: windowManager.minimize,
            icon: const Icon(Icons.minimize_rounded),
          ),
        ),
        Tooltip(
          message: l10n.maximize,
          child: IconButton(
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            icon: const Icon(Icons.crop_square_rounded),
          ),
        ),
        Tooltip(
          message: l10n.close,
          child: IconButton(
            onPressed: windowManager.close,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }
}

bool _isDesktopPlatform() {
  return !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      };
}
