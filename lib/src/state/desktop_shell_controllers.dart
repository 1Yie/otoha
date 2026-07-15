import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/catalog.dart';
import '../services/audio_playback_engine.dart';
import '../services/player_session_store.dart';

enum WorkspacePage {
  home,
  explore,
  library,
  history,
  downloads,
  playlists,
  settings,
}

extension WorkspacePageDetails on WorkspacePage {
  String get label => switch (this) {
    WorkspacePage.home => 'Home',
    WorkspacePage.explore => 'Explore',
    WorkspacePage.library => 'Library',
    WorkspacePage.history => 'History',
    WorkspacePage.downloads => 'Downloads',
    WorkspacePage.playlists => 'Playlists',
    WorkspacePage.settings => 'Settings',
  };
}

enum SidePanel { queue, devices, account }

enum PlaybackRepeatMode { off, all, one }

class WorkspaceController extends ChangeNotifier {
  final List<WorkspacePage> _history = <WorkspacePage>[WorkspacePage.home];
  int _historyIndex = 0;

  WorkspacePage get current => _history[_historyIndex];
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex < _history.length - 1;

  void navigateTo(WorkspacePage page) {
    if (page == current) {
      return;
    }

    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(page);
    _historyIndex = _history.length - 1;
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) {
      return;
    }

    _historyIndex -= 1;
    notifyListeners();
  }

  void goForward() {
    if (!canGoForward) {
      return;
    }

    _historyIndex += 1;
    notifyListeners();
  }
}

class PlayerController extends ChangeNotifier {
  PlayerController(
    List<Track> catalog, {
    PlayerSessionStore? sessionStore,
    AudioPlaybackEngine? audioPlaybackEngine,
  }) : this._(catalog, sessionStore, audioPlaybackEngine);

  PlayerController._(
    List<Track> catalog,
    this._sessionStore,
    this._audioPlaybackEngine,
  ) : _catalog = List<Track>.unmodifiable(catalog),
      _playOrder = List<Track>.of(catalog),
      _currentTrack = catalog.isEmpty ? null : catalog.first {
    _audioOutputState =
        _audioPlaybackEngine?.outputState ?? const AudioOutputState();
    _audioStates = _audioPlaybackEngine?.states.listen(_handleAudioState);
    _audioOutputStates = _audioPlaybackEngine?.outputStates.listen(
      _handleAudioOutputState,
    );
  }

  List<Track> _catalog;
  List<Track> _playOrder;
  Track? _currentTrack;
  final PlayerSessionStore? _sessionStore;
  final AudioPlaybackEngine? _audioPlaybackEngine;
  Timer? _clock;
  StreamSubscription<AudioPlaybackSnapshot>? _audioStates;
  StreamSubscription<AudioOutputState>? _audioOutputStates;
  Future<void> _writeChain = Future<void>.value();
  int? _lastPersistedAudioCheckpoint;
  int _positionSeconds = 0;
  double _volume = 0.72;
  bool _isPlaying = false;
  bool _isBuffering = false;
  AudioPlaybackFailure? _playbackError;
  int _audioResolveAttempts = 0;
  bool _hasActiveAudio = false;
  int? _pendingAudioPositionSeconds;
  bool _isShuffled = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  AudioOutputState _audioOutputState = const AudioOutputState();
  bool _isSelectingOutputDevice = false;
  bool _hasOutputDeviceError = false;

  Track? get currentTrack => _currentTrack;
  List<Track> get queue => List<Track>.unmodifiable(_playOrder);
  int get positionSeconds => _positionSeconds;
  double get volume => _volume;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  AudioPlaybackFailure? get playbackError => _playbackError;
  VideoController? get videoController => _audioPlaybackEngine?.videoController;
  bool get canSwitchToVideo => _currentTrack?.canPlayVideo ?? false;
  bool get isShuffled => _isShuffled;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  List<AudioOutputDevice> get outputDevices => _audioOutputState.devices;
  AudioOutputDevice? get selectedOutputDevice =>
      _audioOutputState.selectedDevice;
  bool get isSelectingOutputDevice => _isSelectingOutputDevice;
  bool get hasOutputDeviceError => _hasOutputDeviceError;

  Future<void> selectOutputDevice(AudioOutputDevice device) async {
    final engine = _audioPlaybackEngine;
    if (engine == null || _isSelectingOutputDevice) {
      return;
    }
    if (_audioOutputState.selectedDevice?.id == device.id) {
      return;
    }
    _isSelectingOutputDevice = true;
    _hasOutputDeviceError = false;
    notifyListeners();
    try {
      await engine.setOutputDevice(device);
    } on Object {
      _hasOutputDeviceError = true;
    } finally {
      _isSelectingOutputDevice = false;
      notifyListeners();
    }
  }

