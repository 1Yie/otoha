import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/app_locale_controller.dart';
import '../state/youtube_library_controller.dart';
import '../state/offline_library_controller.dart';
import '../widgets/artwork_image.dart';
import 'offline_library_workspace.dart';
import 'offline_playlists_workspace.dart';
import 'search_workspace.dart';
import 'youtube_feed_workspace.dart';
import 'youtube_history_workspace.dart';
import 'youtube_library_workspace.dart';

class WorkspaceView extends StatelessWidget {
  const WorkspaceView({
    required this.page,
    required this.workspaceController,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    required this.offlineLibraryController,
    required this.localeController,
    super.key,
  });

  final WorkspacePage page;
  final WorkspaceController workspaceController;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;
  final OfflineLibraryController offlineLibraryController;
  final AppLocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return switch (page) {
      WorkspacePage.home => YouTubeFeedWorkspace(
        kind: YouTubeFeedKind.home,
        playerController: playerController,
        shellController: shellController,
        youtubeLibraryController: youtubeLibraryController,
      ),
      WorkspacePage.search => SearchWorkspace(
        workspaceController: workspaceController,
        playerController: playerController,
        shellController: shellController,
        youtubeLibraryController: youtubeLibraryController,
      ),
      WorkspacePage.explore => YouTubeFeedWorkspace(
        kind: YouTubeFeedKind.explore,
        playerController: playerController,
        shellController: shellController,
        youtubeLibraryController: youtubeLibraryController,
      ),
      WorkspacePage.library => LibraryWorkspace(
        playerController: playerController,
        shellController: shellController,
        youtubeLibraryController: youtubeLibraryController,
      ),
      WorkspacePage.history => YouTubeHistoryWorkspace(
        controller: youtubeLibraryController,
        playerController: playerController,
        shellController: shellController,
      ),
      WorkspacePage.downloads => OfflineLibraryWorkspace(
        controller: offlineLibraryController,
        playerController: playerController,
      ),
      WorkspacePage.playlists => OfflinePlaylistsWorkspace(
        controller: offlineLibraryController,
        playerController: playerController,
      ),
      WorkspacePage.settings => SettingsWorkspace(
        shellController: shellController,
        localeController: localeController,
        offlineLibraryController: offlineLibraryController,
      ),
    };
  }
}

class LibraryWorkspace extends StatelessWidget {
  const LibraryWorkspace({
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
    super.key,
  });

  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  Widget build(BuildContext context) {
    return YouTubeLibraryWorkspace(
      controller: youtubeLibraryController,
      playerController: playerController,
      shellController: shellController,
    );
  }
}

class SettingsWorkspace extends StatelessWidget {
  const SettingsWorkspace({
    required this.shellController,
    required this.localeController,
    required this.offlineLibraryController,
    super.key,
  });

