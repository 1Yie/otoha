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

  bool get _canSubmit => _cookieController.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) {
      return;
    }
    final cookie = _cookieController.text;
    // Clear the field before the request so the credential does not stay in widget state.
    _cookieController.clear();
    setState(() {});
    widget.controller.signInWithCookie(cookie);
  }

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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.youtubeMusicSignIn,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppMetrics.unit),
          _CookieGuide(l10n: l10n),
          const SizedBox(height: AppMetrics.unit * 2),
          TextField(
            key: const Key('youtube-cookie-field'),
            controller: _cookieController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.youtubeCookieHeader,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('youtube-cookie-submit'),
            onPressed: _canSubmit ? _submit : null,
            icon: const Icon(Icons.login_rounded),
            label: Text(l10n.signIn),
          ),
          if (widget.controller.errorMessage != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              localizeYouTubeLibraryError(
                widget.controller.errorMessage!,
                l10n,
              ),
              key: const Key('youtube-auth-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (widget.controller.errorDiagnostic != null) ...<Widget>[
              const SizedBox(height: 6),
              SelectableText(
                widget.controller.errorDiagnostic!,
                key: const Key('youtube-auth-diagnostic'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
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

class _CookieGuide extends StatelessWidget {
  const _CookieGuide({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, Widget)>[
      (l10n.youtubeCookieStep1, const _PrivateWindowArt()),
      (l10n.youtubeCookieStep2, const _NetworkPanelArt()),
      (l10n.youtubeCookieStep3, const _CookieHeaderArt()),
    ];
    return Column(
      key: const Key('youtube-cookie-steps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < steps.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: AppMetrics.unit),
          _GuideStep(
            number: index + 1,
            text: steps[index].$1,
            art: steps[index].$2,
          ),
        ],
      ],
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.text,
    required this.art,
  });

  final int number;
  final String text;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppMetrics.unit),
      decoration: BoxDecoration(
        color: OtohaColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        border: Border.all(color: OtohaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: OtohaColors.accent,
                  borderRadius: BorderRadius.circular(AppMetrics.radius),
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: OtohaColors.canvas,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppMetrics.unit),
              Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ],
          ),
          const SizedBox(height: AppMetrics.unit),
          art,
        ],
      ),
    );
  }
}

class _ArtFrame extends StatelessWidget {
  const _ArtFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      width: double.infinity,
      padding: const EdgeInsets.all(AppMetrics.unit),
      decoration: BoxDecoration(
        color: OtohaColors.canvas,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
      ),
      child: child,
    );
  }
}

class _PrivateWindowArt extends StatelessWidget {
  const _PrivateWindowArt();

  @override
  Widget build(BuildContext context) {
    return _ArtFrame(
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.visibility_off_rounded,
            color: OtohaColors.accent,
            size: 28,
          ),
          const SizedBox(width: AppMetrics.unit),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppMetrics.unit),
              decoration: BoxDecoration(
                color: OtohaColors.surface,
                borderRadius: BorderRadius.circular(AppMetrics.radius),
                border: Border.all(color: OtohaColors.border),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: OtohaColors.mutedText,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'music.youtube.com',
                    style: TextStyle(color: OtohaColors.text, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkPanelArt extends StatelessWidget {
  const _NetworkPanelArt();

  @override
  Widget build(BuildContext context) {
    return _ArtFrame(
      child: Wrap(
        spacing: AppMetrics.unit,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          for (final tab in <String>['Elements', 'Console', 'Network'])
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: tab == 'Network'
                  ? BoxDecoration(
                      color: OtohaColors.accent,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                tab,
                style: TextStyle(
                  fontSize: 11,
                  color: tab == 'Network'
                      ? OtohaColors.canvas
                      : OtohaColors.mutedText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CookieHeaderArt extends StatelessWidget {
  const _CookieHeaderArt();

  @override
  Widget build(BuildContext context) {
    return _ArtFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: OtohaColors.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Cookie: ••••••••••••',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: OtohaColors.mutedText,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppMetrics.unit),
          const Icon(
            Icons.content_copy_rounded,
            color: OtohaColors.accent,
            size: 20,
          ),
        ],
      ),
    );
  }
}
