import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../app/youtube_library_error_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
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
                    _title(l10n),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Tooltip(
                  message: l10n.closePanel,
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

  String _title(AppLocalizations l10n) => switch (panel) {
    SidePanel.queue => l10n.queue,
    SidePanel.devices => l10n.outputDevice,
    SidePanel.comments => l10n.comments,
    SidePanel.account => l10n.youtubeMusic,
  };

  Widget _body(BuildContext context) => switch (panel) {
    SidePanel.queue => _QueuePanel(playerController: playerController),
    SidePanel.devices => _DevicesPanel(playerController: playerController),
    SidePanel.comments => _CommentsPanel(
      playerController: playerController,
      controller: youtubeLibraryController,
    ),
    SidePanel.account => AccountPanel(controller: youtubeLibraryController),
  };
}

class _CommentsPanel extends StatefulWidget {
  const _CommentsPanel({
    required this.playerController,
    required this.controller,
  });

  final PlayerController playerController;
  final YouTubeLibraryController controller;

  @override
  State<_CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends State<_CommentsPanel> {
  final TextEditingController _draftController = TextEditingController();
  String? _loadedVideoId;

  @override
  void initState() {
    super.initState();
    _draftController.addListener(_handleDraftChanged);
    widget.playerController.addListener(_syncTrack);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTrack());
  }

  @override
  void didUpdateWidget(covariant _CommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerController != widget.playerController) {
      oldWidget.playerController.removeListener(_syncTrack);
      widget.playerController.addListener(_syncTrack);
      _loadedVideoId = null;
      _syncTrack();
    }
  }

  @override
  void dispose() {
    widget.playerController.removeListener(_syncTrack);
    _draftController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    super.dispose();
  }

  String? get _videoId => widget.playerController.currentTrack?.youtubeVideoId;

  void _syncTrack() {
    final videoId = _videoId;
    if (_loadedVideoId == videoId) {
      return;
    }
    _loadedVideoId = videoId;
    _draftController.clear();
    if (videoId != null && widget.controller.isSignedIn) {
      unawaited(widget.controller.loadComments(videoId));
    }
  }

  void _handleDraftChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _postComment() async {
    final videoId = _videoId;
    if (videoId == null) {
      return;
    }
    final posted = await widget.controller.postComment(
      videoId,
      _draftController.text,
    );
    if (posted && mounted) {
      _draftController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.playerController,
        widget.controller,
      ]),
      builder: (context, _) {
        final videoId = _videoId;
        if (videoId == null || !widget.controller.isSignedIn) {
          return Center(
            key: const Key('panel-comments-unavailable'),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.commentsUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: OtohaColors.mutedText),
              ),
            ),
          );
        }

        final comments = widget.controller.comments;
        final isLoading =
            widget.controller.isLoadingComments &&
            widget.controller.commentsVideoId == videoId;
        final canPost =
            _draftController.text.trim().isNotEmpty &&
            !widget.controller.isPostingComment &&
            !widget.controller.isAccountWriteCoolingDown;
        return Column(
          children: <Widget>[
            Expanded(
              child: isLoading && comments.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : comments.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noComments,
                        style: const TextStyle(color: OtohaColors.mutedText),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('panel-comments-list'),
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      itemCount: comments.length,
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: OtohaColors.surfaceRaised,
                              foregroundImage: comment.avatarUrl == null
                                  ? null
                                  : NetworkImage(comment.avatarUrl!),
                              onForegroundImageError: (_, _) {},
                              child: comment.avatarUrl == null
                                  ? const Icon(
                                      Icons.person_rounded,
                                      size: 18,
                                      color: OtohaColors.accent,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    comment.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  if (comment.publishedTime case final time?
                                      when time.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      time,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    comment.text,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (widget.controller.commentErrorMessage case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  localizeYouTubeLibraryError(error, l10n),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('panel-comment-input'),
                      controller: _draftController,
                      maxLength: 10000,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: l10n.writeComment),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: l10n.postComment,
                    child: IconButton(
                      key: const Key('panel-comment-post'),
                      onPressed: canPost
                          ? () => unawaited(_postComment())
                          : null,
                      icon: widget.controller.isPostingComment
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playerController,
      builder: (context, _) {
        if (playerController.queue.isEmpty) {
          return Center(
            key: const Key('panel-queue-empty'),
            child: Text(
              AppLocalizations.of(context)!.queueEmpty,
              style: const TextStyle(color: OtohaColors.mutedText),
            ),
          );
        }
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
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      borderRadius: const BorderRadius.all(Radius.circular(AppMetrics.radius)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(8),
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
                      semanticLabel: l10n.artwork(track.album),
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
                          color: selected
                              ? OtohaColors.accent
                              : OtohaColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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
                ),
                Text(
                  formatDuration(track.durationSeconds),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                onTap: onPressed,
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

class _DevicesPanel extends StatelessWidget {
  const _DevicesPanel({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: playerController,
      builder: (context, _) {
        final devices = playerController.outputDevices;
        if (devices.isEmpty) {
          return Center(
            key: const Key('panel-devices-unavailable'),
            child: Text(l10n.noAudioOutputDevices),
          );
        }
        return ListView.separated(
          key: const Key('panel-devices'),
          padding: const EdgeInsets.all(16),
          itemCount:
              devices.length + (playerController.hasOutputDeviceError ? 1 : 0),
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == devices.length) {
              return Text(
                l10n.changeOutputDeviceError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              );
            }
            final device = devices[index];
            final selected =
                device.id == playerController.selectedOutputDevice?.id;
            final label = device.isSystemDefault
                ? l10n.systemDefault
                : device.description.isEmpty
                ? device.id
                : device.description;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: playerController.isSelectingOutputDevice
                    ? null
                    : () => playerController.selectOutputDevice(device),
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
                      Expanded(child: Text(label)),
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
