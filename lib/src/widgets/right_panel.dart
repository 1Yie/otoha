import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/catalog.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../workspaces/workspace_views.dart';
import 'account_panel.dart';
import 'artwork_image.dart';

class RightPanelHost extends StatefulWidget {
  const RightPanelHost({
    required this.activePanel,
    required this.playerController,
    required this.shellController,
    required this.reduceMotion,
    required this.youtubeLibraryController,
    super.key,
  });

  final SidePanel? activePanel;
  final PlayerController playerController;
  final ShellController shellController;
  final bool reduceMotion;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  State<RightPanelHost> createState() => _RightPanelHostState();
}

class _RightPanelHostState extends State<RightPanelHost> {
  SidePanel? _visiblePanel;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _visiblePanel = widget.activePanel;
    _isOpen = _visiblePanel != null;
  }

  @override
  void didUpdateWidget(covariant RightPanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activePanel != null) {
      _visiblePanel = widget.activePanel;
      _isOpen = true;
    } else if (oldWidget.activePanel != null) {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_visiblePanel == null) {
      return const SizedBox.shrink();
    }

    return AnimatedSlide(
      offset: _isOpen ? Offset.zero : const Offset(1, 0),
      duration: widget.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      onEnd: () {
        if (!_isOpen && mounted) {
          setState(() => _visiblePanel = null);
        }
      },
      child: SizedBox(
        width: AppMetrics.panelWidth,
        child: _PanelSurface(
          panel: _visiblePanel!,
          playerController: widget.playerController,
          shellController: widget.shellController,
          youtubeLibraryController: widget.youtubeLibraryController,
        ),
      ),
    );
  }
}

class _PanelSurface extends StatelessWidget {
  const _PanelSurface({
    required this.panel,
    required this.playerController,
    required this.shellController,
    required this.youtubeLibraryController,
  });

  final SidePanel panel;
  final PlayerController playerController;
  final ShellController shellController;
  final YouTubeLibraryController youtubeLibraryController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: OtohaColors.surface,
        border: Border(left: BorderSide(color: OtohaColors.border)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Tooltip(
                  message: 'Close panel',
                  child: IconButton(
                    onPressed: shellController.closePanel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  String get _title => switch (panel) {
    SidePanel.queue => 'Queue',
    SidePanel.lyrics => 'Lyrics',
    SidePanel.devices => 'Output device',
    SidePanel.account => 'YouTube Music',
  };

  Widget _body(BuildContext context) => switch (panel) {
    SidePanel.queue => _QueuePanel(playerController: playerController),
    SidePanel.lyrics => _LyricsPanel(playerController: playerController),
    SidePanel.devices => _DevicesPanel(shellController: shellController),
    SidePanel.account => AccountPanel(controller: youtubeLibraryController),
  };
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playerController,
      builder: (context, _) {
        return ListView.separated(
          key: const Key('panel-queue'),
          padding: const EdgeInsets.all(16),
          itemCount: playerController.queue.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final track = playerController.queue[index];
            return _QueueTrackRow(
              track: track,
              selected: track == playerController.currentTrack,
              onPressed: () => playerController.selectTrack(track),
            );
          },
        );
      },
    );
  }
}

class _QueueTrackRow extends StatelessWidget {
  const _QueueTrackRow({
    required this.track,
    required this.selected,
    required this.onPressed,
  });

  final Track track;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppMetrics.radius),
        ),
        child: Container(
          height: 64,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? OtohaColors.surfaceRaised : Colors.transparent,
            borderRadius: const BorderRadius.all(
              Radius.circular(AppMetrics.radius),
            ),
          ),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppMetrics.radius),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: ArtworkImage(
                    assetPath: track.artworkAsset,
                    semanticLabel: '${track.album} artwork',
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                        color: selected ? OtohaColors.accent : OtohaColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                formatDuration(track.durationSeconds),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playerController,
      builder: (context, _) {
        final track = playerController.currentTrack;
        return ListView(
          key: const Key('panel-lyrics'),
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(track.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(track.artist, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 32),
            ...track.lyrics.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: OtohaColors.text,
                    fontSize: 18,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DevicesPanel extends StatelessWidget {
  const _DevicesPanel({required this.shellController});

  final ShellController shellController;

  static const _devices = <String>[
    'This computer',
    'Studio Desk',
    'Living Room',
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shellController,
      builder: (context, _) {
        return ListView.separated(
          key: const Key('panel-devices'),
          padding: const EdgeInsets.all(16),
          itemCount: _devices.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final device = _devices[index];
            final selected = device == shellController.selectedDevice;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => shellController.selectDevice(device),
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppMetrics.radius),
                ),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: selected
                        ? OtohaColors.surfaceRaised
                        : Colors.transparent,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppMetrics.radius),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.speaker_outlined,
                        color: selected
                            ? OtohaColors.accent
                            : OtohaColors.mutedText,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Text(device)),
                      if (selected)
                        const Icon(
                          Icons.check_rounded,
                          color: OtohaColors.accent,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
