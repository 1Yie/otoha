import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../app/theme.dart';
import '../app/youtube_library_error_localizations.dart';
import '../state/youtube_library_controller.dart';

class AccountPanel extends StatefulWidget {
  const AccountPanel({required this.controller, super.key});

  final YouTubeLibraryController controller;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  final TextEditingController _cookieController = TextEditingController();

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Padding(
          key: const Key('panel-account'),
          padding: const EdgeInsets.all(24),
          child: switch (widget.controller.status) {
            YouTubeAccountStatus.restoring => const Center(
              child: CircularProgressIndicator(),
            ),
            YouTubeAccountStatus.authorizing => const Center(
              child: CircularProgressIndicator(),
            ),
            YouTubeAccountStatus.signedIn => _ConnectedView(
              controller: widget.controller,
            ),
            YouTubeAccountStatus.signedOut ||
            YouTubeAccountStatus.error => _buildSignedOut(context),
          },
        );
      },
    );
  }

  Widget _buildSignedOut(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.youtubeMusicSignIn,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('youtube-cookie-field'),
          controller: _cookieController,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.youtubeCookieHeader,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('youtube-cookie-submit'),
          onPressed: _cookieController.text.trim().isEmpty
              ? null
              : () =>
                    widget.controller.signInWithCookie(_cookieController.text),
          icon: const Icon(Icons.login_rounded),
          label: Text(l10n.signIn),
        ),
        if (widget.controller.errorMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            localizeYouTubeLibraryError(widget.controller.errorMessage!, l10n),
            key: const Key('youtube-auth-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.controller});

  final YouTubeLibraryController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      key: const Key('youtube-connected'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: SizedBox(
            key: const Key('youtube-account-avatar'),
            width: 64,
            height: 64,
            child: CircleAvatar(
              radius: 32,
              backgroundColor: OtohaColors.surfaceRaised,
              foregroundImage:
                  controller.profileAvatarUrl != null &&
                      controller.profileAvatarUrl!.isNotEmpty
                  ? NetworkImage(controller.profileAvatarUrl!)
                  : null,
              child: const Icon(
                Icons.person_rounded,
                color: OtohaColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          controller.profileName ??
              l10n.playlistCount(controller.playlists.length),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          l10n.fullYouTubeMusicSession,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const Key('youtube-library-sync'),
          onPressed: controller.isLoadingLibrary
              ? null
              : controller.loadPlaylists,
          icon: const Icon(Icons.sync_rounded),
          label: Text(l10n.syncLibrary),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('youtube-sign-out'),
          onPressed: controller.signOut,
          icon: const Icon(Icons.logout_rounded),
          label: Text(l10n.signOut),
        ),
      ],
    );
  }
}