  final ShellController shellController;
  final AppLocaleController localeController;
  final OfflineLibraryController offlineLibraryController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _WorkspaceScroller(
      children: <Widget>[
        _PageHeading(title: l10n.settings, eyebrow: l10n.desktop),
        const SizedBox(height: 40),
        _SectionHeading(l10n.motion),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: shellController,
          builder: (context, _) {
            return Material(
              color: OtohaColors.surface,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppMetrics.radius),
              ),
              child: SwitchListTile.adaptive(
                key: const Key('reduce-motion-switch'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(l10n.reduceMotion),
                value: shellController.reduceMotion,
                onChanged: shellController.setReduceMotion,
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        _SectionHeading(l10n.language),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: localeController,
          builder: (context, _) {
            return Material(
              color: OtohaColors.surface,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppMetrics.radius),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(l10n.language),
                trailing: DropdownButton<Locale>(
                  key: const Key('language-selector'),
                  value: localeController.locale,
                  onChanged: (locale) {
                    if (locale == null) {
                      return;
                    }
                    localeController.select(locale);
                  },
                  items: <DropdownMenuItem<Locale>>[
                    DropdownMenuItem<Locale>(
                      value: const Locale('en'),
                      child: Text(l10n.english),
                    ),
                    DropdownMenuItem<Locale>(
                      value: const Locale('zh'),
                      child: Text(l10n.simplifiedChinese),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        _SectionHeading(l10n.downloads),
        const SizedBox(height: 16),
        _DownloadLocationSetting(controller: offlineLibraryController),
        const SizedBox(height: 32),
        _SectionHeading(l10n.about),
        const SizedBox(height: 16),
        const _AboutOtoha(),
        const SizedBox(height: 8),
        Material(
          color: OtohaColors.surface,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppMetrics.radius),
          ),
          child: ListTile(
            key: const Key('settings-open-source-licenses'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.policy_outlined),
            title: Text(l10n.licensesAndNotices),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (context) => _DesktopLicensePage(
                  applicationName: l10n.appTitle,
                  applicationIcon: Image.asset(
                    'assets/icon/icon.png',
                    width: 56,
                    height: 56,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopLicensePage extends StatelessWidget {
  const _DesktopLicensePage({
    required this.applicationName,
    required this.applicationIcon,
  });

  final String applicationName;
  final Widget applicationIcon;

  @override
  Widget build(BuildContext context) {
    final page = LicensePage(
      applicationName: applicationName,
      applicationIcon: applicationIcon,
    );
    const desktopPlatforms = <TargetPlatform>{
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    };
    if (kIsWeb || !desktopPlatforms.contains(defaultTargetPlatform)) {
      return page;
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        page,
        Positioned(
          top: 0,
          left: kToolbarHeight,
          right: 0,
          height: kToolbarHeight,
          child: GestureDetector(
            key: const Key('license-page-drag-area'),
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
          ),
        ),
      ],
    );
  }
}

class _DownloadLocationSetting extends StatefulWidget {
  const _DownloadLocationSetting({required this.controller});

  final OfflineLibraryController controller;

  @override
  State<_DownloadLocationSetting> createState() =>
      _DownloadLocationSettingState();
}

class _DownloadLocationSettingState extends State<_DownloadLocationSetting> {
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.initialize();
      if (mounted) {
        _textController.text = widget.controller.downloadDirectory ?? '';
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Material(
          color: OtohaColors.surface,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppMetrics.radius),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('download-directory-field'),
                    controller: _textController,
                    onSubmitted: widget.controller.setDownloadDirectory,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      labelText: l10n.downloadLocation,
                    ),
                  ),
                ),
                Tooltip(
                  message: l10n.saveDownloadLocation,
                  child: IconButton(
                    key: const Key('save-download-directory'),
                    onPressed: () => widget.controller.setDownloadDirectory(
                      _textController.text,
                    ),
                    icon: const Icon(Icons.check_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AboutOtoha extends StatefulWidget {
  const _AboutOtoha();

  @override
  State<_AboutOtoha> createState() => _AboutOtohaState();
}

class _AboutOtohaState extends State<_AboutOtoha> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        return Material(
          key: const Key('settings-about'),
          color: OtohaColors.surface,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppMetrics.radius),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(AppMetrics.radius),
              ),
              child: Image.asset(
                'assets/icon/icon.png',
                key: const Key('settings-about-icon'),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            title: const Text('Otoha'),
            subtitle: Text(
              version == null
                  ? l10n.versionUnavailable
                  : l10n.appVersion(version),
            ),
          ),
        );
      },
    );
  }
}

class AlbumGrid extends StatelessWidget {
  const AlbumGrid({required this.tracks, required this.onSelect, super.key});

  final List<Track> tracks;
  final ValueChanged<Track> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 184,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.76,
      ),
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _AlbumCard(track: track, onSelect: () => onSelect(track));
      },
    );
  }
}

class TrackList extends StatelessWidget {
  const TrackList({
    required this.tracks,
    required this.playerController,
    this.compact = false,
    super.key,
  });

  final List<Track> tracks;
  final PlayerController playerController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playerController,
      builder: (context, _) {
        return Column(
          children: tracks
              .map(
                (track) => _TrackRow(
                  track: track,
                  compact: compact,
                  selected: track == playerController.currentTrack,
                  onSelect: () => playerController.selectTrack(track),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _WorkspaceScroller extends StatelessWidget {
  const _WorkspaceScroller({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppMetrics.workspacePadding,
        AppMetrics.workspacePadding,
        AppMetrics.workspacePadding,
        56,
      ),
      children: children,
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.title, required this.eyebrow});

  final String title;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          eyebrow,
          style: const TextStyle(
            color: OtohaColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.displaySmall),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.track, required this.onSelect});

  final Track track;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      borderRadius: const BorderRadius.all(Radius.circular(AppMetrics.radius)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppMetrics.radius),
                  ),
                  child: SizedBox.expand(
                    child: ArtworkImage(
                      assetPath: track.artworkAsset,
                      semanticLabel: l10n.artwork(track.album),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                track.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onSelect,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppMetrics.radius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.compact,
    required this.selected,
    required this.onSelect,
  });

  final Track track;
  final bool compact;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final artworkSize = compact ? 40.0 : 48.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppMetrics.radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Container(
              height: compact ? 56 : 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppMetrics.radius),
                    ),
                    child: SizedBox(
                      width: artworkSize,
                      height: artworkSize,
                      child: ArtworkImage(
                        assetPath: track.artworkAsset,
                        semanticLabel: l10n.artwork(track.album),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? OtohaColors.accent
                                : OtohaColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${track.artist} - ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatDuration(track.durationSeconds),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: OtohaColors.accent.withValues(alpha: 0.10),
                  ),
                ),
              ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSelect,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppMetrics.radius),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatDuration(int seconds) => _formatDuration(seconds);

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final minutes = duration.inMinutes.toString();
  final remainingSeconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainingSeconds';
}
