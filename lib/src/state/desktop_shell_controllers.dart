import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/catalog.dart';
import '../services/player_session_store.dart';

enum WorkspacePage { home, explore, library, settings }

extension WorkspacePageDetails on WorkspacePage {
  String get label => switch (this) {
    WorkspacePage.home => 'Home',
    WorkspacePage.explore => 'Explore',
    WorkspacePage.library => 'Library',
    WorkspacePage.settings => 'Settings',
  };
}

enum SidePanel { queue, lyrics, devices, account }

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
  PlayerController(List<Track> catalog, {PlayerSessionStore? sessionStore})
    : this._(catalog, sessionStore);

  PlayerController._(List<Track> catalog, this._sessionStore)
    : _catalog = List<Track>.unmodifiable(catalog),
      _playOrder = List<Track>.of(catalog),
      _currentTrack = catalog.first;

  List<Track> _catalog;
  List<Track> _playOrder;
  Track _currentTrack;
  final PlayerSessionStore? _sessionStore;
  Timer? _clock;
  Future<void> _writeChain = Future<void>.value();
  int _positionSeconds = 42;
  double _volume = 0.72;
  bool _isPlaying = false;
  bool _isShuffled = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;

  Track get currentTrack => _currentTrack;
  List<Track> get queue => List<Track>.unmodifiable(_playOrder);
  int get positionSeconds => _positionSeconds;
  double get volume => _volume;
  bool get isPlaying => _isPlaying;
  bool get isShuffled => _isShuffled;
  PlaybackRepeatMode get repeatMode => _repeatMode;

  Future<void> restoreSession() async {
    if (_sessionStore == null) {
      return;
    }
    try {
      final session = await _sessionStore.read();
      if (session == null) {
        return;
      }
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
      final savedPosition = session['positionSeconds'] as int? ?? 0;
      _positionSeconds = savedPosition.clamp(0, _currentTrack.durationSeconds);
      _volume = (session['volume'] as num? ?? _volume).toDouble().clamp(0, 1);
      _isPlaying = session['isPlaying'] as bool? ?? false;
      _isShuffled = session['isShuffled'] as bool? ?? false;
      _repeatMode = PlaybackRepeatMode.values.firstWhere(
        (mode) => mode.name == session['repeatMode'],
        orElse: () => PlaybackRepeatMode.off,
      );
      _syncClock();
      notifyListeners();
    } on Object {
      await _sessionStore.delete();
    }
  }

  void togglePlaying() {
    _isPlaying = !_isPlaying;
    _syncClock();
    _persistSession();
    notifyListeners();
  }

  void selectTrack(Track track) {
    _currentTrack = track;
    _positionSeconds = 0;
    _isPlaying = true;
    _syncClock();
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
    _syncClock();
    _persistSession();
    notifyListeners();
  }

  void previous() {
    if (_positionSeconds > 3) {
      seekTo(0);
      return;
    }

    final currentIndex = _playOrder.indexOf(_currentTrack);
    final previousIndex = currentIndex > 0
        ? currentIndex - 1
        : _repeatMode == PlaybackRepeatMode.all
        ? _playOrder.length - 1
        : 0;
    _currentTrack = _playOrder[previousIndex];
    _positionSeconds = 0;
    _persistSession();
    notifyListeners();
  }

  void next() {
    final currentIndex = _playOrder.indexOf(_currentTrack);
    if (_repeatMode == PlaybackRepeatMode.one) {
      _positionSeconds = 0;
      _persistSession();
      notifyListeners();
      return;
    }

    if (currentIndex == _playOrder.length - 1 &&
        _repeatMode != PlaybackRepeatMode.all) {
      _positionSeconds = _currentTrack.durationSeconds;
      _isPlaying = false;
      _syncClock();
      _persistSession();
      notifyListeners();
      return;
    }

    _currentTrack = _playOrder[(currentIndex + 1) % _playOrder.length];
    _positionSeconds = 0;
    _persistSession();
    notifyListeners();
  }

  void seekTo(int seconds) {
    _positionSeconds = seconds.clamp(0, _currentTrack.durationSeconds);
    _persistSession();
    notifyListeners();
  }

  void setVolume(double value) {
    _volume = value.clamp(0, 1);
    _persistSession();
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    if (_isShuffled) {
      final otherTracks =
          _catalog
              .where((track) => track != _currentTrack)
              .toList(growable: false)
            ..shuffle(Random(17));
      _playOrder = <Track>[_currentTrack, ...otherTracks];
    } else {
      _playOrder = List<Track>.of(_catalog);
    }
    _persistSession();
    notifyListeners();
  }

  void cycleRepeatMode() {
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
    if (!_isPlaying || _currentTrack.durationSeconds <= 0) {
      return;
    }

    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_positionSeconds >= _currentTrack.durationSeconds) {
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

  void _persistSession() {
    final store = _sessionStore;
    if (store == null) {
      return;
    }
    final session = <String, Object?>{
      'catalog': _catalog
          .map((track) => track.toJson())
          .toList(growable: false),
      'playOrderIds': _playOrder
          .map((track) => track.id)
          .toList(growable: false),
      'currentTrackId': _currentTrack.id,
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
    super.dispose();
  }
}

class ShellController extends ChangeNotifier {
  SidePanel? _activePanel;
  bool _isSearchOpen = false;
  bool _isExpandedLyricsOpen = false;
  bool _reduceMotion = false;
  String _selectedDevice = 'This computer';

  SidePanel? get activePanel => _activePanel;
  bool get isSearchOpen => _isSearchOpen;
  bool get isExpandedLyricsOpen => _isExpandedLyricsOpen;
  bool get reduceMotion => _reduceMotion;
  String get selectedDevice => _selectedDevice;

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

  void selectDevice(String device) {
    if (_selectedDevice == device) {
      return;
    }

    _selectedDevice = device;
    notifyListeners();
  }
}
