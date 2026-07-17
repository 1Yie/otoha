import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../state/desktop_shell_controllers.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.workspaceController,
    required this.reduceMotion,
    super.key,
  });

  final WorkspaceController workspaceController;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: AppMetrics.sidebarWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: AnimatedBuilder(
          animation: workspaceController,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _NavigationItem(
                  icon: Icons.home_outlined,
                  label: l10n.home,
                  key: const Key('sidebar-home'),
                  selected: workspaceController.current == WorkspacePage.home,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.home),
                ),
                const SizedBox(height: 8),
                _NavigationItem(
                  icon: Icons.explore_outlined,
                  label: l10n.explore,
                  key: const Key('sidebar-explore'),
                  selected:
                      workspaceController.current == WorkspacePage.explore,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.explore),
                ),
                const SizedBox(height: 8),
                _NavigationItem(
                  icon: Icons.library_music_outlined,
                  label: l10n.library,
                  key: const Key('sidebar-library'),
                  selected:
                      workspaceController.current == WorkspacePage.library,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.library),
                ),
                const SizedBox(height: 8),
                _NavigationItem(
                  icon: Icons.history_rounded,
                  label: l10n.history,
                  key: const Key('sidebar-history'),
                  selected:
                      workspaceController.current == WorkspacePage.history,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.history),
                ),
                const Spacer(),
                Text(
                  l10n.yourSpace,
                  style: TextStyle(
                    color: OtohaColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _NavigationItem(
                  icon: Icons.download_outlined,
                  label: l10n.downloads,
                  key: const Key('sidebar-downloads'),
                  selected:
                      workspaceController.current == WorkspacePage.downloads,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.downloads),
                ),
                const SizedBox(height: 12),
                _NavigationItem(
                  icon: Icons.queue_music_outlined,
                  label: l10n.playlists,
                  key: const Key('sidebar-playlists'),
                  selected:
                      workspaceController.current == WorkspacePage.playlists,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.playlists),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppMetrics.radius),
          ),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? OtohaColors.surfaceRaised : Colors.transparent,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppMetrics.radius),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 20,
                  color: selected ? OtohaColors.accent : OtohaColors.mutedText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? OtohaColors.text
                          : OtohaColors.mutedText,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
