import 'package:flutter/material.dart';

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
                  label: 'Home',
                  key: const Key('sidebar-home'),
                  selected: workspaceController.current == WorkspacePage.home,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.home),
                ),
                const SizedBox(height: 8),
                _NavigationItem(
                  icon: Icons.explore_outlined,
                  label: 'Explore',
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
                  label: 'Library',
                  key: const Key('sidebar-library'),
                  selected:
                      workspaceController.current == WorkspacePage.library,
                  reduceMotion: reduceMotion,
                  onPressed: () =>
                      workspaceController.navigateTo(WorkspacePage.library),
                ),
                const Spacer(),
                const Text(
                  'YOUR SPACE',
                  style: TextStyle(
                    color: OtohaColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                const _QuietSidebarHint(
                  icon: Icons.download_outlined,
                  label: 'Downloads',
                ),
                const SizedBox(height: 12),
                const _QuietSidebarHint(
                  icon: Icons.queue_music_outlined,
                  label: 'Playlists',
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
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? OtohaColors.text : OtohaColors.mutedText,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

class _QuietSidebarHint extends StatelessWidget {
  const _QuietSidebarHint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: OtohaColors.mutedText),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(color: OtohaColors.mutedText, fontSize: 13),
        ),
      ],
    );
  }
}
