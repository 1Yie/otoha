import 'dart:async';

import 'package:flutter/material.dart';

import '../data/mock_catalog.dart';
import '../services/credential_store.dart';
import '../services/player_session_store.dart';
import '../services/youtube_sidecar_client.dart';
import '../state/desktop_shell_controllers.dart';
import '../state/youtube_library_controller.dart';
import '../widgets/desktop_shell.dart';
import 'theme.dart';

class OtohaApp extends StatefulWidget {
  const OtohaApp({
    this.youtubeLibraryController,
    this.playerSessionStore,
    super.key,
  });

  final YouTubeLibraryController? youtubeLibraryController;
  final PlayerSessionStore? playerSessionStore;

  @override
  State<OtohaApp> createState() => _OtohaAppState();
}

class _OtohaAppState extends State<OtohaApp> {
  late final WorkspaceController _workspaceController;
  late final PlayerController _playerController;
  late final ShellController _shellController;
  late final YouTubeLibraryController _youtubeLibraryController;
  late final bool _ownsYouTubeLibraryController;
  late final bool _restoresPlayerSession;

  @override
  void initState() {
    super.initState();
    _workspaceController = WorkspaceController();
    _ownsYouTubeLibraryController = widget.youtubeLibraryController == null;
    _restoresPlayerSession =
        _ownsYouTubeLibraryController || widget.playerSessionStore != null;
    _playerController = PlayerController(
      MockCatalog.tracks,
      sessionStore: _restoresPlayerSession
          ? widget.playerSessionStore ?? const SecurePlayerSessionStore()
          : null,
    );
    _shellController = ShellController();
    _youtubeLibraryController =
        widget.youtubeLibraryController ??
        YouTubeLibraryController(
          client: YouTubeSidecarClient(),
          credentialStore: const SecureCredentialStore(),
        );
    if (_ownsYouTubeLibraryController) {
      unawaited(_youtubeLibraryController.initialize());
    }
    if (_restoresPlayerSession) {
      unawaited(_playerController.restoreSession());
    }
  }

  @override
  void dispose() {
    _workspaceController.dispose();
    _playerController.dispose();
    _shellController.dispose();
    if (_ownsYouTubeLibraryController) {
      _youtubeLibraryController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Otoha',
      debugShowCheckedModeBanner: false,
      theme: buildOtohaTheme(),
      home: DesktopShell(
        workspaceController: _workspaceController,
        playerController: _playerController,
        shellController: _shellController,
        youtubeLibraryController: _youtubeLibraryController,
      ),
    );
  }
}
