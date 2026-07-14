import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otoha/l10n/app_localizations.dart';

import '../models/catalog.dart';
import '../services/audio_playback_engine.dart';
import '../services/credential_store.dart';
import '../services/desktop_tray_controller.dart';
import '../services/lyric_cache.dart';
import '../services/offline_library_store.dart';
import '../services/player_session_store.dart';
import '../services/remote_metadata_cache.dart';
import '../services/youtube_sidecar_client.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/app_locale_controller.dart';
import '../state/offline_library_controller.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/desktop_shell.dart';
import 'theme.dart';

class OtohaApp extends StatefulWidget {
  const OtohaApp({
    this.youtubeLibraryController,
    this.offlineLibraryController,
    this.playerSessionStore,
    this.initialTracks = const <Track>[],
    this.localeController,
    this.desktopTrayController,
    super.key,
  });

  final YouTubeLibraryController? youtubeLibraryController;
  final OfflineLibraryController? offlineLibraryController;
  final PlayerSessionStore? playerSessionStore;
  final List<Track> initialTracks;
  final AppLocaleController? localeController;
  final DesktopTrayController? desktopTrayController;

  @override
  State<OtohaApp> createState() => _OtohaAppState();
}

class _OtohaAppState extends State<OtohaApp> {
  late final WorkspaceController _workspaceController;
  late final PlayerController _playerController;
  late final ShellController _shellController;
  late final FocusNode _shellFocusNode;
  late final YouTubeLibraryController _youtubeLibraryController;
  late final OfflineLibraryController _offlineLibraryController;
  late final AppLocaleController _localeController;
  late final bool _ownsYouTubeLibraryController;
  late final bool _ownsOfflineLibraryController;
  late final bool _ownsLocaleController;
  late final bool _restoresPlayerSession;
  bool _localeSyncPending = false;
  String? _trayLanguageCode;
  String? _lyricsPrefetchTrackId;

  @override
  void initState() {
    super.initState();
    _ownsLocaleController = widget.localeController == null;
    _localeController = widget.localeController ?? AppLocaleController();
    _workspaceController = WorkspaceController();
    _ownsYouTubeLibraryController = widget.youtubeLibraryController == null;
    _restoresPlayerSession =
        _ownsYouTubeLibraryController || widget.playerSessionStore != null;
    final sidecarClient = _ownsYouTubeLibraryController
        ? YouTubeSidecarClient()
        : null;
    _playerController = PlayerController(
      widget.initialTracks,
      sessionStore: _restoresPlayerSession
          ? widget.playerSessionStore ?? const SecurePlayerSessionStore()
          : null,
      audioPlaybackEngine: sidecarClient == null
          ? null
          : MediaKitAudioPlaybackEngine(sidecarClient),
    );
    _shellController = ShellController();
    _shellFocusNode = FocusNode(debugLabel: 'desktop-shell');
    _youtubeLibraryController =
        widget.youtubeLibraryController ??
        YouTubeLibraryController(
          client: sidecarClient!,
          credentialStore: const SecureCredentialStore(),
          metadataCache: FileRemoteMetadataCache(),
          lyricCache: FileLyricCache(),
          locale: _localeController.youtubeLanguage,
        );
    _ownsOfflineLibraryController = widget.offlineLibraryController == null;
    _offlineLibraryController =
        widget.offlineLibraryController ??
        OfflineLibraryController(
          store: FileOfflineLibraryStore(),
          youtubeLibraryController: _youtubeLibraryController,
        );
    _localeController.addListener(_handleLocaleChanged);
    _playerController.addListener(_prefetchLyricsForCurrentTrack);
    unawaited(_offlineLibraryController.initialize());
    if (_ownsYouTubeLibraryController) {
      unawaited(_youtubeLibraryController.initialize());
    }
    if (_restoresPlayerSession) {
      unawaited(_playerController.restoreSession());
    }
    if (widget.desktopTrayController case final desktopTrayController?) {
      desktopTrayController.setWindowShownCallback(_restoreShellFocus);
      unawaited(desktopTrayController.initialize(_playerController));
    }
  }

  @override
  void dispose() {
    widget.desktopTrayController?.setWindowShownCallback(null);
    widget.desktopTrayController?.dispose();
    _workspaceController.dispose();
    _playerController.removeListener(_prefetchLyricsForCurrentTrack);
    _playerController.dispose();
    _shellController.dispose();
    _shellFocusNode.dispose();
    if (_ownsOfflineLibraryController) {
      _offlineLibraryController.dispose();
    }
    _localeController.removeListener(_handleLocaleChanged);
    if (_ownsLocaleController) {
      _localeController.dispose();
    }
    if (_ownsYouTubeLibraryController) {
      _youtubeLibraryController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _localeController,
      builder: (context, _) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          debugShowCheckedModeBanner: false,
          theme: buildOtohaTheme(),
          locale: _localeController.locale,
          supportedLocales: AppLocaleController.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              _updateTrayLabels(AppLocalizations.of(context)!);
              return DesktopShell(
                workspaceController: _workspaceController,
                playerController: _playerController,
                shellController: _shellController,
                focusNode: _shellFocusNode,
                youtubeLibraryController: _youtubeLibraryController,
                offlineLibraryController: _offlineLibraryController,
                localeController: _localeController,
              );
            },
          ),
        );
      },
    );
  }

  void _restoreShellFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_shellFocusNode.hasFocus) {
        _shellFocusNode.requestFocus();
      }
    });
  }

  void _updateTrayLabels(AppLocalizations localizations) {
    final desktopTrayController = widget.desktopTrayController;
    final languageCode = _localeController.locale.languageCode;
    if (desktopTrayController == null || _trayLanguageCode == languageCode) {
      return;
    }
    _trayLanguageCode = languageCode;
    final labels = TrayLabels(
      showWindow: localizations.showWindow,
      play: localizations.play,
      pause: localizations.pause,
      quit: localizations.quitApplication,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(desktopTrayController.updateLabels(labels));
      }
    });
  }

  void _handleLocaleChanged() {
    if (_localeSyncPending) {
      return;
    }
    _localeSyncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _localeSyncPending = false;
      if (!mounted) {
        return;
      }
      unawaited(
        _youtubeLibraryController.setLocale(_localeController.youtubeLanguage),
      );
    });
  }

  void _prefetchLyricsForCurrentTrack() {
    final track = _playerController.currentTrack;
    if (track == null) {
      _lyricsPrefetchTrackId = null;
      return;
    }
    final videoId = track.youtubeVideoId;
    if (!_youtubeLibraryController.isSignedIn || videoId == null) {
      _lyricsPrefetchTrackId = null;
      return;
    }
    if (_lyricsPrefetchTrackId == track.id) {
      return;
    }

    _lyricsPrefetchTrackId = track.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _lyricsPrefetchTrackId != track.id ||
          _playerController.currentTrack?.id != track.id ||
          !_youtubeLibraryController.isSignedIn) {
        return;
      }
      unawaited(
        _youtubeLibraryController.loadLyrics(
          videoId: videoId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationSeconds: track.durationSeconds,
        ),
      );
    });
  }
}
