import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../app/youtube_library_error_localizations.dart';
import '../models/youtube_library.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/artwork_image.dart';
import 'youtube_feed_workspace.dart';

typedef ChannelUrlLauncher = Future<bool> Function(Uri uri);
typedef ChannelTextCopier = Future<void> Function(String text);

class YouTubeChannelWorkspace extends StatelessWidget {
  const YouTubeChannelWorkspace({
    required this.controller,
    required this.playerController,
    required this.shellController,
    this.launchExternalUrl,
    this.copyText,
    super.key,
  });

  final YouTubeLibraryController controller;
  final PlayerController playerController;
  final ShellController shellController;
  final ChannelUrlLauncher? launchExternalUrl;
  final ChannelTextCopier? copyText;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isSignedIn) {
          return _SignedOutChannel(
            onSignIn: () => shellController.togglePanel(SidePanel.account),
          );
        }

        final collection = controller.selectedFeedCollection;
        if (collection?.source == 'channel') {
          return YouTubeFeedCollectionDetailView(
            detail: collection!,
            playerController: playerController,
            isSaved: controller.isAlbumSaved(collection.id),
            isSaving: controller.albumLibraryWriteId == collection.id,
            canToggleLibrary:
                controller.albumLibraryWriteId == null &&
                !controller.isAccountWriteCoolingDown,
            onToggleLibrary: () =>
                unawaited(controller.toggleAlbumLibrary(collection)),
            onBack: controller.closeFeedDetail,
          );
        }
        final podcast = controller.selectedPodcastShow;
        if (podcast?.source == 'channel') {
          return YouTubePodcastShowDetailView(
            detail: podcast!,
            loadingItemId: controller.loadingFeedItemId,
            isLoadingMore: controller.isLoadingMorePodcast,
            isSaved: controller.isPodcastSaved(podcast.id),
            isSaving: controller.podcastLibraryWriteId == podcast.id,
            canToggleLibrary:
                controller.podcastLibraryWriteId == null &&
                !controller.isAccountWriteCoolingDown,
            onBack: controller.closeFeedDetail,
            onLoadMore: controller.loadMorePodcastShow,
            onToggleLibrary: () =>
                unawaited(controller.togglePodcastLibrary(podcast)),
            onTap: _actionFor,
          );
        }
        final browse = controller.selectedFeedBrowse;
        if (browse?.source == 'channel') {
          return YouTubeFeedBrowseDetailView(
            detail: browse!,
            playerController: playerController,
            youtubeLibraryController: controller,
            loadingItemId: controller.loadingFeedItemId,
            reduceMotion: shellController.reduceMotion,
            onBack: controller.closeFeedDetail,
            onTap: _actionFor,
          );
        }

        final profile = controller.channelProfile;
        if (profile == null) {
          if (!controller.isLoadingChannel &&
              controller.channelErrorMessage == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(controller.loadChannelProfile());
            });
          }
          if (controller.channelErrorMessage != null) {
            return _ChannelLoadError(
              error: controller.channelErrorMessage!,
              onRetry: () => controller.loadChannelProfile(forceRefresh: true),
            );
          }
          return const Center(
            child: CircularProgressIndicator(
              key: Key('youtube-channel-loading'),
            ),
          );
        }

        return _ChannelContent(
          profile: profile,
          fallbackName: controller.profileName,
          loadingItemId: controller.loadingFeedItemId,
          reduceMotion: shellController.reduceMotion,
          feedError: controller.feedActionErrorMessage,
          onFeedItem: _actionFor,
          onEdit: () => _openStudio(context, profile),
          onShare: () => _shareChannel(context, profile),
          onSignOut: controller.signOut,
        );
      },
    );
  }

  VoidCallback? _actionFor(
    YouTubeFeedItem item, [
    List<YouTubeFeedItem> queueItems = const <YouTubeFeedItem>[],
  ]) {
    if (item.isCollection) {
      return () => unawaited(_openCollection(item));
    }
    if (item.isBrowsable) {
      return () =>
          unawaited(controller.openFeedBrowse(item, source: 'channel'));
    }
    if (item.isPlayable) {
      return () => unawaited(
        playYouTubeFeedQueue(
          selectedItem: item,
          queueItems: queueItems,
          youtubeLibraryController: controller,
          playerController: playerController,
        ),
      );
    }
    return null;
  }

  Future<void> _openCollection(YouTubeFeedItem item) async {
    final tracks = await controller.openFeedCollection(item, source: 'channel');
    if (tracks.length == 1 && item.itemType != 'album') {
      playerController.playTracks([
        asSimulatedYouTubeTrack(
          tracks.single,
          artworkFallback: item.thumbnailUrl,
          albumFallback: item.title,
          artistFallback: item.artists,
        ),
      ]);
    }
  }

  Future<void> _openStudio(
    BuildContext context,
    YouTubeChannelProfile profile,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri.tryParse(profile.studioUrl ?? '');
    try {
      final opened =
          uri != null &&
          _isAllowedYouTubeUri(uri) &&
          await (launchExternalUrl ?? _launchExternally)(uri);
      if (opened) {
        return;
      }
    } on Object {
      // The user-facing failure below is enough for platform launch errors.
    }
    if (context.mounted) {
      _showMessage(context, l10n.channelOpenFailed);
    }
  }

  Future<void> _shareChannel(
    BuildContext context,
    YouTubeChannelProfile profile,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final value = profile.channelUrl;
    final uri = Uri.tryParse(value ?? '');
    if (value == null || uri == null || !_isAllowedYouTubeUri(uri)) {
      _showMessage(context, l10n.channelLinkCopyFailed);
      return;
    }
    try {
      await (copyText ?? _copyChannelText)(value);
      if (context.mounted) {
        _showMessage(context, l10n.channelLinkCopied);
      }
    } on Object {
      if (context.mounted) {
        _showMessage(context, l10n.channelLinkCopyFailed);
      }
    }
  }
}