  Future<void> restoreSession() async {
    final store = _sessionStore;
    if (store == null) {
      return;
    }
    Map<String, Object?>? session;
    try {
      session = await store.read();
    } on Object {
      return;
    }
    if (session == null) {
      return;
    }
    try {
      final catalog = (session['catalog']! as List<Object?>)
          .map(
            (item) => Track.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
      if (catalog.isEmpty) {
        return;
      }
      final byId = <String, Track>{
        for (final track in catalog) track.id: track,
      };
      final order = (session['playOrderIds']! as List<Object?>)
          .map((id) => byId[id])
          .whereType<Track>()
          .toList(growable: false);
      _catalog = List<Track>.unmodifiable(catalog);
      _playOrder = order.isEmpty ? List<Track>.of(catalog) : order;
      _currentTrack = byId[session['currentTrackId']] ?? _playOrder.first;
      final currentTrack = _currentTrack!;
      final savedPosition = session['positionSeconds'] as int? ?? 0;
      _positionSeconds = currentTrack.durationSeconds <= 0
          ? savedPosition.clamp(0, 1 << 31)
          : savedPosition.clamp(0, currentTrack.durationSeconds);
      _volume = (session['volume'] as num? ?? _volume).toDouble().clamp(0, 1);
      _isPlaying = session['isPlaying'] as bool? ?? false;
      _isShuffled = session['isShuffled'] as bool? ?? false;
      _repeatMode = PlaybackRepeatMode.values.firstWhere(
        (mode) => mode.name == session!['repeatMode'],
        orElse: () => PlaybackRepeatMode.off,
      );
      if (_usesAudioPlayback) {
        _isPlaying = false;
        unawaited(_audioPlaybackEngine!.setVolume(_volume));
      }
      _syncClock();
      notifyListeners();
    } on Object {
      try {
        await store.delete();
      } on Object {
        // A malformed session can be ignored if secure storage is unavailable.
      }
    }
  }

  void togglePlaying() {
    if (_currentTrack == null) {
      return;
    }
    if (_usesAudioPlayback) {
      if (_isBuffering) {
        _isPlaying = false;
        _isBuffering = false;
        _hasActiveAudio = false;
        _pendingAudioPositionSeconds = null;
        unawaited(_audioPlaybackEngine!.stop());
      } else if (_isPlaying) {
        _isPlaying = false;
        unawaited(_audioPlaybackEngine!.pause());
      } else {
        _isPlaying = true;
        if (_hasActiveAudio) {
          unawaited(_audioPlaybackEngine!.play());
        } else {
          _activateCurrentTrack();
        }
      }
      _persistSession();
      notifyListeners();
      return;
    }
    _isPlaying = !_isPlaying;
    _syncClock();
    _persistSession();
    notifyListeners();
  }

  void selectTrack(Track track) {
    _currentTrack = track;
    _positionSeconds = 0;
    _isPlaying = true;
    _activateCurrentTrack();
    _persistSession();
    notifyListeners();
  }

  void playTracks(List<Track> tracks) {
    if (tracks.isEmpty) {
      return;
    }
    _catalog = List<Track>.unmodifiable(tracks);
    _playOrder = List<Track>.of(tracks);
    _currentTrack = tracks.first;
    _positionSeconds = 0;
    _isPlaying = true;
    _isShuffled = false;
    _activateCurrentTrack();
    _persistSession();
    notifyListeners();
  }

  void previous() {
    final currentTrack = _currentTrack;
    if (currentTrack == null || _playOrder.isEmpty) {
      return;
    }
    if (_positionSeconds > 3) {
      seekTo(0);
      return;
    }

    final currentIndex = _playOrder.indexOf(currentTrack);
    final previousIndex = currentIndex > 0
        ? currentIndex - 1
        : _repeatMode == PlaybackRepeatMode.all
        ? _playOrder.length - 1
        : 0;
    _currentTrack = _playOrder[previousIndex];
    _positionSeconds = 0;
    _isPlaying = true;
    _activateCurrentTrack();
    _persistSession();
    notifyListeners();
  }

  void next() {
    final currentTrack = _currentTrack;
    if (currentTrack == null || _playOrder.isEmpty) {
      return;
    }
    final currentIndex = _playOrder.indexOf(currentTrack);
    if (_repeatMode == PlaybackRepeatMode.one) {
      _positionSeconds = 0;
      _isPlaying = true;
      _activateCurrentTrack();
      _persistSession();
      notifyListeners();
      return;
    }

    if (currentIndex == _playOrder.length - 1 &&
        _repeatMode != PlaybackRepeatMode.all) {
      _positionSeconds = currentTrack.durationSeconds;
      _isPlaying = false;
      _syncClock();
      _persistSession();
      notifyListeners();
      return;
    }

    _currentTrack = _playOrder[(currentIndex + 1) % _playOrder.length];
    _positionSeconds = 0;
    _isPlaying = true;
    _activateCurrentTrack();
    _persistSession();
    notifyListeners();
  }

  void seekTo(int seconds) {
    final currentTrack = _currentTrack;
    if (currentTrack == null) {
      return;
    }
    _positionSeconds = seconds.clamp(0, currentTrack.durationSeconds);
    if (_usesAudioPlayback) {
      _pendingAudioPositionSeconds = _positionSeconds;
      unawaited(
        _audioPlaybackEngine!.seek(Duration(seconds: _positionSeconds)),
      );
    }
    _persistSession();
    notifyListeners();
  }

  void setVolume(double value) {
    _volume = value.clamp(0, 1);
    if (_audioPlaybackEngine != null) {
      unawaited(_audioPlaybackEngine.setVolume(_volume));
    }
    _persistSession();
    notifyListeners();
  }

  void setVideoMode(bool enabled) {
    final currentTrack = _currentTrack;
    if (currentTrack == null ||
        !currentTrack.canPlayVideo ||
        currentTrack.isVideo == enabled) {
      return;
    }
    final replacement = currentTrack.withVideoMode(enabled);
    final wasPlaying = _isPlaying;
    _catalog = List<Track>.unmodifiable(
      _catalog.map(
        (track) => track.id == currentTrack.id ? replacement : track,
      ),
    );
    _playOrder = _playOrder
        .map((track) => track.id == currentTrack.id ? replacement : track)
        .toList(growable: false);
    _currentTrack = replacement;
    _activateCurrentTrack(playWhenReady: wasPlaying);
    _persistSession();
    notifyListeners();
  }

  void toggleVideoMode() {
    final currentTrack = _currentTrack;
    if (currentTrack == null) {
      return;
    }
    setVideoMode(!currentTrack.isVideo);
  }

  void toggleShuffle() {
    final currentTrack = _currentTrack;
    if (currentTrack == null) {
      return;
    }
    _isShuffled = !_isShuffled;
    if (_isShuffled) {
      final otherTracks =
          _catalog
              .where((track) => track != currentTrack)
              .toList(growable: false)
            ..shuffle(Random(17));
      _playOrder = <Track>[currentTrack, ...otherTracks];
    } else {
      _playOrder = List<Track>.of(_catalog);
    }
    _persistSession();
    notifyListeners();
  }

  void cycleRepeatMode() {
    if (_currentTrack == null) {
      return;
    }
    _repeatMode = switch (_repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    _persistSession();
    notifyListeners();
  }

  void _syncClock() {
    _clock?.cancel();
    final currentTrack = _currentTrack;
    if (_usesAudioPlayback ||
        !_isPlaying ||
        currentTrack == null ||
        currentTrack.durationSeconds <= 0) {
      return;
    }

    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_positionSeconds >= currentTrack.durationSeconds) {
        next();
        return;
      }
      _positionSeconds += 1;
      if (_positionSeconds.remainder(5) == 0) {
        _persistSession();
      }
      notifyListeners();
    });
  }

  bool get _usesAudioPlayback =>
      _audioPlaybackEngine != null &&
      (_currentTrack?.youtubeVideoId != null ||
          _currentTrack?.localFilePath != null);

  void _activateCurrentTrack({
    bool isRetry = false,
    bool playWhenReady = true,
  }) {
    final currentTrack = _currentTrack;
    if (currentTrack == null) {
      return;
    }
    _playbackError = null;
    if (_usesAudioPlayback) {
      if (!isRetry) {
        _audioResolveAttempts = 0;
      }
      _hasActiveAudio = false;
      _clock?.cancel();
      _isPlaying = playWhenReady;
      _isBuffering = true;
      final initialPosition = Duration(seconds: _positionSeconds);
      _pendingAudioPositionSeconds = initialPosition.inSeconds;
      final localFilePath = currentTrack.localFilePath;
      if (localFilePath != null) {
        unawaited(
          _audioPlaybackEngine!.openLocalFile(
            localFilePath,
            initialPosition: initialPosition,
          ),
        );
      } else {
        unawaited(
          _audioPlaybackEngine!.open(
            currentTrack.youtubeVideoId!,
            initialPosition: initialPosition,
            isVideo: currentTrack.isVideo,
            autoplay: playWhenReady,
          ),
        );
      }
      return;
    }
    _isBuffering = false;
    _hasActiveAudio = false;
    _pendingAudioPositionSeconds = null;
    if (_audioPlaybackEngine != null) {
      unawaited(_audioPlaybackEngine.stop());
    }
    _syncClock();
  }

  void _handleAudioState(AudioPlaybackSnapshot state) {
    final currentTrack = _currentTrack;
    if (!_usesAudioPlayback || currentTrack == null) {
      return;
    }
    if (state.isCompleted) {
      next();
      return;
    }
    _isBuffering = state.isBuffering;
    _playbackError = state.error;
    if (state.error != null && _audioResolveAttempts < 1) {
      _audioResolveAttempts += 1;
      _activateCurrentTrack(isRetry: true);
      return;
    }
    if (state.error != null) {
      _isPlaying = false;
    } else if (state.isPlaying) {
      _audioResolveAttempts = 0;
      _hasActiveAudio = true;
    }
    final position = state.position.inSeconds;
    final pendingPosition = _pendingAudioPositionSeconds;
    final acceptsPosition =
        pendingPosition == null || (position - pendingPosition).abs() <= 2;
    if (acceptsPosition) {
      _pendingAudioPositionSeconds = null;
      if (currentTrack.durationSeconds > 0) {
        _positionSeconds = position.clamp(0, currentTrack.durationSeconds);
      } else {
        _positionSeconds = position;
      }
    }
    if (acceptsPosition && _positionSeconds.remainder(5) == 0) {
      _persistSession(deduplicateAudioCheckpoint: true);
    }
    notifyListeners();
  }

  void _handleAudioOutputState(AudioOutputState state) {
    _audioOutputState = state;
    _hasOutputDeviceError = false;
    notifyListeners();
  }

  void _persistSession({bool deduplicateAudioCheckpoint = false}) {
    final store = _sessionStore;
    final currentTrack = _currentTrack;
    if (store == null || currentTrack == null) {
      return;
    }
    final isAudioCheckpoint = _positionSeconds.remainder(5) == 0;
    if (deduplicateAudioCheckpoint &&
        _lastPersistedAudioCheckpoint == _positionSeconds) {
      return;
    }
    if (isAudioCheckpoint) {
      _lastPersistedAudioCheckpoint = _positionSeconds;
    }
    final session = <String, Object?>{
      'catalog': _catalog
          .map((track) => track.toJson())
          .toList(growable: false),
      'playOrderIds': _playOrder
          .map((track) => track.id)
          .toList(growable: false),
      'currentTrackId': currentTrack.id,
      'positionSeconds': _positionSeconds,
      'volume': _volume,
      'isPlaying': _isPlaying,
      'isShuffled': _isShuffled,
      'repeatMode': _repeatMode.name,
    };
    _writeChain = _writeChain
        .then((_) => store.write(session))
        .catchError((_) {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_audioStates?.cancel() ?? Future<void>.value());
    unawaited(_audioOutputStates?.cancel() ?? Future<void>.value());
    if (_audioPlaybackEngine != null) {
      unawaited(_audioPlaybackEngine.dispose());
    }
    super.dispose();
  }
}

class ShellController extends ChangeNotifier {
  SidePanel? _activePanel;
  bool _isSearchOpen = false;
  bool _isExpandedLyricsOpen = false;
  bool _reduceMotion = false;

  SidePanel? get activePanel => _activePanel;
  bool get isSearchOpen => _isSearchOpen;
  bool get isExpandedLyricsOpen => _isExpandedLyricsOpen;
  bool get reduceMotion => _reduceMotion;

  void togglePanel(SidePanel panel) {
    _activePanel = _activePanel == panel ? null : panel;
    notifyListeners();
  }

  void closePanel() {
    if (_activePanel == null) {
      return;
    }

    _activePanel = null;
    notifyListeners();
  }

  void openSearch() {
    if (_isSearchOpen) {
      return;
    }

    _isSearchOpen = true;
    _isExpandedLyricsOpen = false;
    notifyListeners();
  }

  void closeSearch() {
    if (!_isSearchOpen) {
      return;
    }

    _isSearchOpen = false;
    notifyListeners();
  }

  void toggleExpandedLyrics() {
    _isExpandedLyricsOpen = !_isExpandedLyricsOpen;
    if (_isExpandedLyricsOpen) {
      _activePanel = null;
      _isSearchOpen = false;
    }
    notifyListeners();
  }

  void openExpandedMedia() {
    if (_isExpandedLyricsOpen) {
      return;
    }
    _isExpandedLyricsOpen = true;
    _activePanel = null;
    _isSearchOpen = false;
    notifyListeners();
  }

  void closeExpandedLyrics() {
    if (!_isExpandedLyricsOpen) {
      return;
    }

    _isExpandedLyricsOpen = false;
    notifyListeners();
  }

  void closeTopmostOverlay() {
    if (_isSearchOpen) {
      closeSearch();
      return;
    }
    if (_isExpandedLyricsOpen) {
      closeExpandedLyrics();
      return;
    }
    closePanel();
  }

  void setReduceMotion(bool value) {
    if (_reduceMotion == value) {
      return;
    }

    _reduceMotion = value;
    notifyListeners();
  }
}