class _SignedOutChannel extends StatelessWidget {
  const _SignedOutChannel({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      key: const Key('youtube-channel-signed-out'),
      child: FilledButton.icon(
        key: const Key('youtube-channel-sign-in'),
        onPressed: onSignIn,
        icon: const Icon(Icons.login_rounded),
        label: Text(l10n.signInToYouTubeMusic),
      ),
    );
  }
}

class _ChannelLoadError extends StatelessWidget {
  const _ChannelLoadError({required this.error, required this.onRetry});

  final YouTubeLibraryError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      key: const Key('youtube-channel-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: OtohaColors.mutedText,
          ),
          const SizedBox(height: 16),
          Text(localizeYouTubeLibraryError(error, l10n)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('youtube-channel-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.loadAgain),
          ),
        ],
      ),
    );
  }
}

class _ChannelContent extends StatefulWidget {
  const _ChannelContent({
    required this.profile,
    required this.fallbackName,
    required this.loadingItemId,
    required this.reduceMotion,
    required this.feedError,
    required this.onFeedItem,
    required this.onEdit,
    required this.onShare,
    required this.onSignOut,
  });

  final YouTubeChannelProfile profile;
  final String? fallbackName;
  final String? loadingItemId;
  final bool reduceMotion;
  final YouTubeLibraryError? feedError;
  final VoidCallback? Function(
    YouTubeFeedItem item, [
    List<YouTubeFeedItem> queueItems,
  ])
  onFeedItem;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final Future<void> Function() onSignOut;

  @override
  State<_ChannelContent> createState() => _ChannelContentState();
}

class _ChannelContentState extends State<_ChannelContent> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayName =
        widget.profile.displayName ?? widget.fallbackName ?? l10n.youtubeMusic;
    return Scrollbar(
      key: const Key('youtube-channel-scrollbar'),
      controller: _scrollController,
      child: CustomScrollView(
        key: const Key('youtube-channel-workspace'),
        controller: _scrollController,
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _ChannelHeader(
              profile: widget.profile,
              displayName: displayName,
              onEdit: widget.onEdit,
              onShare: widget.onShare,
              onSignOut: widget.onSignOut,
            ),
          ),
          if (widget.feedError != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                24,
                AppMetrics.workspacePadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  localizeYouTubeLibraryError(widget.feedError!, l10n),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (widget.profile.channelSections.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppMetrics.workspacePadding,
                32,
                AppMetrics.workspacePadding,
                8,
              ),
              sliver: SliverToBoxAdapter(child: _ChannelContentUnavailable()),
            )
          else
            SliverList.builder(
              itemCount: widget.profile.channelSections.length,
              itemBuilder: (context, index) {
                final section = widget.profile.channelSections[index];
                return YouTubeFeedSectionView(
                  key: ValueKey<String>('channel:${section.title}:$index'),
                  section: section,
                  sectionIndex: index,
                  loadingItemId: widget.loadingItemId,
                  reduceMotion: widget.reduceMotion,
                  onTap: (item) => widget.onFeedItem(item, section.items),
                );
              },
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.workspacePadding,
              40,
              AppMetrics.workspacePadding,
              20,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                l10n.yourRecap,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          if (!widget.profile.recapAvailable)
            const SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: AppMetrics.workspacePadding,
              ),
              sliver: SliverToBoxAdapter(child: _RecapUnavailable()),
            )
          else ...<Widget>[
            if (widget.profile.recapHighlights.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.workspacePadding,
                ),
                sliver: SliverToBoxAdapter(
                  child: _RecapHighlights(
                    items: widget.profile.recapHighlights,
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: widget.profile.recapSections.length,
              itemBuilder: (context, index) {
                final section = widget.profile.recapSections[index];
                return YouTubeFeedSectionView(
                  key: ValueKey<String>('recap:${section.title}:$index'),
                  section: section,
                  sectionIndex: widget.profile.channelSections.length + index,
                  loadingItemId: widget.loadingItemId,
                  reduceMotion: widget.reduceMotion,
                  onTap: (item) => widget.onFeedItem(item, section.items),
                );
              },
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.profile,
    required this.displayName,
    required this.onEdit,
    required this.onShare,
    required this.onSignOut,
  });

  final YouTubeChannelProfile profile;
  final String displayName;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasBanner = profile.bannerUrl?.isNotEmpty ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final height = hasBanner
            ? compact
                  ? 280.0
                  : 224.0
            : compact
            ? 256.0
            : 184.0;
        final identity = _ChannelIdentity(
          profile: profile,
          displayName: displayName,
          compact: compact,
        );
        final actions = _ChannelActions(
          onEdit: onEdit,
          onShare: onShare,
          onSignOut: onSignOut,
        );
        return SizedBox(
          key: const Key('youtube-channel-banner'),
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (hasBanner)
                _ChannelImage(
                  path: profile.bannerUrl,
                  semanticLabel: l10n.backgroundArtwork(displayName),
                  fallbackIcon: Icons.graphic_eq_rounded,
                )
              else
                const ColoredBox(color: OtohaColors.surfaceRaised),
              if (hasBanner) const ColoredBox(color: Color(0x66000000)),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 24 : AppMetrics.workspacePadding,
                  24,
                  compact ? 24 : AppMetrics.workspacePadding,
                  24,
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: compact
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            identity,
                            const SizedBox(height: 16),
                            actions,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Expanded(child: identity),
                            const SizedBox(width: 24),
                            actions,
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChannelIdentity extends StatelessWidget {
  const _ChannelIdentity({
    required this.profile,
    required this.displayName,
    required this.compact,
  });

  final YouTubeChannelProfile profile;
  final String displayName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        ClipOval(
          child: SizedBox(
            key: const Key('youtube-channel-avatar'),
            width: compact ? 88 : 112,
            height: compact ? 88 : 112,
            child: _ChannelImage(
              path: profile.avatarUrl,
              semanticLabel: AppLocalizations.of(
                context,
              )!.profileImage(displayName),
              fallbackIcon: Icons.person_rounded,
            ),
          ),
        ),
        SizedBox(width: compact ? 16 : 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              if (profile.handle != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  profile.handle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: OtohaColors.text.withValues(alpha: 0.82),
                  ),
                ),
              ],
              if (profile.subscriberText != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  profile.subscriberText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: OtohaColors.text.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

enum _ChannelMenuAction { signOut }

class _ChannelActions extends StatelessWidget {
  const _ChannelActions({
    required this.onEdit,
    required this.onShare,
    required this.onSignOut,
  });

  final VoidCallback onEdit;
  final VoidCallback onShare;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        OutlinedButton.icon(
          key: const Key('youtube-channel-edit'),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: Text(l10n.editChannel),
          style: _actionStyle(),
        ),
        OutlinedButton.icon(
          key: const Key('youtube-channel-share'),
          onPressed: onShare,
          icon: const Icon(Icons.share_outlined),
          label: Text(l10n.shareChannel),
          style: _actionStyle(),
        ),
        PopupMenuButton<_ChannelMenuAction>(
          key: const Key('youtube-channel-menu'),
          tooltip: l10n.profile,
          icon: const Icon(Icons.more_vert_rounded),
          iconColor: OtohaColors.text,
          onSelected: (action) {
            if (action == _ChannelMenuAction.signOut) {
              unawaited(onSignOut());
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<_ChannelMenuAction>>[
            PopupMenuItem<_ChannelMenuAction>(
              value: _ChannelMenuAction.signOut,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.logout_rounded, size: 20),
                  const SizedBox(width: 12),
                  Text(l10n.signOut),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  ButtonStyle _actionStyle() => OutlinedButton.styleFrom(
    foregroundColor: OtohaColors.text,
    backgroundColor: OtohaColors.canvas.withValues(alpha: 0.88),
    side: BorderSide(color: OtohaColors.text.withValues(alpha: 0.48)),
  );
}

class _ChannelContentUnavailable extends StatelessWidget {
  const _ChannelContentUnavailable();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      key: const Key('youtube-channel-content-unavailable'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.music_off_outlined, color: OtohaColors.mutedText),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            l10n.channelContentUnavailable,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _RecapUnavailable extends StatelessWidget {
  const _RecapUnavailable();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      key: const Key('youtube-channel-recap-unavailable'),
      color: OtohaColors.surface,
      borderRadius: const BorderRadius.all(Radius.circular(AppMetrics.radius)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: <Widget>[
            const Icon(Icons.insights_outlined, color: OtohaColors.mutedText),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.recapUnavailable,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.recapUnavailableDescription,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecapHighlights extends StatelessWidget {
  const _RecapHighlights({required this.items});

  final List<YouTubeRecapHighlight> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          key: const Key('youtube-channel-recap-highlights'),
          spacing: 16,
          runSpacing: 16,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: width,
                height: 208,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppMetrics.radius),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _ChannelImage(
                        path: item.backgroundUrl ?? item.thumbnailUrl,
                        semanticLabel: item.title,
                        fallbackIcon: Icons.insights_rounded,
                      ),
                      const ColoredBox(color: Color(0x99000000)),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            if (item.strapline != null)
                              Text(
                                item.strapline!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (item.description != null) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(
                                item.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChannelImage extends StatelessWidget {
  const _ChannelImage({
    required this.path,
    required this.semanticLabel,
    required this.fallbackIcon,
  });

  final String? path;
  final String semanticLabel;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final value = path;
    if (value == null || value.isEmpty) {
      return ColoredBox(
        color: OtohaColors.surfaceRaised,
        child: Center(
          child: Icon(fallbackIcon, color: OtohaColors.accent, size: 32),
        ),
      );
    }
    return ArtworkImage(assetPath: value, semanticLabel: semanticLabel);
  }
}

bool _isAllowedYouTubeUri(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'youtube.com' || uri.host.endsWith('.youtube.com'));

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> _copyChannelText(String text) =>
    Clipboard.setData(ClipboardData(text: text));

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
