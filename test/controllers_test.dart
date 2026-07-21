import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/data/mock_catalog.dart';
import 'package:otoha/src/models/catalog.dart';
import 'package:otoha/src/services/audio_playback_engine.dart';
import 'package:otoha/src/services/player_session_store.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';

void main() {
  group('WorkspaceController', () {
    test('restores prior workspaces through history', () {
      final controller = WorkspaceController();
      addTearDown(controller.dispose);

      controller.navigateTo(WorkspacePage.explore);
      controller.navigateTo(WorkspacePage.library);

      expect(controller.current, WorkspacePage.library);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoForward, isFalse);

      controller.goBack();

      expect(controller.current, WorkspacePage.explore);
      expect(controller.canGoForward, isTrue);

      controller.goForward();

      expect(controller.current, WorkspacePage.library);
    });
  });

  group('PlayerController', () {
    test('changes tracks and retains local playback state', () {
      final controller = PlayerController(MockCatalog.tracks);
      addTearDown(controller.dispose);

      controller.selectTrack(MockCatalog.tracks[1]);

      expect(controller.currentTrack, MockCatalog.tracks[1]);
      expect(controller.positionSeconds, 0);
      expect(controller.isPlaying, isTrue);

      controller.next();

      expect(controller.currentTrack, MockCatalog.tracks[2]);
      expect(controller.positionSeconds, 0);

      controller.toggleShuffle();

      expect(controller.isShuffled, isTrue);
      expect(controller.queue.first, controller.currentTrack);

      controller.cycleRepeatMode();

      expect(controller.repeatMode, PlaybackRepeatMode.all);
    });

    test('restores a simulated playlist session after restart', () async {
      final store = _MemoryPlayerSessionStore();
      final source = PlayerController(MockCatalog.tracks, sessionStore: store);
      addTearDown(source.dispose);
      source.playTracks(MockCatalog.tracks.take(3).toList(growable: false));
      source.selectTrack(MockCatalog.tracks[1]);
      source.seekTo(73);
      source.setVolume(0.4);
      source.cycleRepeatMode();
      await Future<void>.delayed(Duration.zero);
      store.value!.remove('audioQuality');

      final restored = PlayerController(const <Track>[], sessionStore: store);
      addTearDown(restored.dispose);
      await restored.restoreSession();

      expect(restored.queue.map((track) => track.id), <String>[
        'soft-signal',
        'after-image',
        'room-for-light',
      ]);
      expect(restored.currentTrack?.id, 'after-image');
      expect(restored.positionSeconds, 73);
      expect(restored.volume, 0.4);
      expect(restored.repeatMode, PlaybackRepeatMode.all);
      expect(restored.audioQuality, AudioQuality.high);
      expect(restored.isPlaying, isTrue);
    });

    test(
      'persists quality without a queue and restores it after restart',
      () async {
        final store = _MemoryPlayerSessionStore();
        final source = PlayerController(const <Track>[], sessionStore: store);
        addTearDown(source.dispose);

        source.setAudioQuality(AudioQuality.normal);
        await Future<void>.delayed(Duration.zero);

        expect(store.value, <String, Object?>{'audioQuality': 'normal'});

        final restored = PlayerController(const <Track>[], sessionStore: store);
        addTearDown(restored.dispose);
        await restored.restoreSession();

        expect(restored.audioQuality, AudioQuality.normal);
        expect(restored.currentTrack, isNull);
      },
    );

    test('applies changed quality only to the next remote stream', () {
      final engine = _FakeAudioPlaybackEngine();
      final first = _youtubeTrack('first');
      final second = _youtubeTrack('second');
      final controller = PlayerController(<Track>[
        first,
        second,
      ], audioPlaybackEngine: engine);
      addTearDown(controller.dispose);

      controller.selectTrack(first);
      expect(engine.openedAudioQualities, <AudioQuality>[AudioQuality.high]);

      controller.setAudioQuality(AudioQuality.low);
      expect(engine.openedVideoIds, <String>['first']);

      controller.selectTrack(second);
      expect(engine.openedAudioQualities, <AudioQuality>[
        AudioQuality.high,
        AudioQuality.low,
      ]);
    });

    test('keeps a persisted session when secure storage read fails', () async {
      final store = _MemoryPlayerSessionStore()
        ..readError = StateError('Keyring unavailable');
      final controller = PlayerController(const <Track>[], sessionStore: store);
      addTearDown(controller.dispose);

      await controller.restoreSession();

      expect(controller.currentTrack, isNull);
      expect(store.deleteCount, 0);
    });

    test('uses native audio events for YouTube tracks', () async {
      final engine = _FakeAudioPlaybackEngine();
      final first = _youtubeTrack('first');
      final second = _youtubeTrack('second');
      final controller = PlayerController(<Track>[
        first,
        second,
      ], audioPlaybackEngine: engine);
      addTearDown(controller.dispose);

      controller.selectTrack(first);

      expect(engine.openedVideoIds, <String>['first']);
      expect(controller.isBuffering, isTrue);
      expect(controller.isPlaying, isTrue);

      controller.togglePlaying();
      expect(controller.isBuffering, isFalse);
      expect(controller.isPlaying, isFalse);

      controller.togglePlaying();
      expect(engine.openedVideoIds, <String>['first', 'first']);

      engine.emit(
        const AudioPlaybackSnapshot(position: Duration.zero, isBuffering: true),
      );
      await Future<void>.delayed(Duration.zero);
      engine.emit(
        const AudioPlaybackSnapshot(
          position: Duration(seconds: 18),
          isPlaying: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.positionSeconds, 18);
      expect(controller.isPlaying, isTrue);
      controller.seekTo(24);
      controller.setVolume(0.4);
      expect(engine.seekPositions, <Duration>[const Duration(seconds: 24)]);
      expect(engine.volumes, <double>[0.4]);

      engine.emit(
        const AudioPlaybackSnapshot(
          position: Duration(seconds: 24),
          isBuffering: true,
          error: AudioPlaybackFailure.startFailed,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(engine.openedVideoIds, <String>['first', 'first', 'first']);
      expect(controller.isBuffering, isTrue);
      engine.emit(
        const AudioPlaybackSnapshot(
          position: Duration(seconds: 24),
          isBuffering: true,
          error: AudioPlaybackFailure.startFailed,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.playbackError, AudioPlaybackFailure.startFailed);
      expect(controller.isBuffering, isFalse);
    });

    test('starts a queue at an index and advances after completion', () async {
      final engine = _FakeAudioPlaybackEngine();
      final first = _youtubeTrack('first');
      final second = _youtubeTrack('second');
      final third = _youtubeTrack('third');
      final controller = PlayerController(
        const <Track>[],
        audioPlaybackEngine: engine,
      );
      addTearDown(controller.dispose);

      controller.playTracks(<Track>[first, second, third], initialIndex: 1);

      expect(controller.currentTrack, same(second));
      expect(controller.queue, <Track>[first, second, third]);
      expect(engine.openedVideoIds, <String>['second']);

      engine.emit(
        const AudioPlaybackSnapshot(
          position: Duration(seconds: 180),
          isCompleted: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentTrack, same(third));
      expect(engine.openedVideoIds, <String>['second', 'third']);
    });

    test('corrects queue durations without losing current identity', () async {
      final engine = _FakeAudioPlaybackEngine();
      final first = _youtubeTrack('first').withDurationSeconds(45);
      final second = _youtubeTrack(
        'second',
        isVideo: true,
        videoAvailable: true,
      ).withDurationSeconds(0);
      final controller = PlayerController(
        const <Track>[],
        audioPlaybackEngine: engine,
      );
      addTearDown(controller.dispose);

      controller.playTracks(<Track>[first, second], initialIndex: 1);
      controller.updateTrackDuration(first.id, 215);

      expect(controller.queue.first.durationSeconds, 215);
      expect(controller.currentTrack, same(controller.queue[1]));
      expect(controller.currentTrack?.durationSeconds, 0);

      engine.emit(
        const AudioPlaybackSnapshot(
          duration: Duration(seconds: 247),
          isPlaying: true,
          isBuffering: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentTrack?.durationSeconds, 0);

      engine.emit(
        const AudioPlaybackSnapshot(
          position: Duration(seconds: 12),
          duration: Duration(seconds: 247),
          isPlaying: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentTrack, same(controller.queue[1]));
      expect(controller.currentTrack?.durationSeconds, 247);
      expect(controller.currentTrack?.isVideo, isTrue);
      expect(controller.currentTrack?.videoAvailable, isTrue);
      expect(controller.positionSeconds, 12);
    });

    test('opens a video track with visible-video playback enabled', () {
      final engine = _FakeAudioPlaybackEngine();
      final track = _youtubeTrack('video', isVideo: true);
      final controller = PlayerController(<Track>[
        track,
      ], audioPlaybackEngine: engine);
      addTearDown(controller.dispose);

      controller.selectTrack(track);

      expect(engine.openedVideoIds, <String>['video']);
      expect(engine.openedVideoModes, <bool>[true]);
      expect(Track.fromJson(track.toJson()).isVideo, isTrue);
    });

    test(
      'video-capable tracks restart independent timelines when switching modes',
      () async {
        final engine = _FakeAudioPlaybackEngine();
        final track = _youtubeTrack('video', videoAvailable: true);
        final controller = PlayerController(<Track>[
          track,
        ], audioPlaybackEngine: engine);
        addTearDown(controller.dispose);

        controller.selectTrack(track);
        expect(engine.openedVideoModes, <bool>[false]);
        engine.emit(
          const AudioPlaybackSnapshot(position: Duration.zero, isPlaying: true),
        );
        await Future<void>.delayed(Duration.zero);
        engine.emit(
          const AudioPlaybackSnapshot(
            position: Duration(seconds: 37),
            isPlaying: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        controller.setVideoMode(true);
        expect(controller.currentTrack?.isVideo, isTrue);
        expect(controller.queue.single.isVideo, isTrue);
        expect(engine.openedVideoModes, <bool>[false, true]);
        expect(engine.openInitialPositions.last, Duration.zero);
        expect(engine.openedAutoplayModes.last, isTrue);
        expect(controller.positionSeconds, 0);
        expect(controller.isBuffering, isTrue);

        engine.emit(
          const AudioPlaybackSnapshot(
            position: Duration.zero,
            isPlaying: true,
            isBuffering: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.positionSeconds, 0);
        expect(controller.isBuffering, isTrue);

        engine.emit(
          const AudioPlaybackSnapshot(
            position: Duration(seconds: 12),
            isPlaying: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.positionSeconds, 12);
        expect(controller.isBuffering, isFalse);

        controller.togglePlaying();
        controller.setVideoMode(false);
        expect(controller.currentTrack?.isVideo, isFalse);
        expect(controller.currentTrack?.videoAvailable, isTrue);
        expect(engine.openedVideoModes, <bool>[false, true, false]);
        expect(engine.openInitialPositions.last, Duration.zero);
        expect(engine.openedAutoplayModes.last, isFalse);
        expect(controller.positionSeconds, 0);
        expect(
          Track.fromJson(controller.currentTrack!.toJson()).videoAvailable,
          isTrue,
        );
      },
    );

    test('persists each native audio checkpoint only once', () async {
      final engine = _FakeAudioPlaybackEngine();
      final store = _MemoryPlayerSessionStore();
      final track = _youtubeTrack('first');
      final controller = PlayerController(
        <Track>[track],
        sessionStore: store,
        audioPlaybackEngine: engine,
      );
      addTearDown(controller.dispose);

      controller.selectTrack(track);
      await Future<void>.delayed(Duration.zero);
      final writesAfterSelection = store.writeCount;

      engine
        ..emit(const AudioPlaybackSnapshot(position: Duration.zero))
        ..emit(const AudioPlaybackSnapshot(position: Duration.zero))
        ..emit(const AudioPlaybackSnapshot(position: Duration.zero));
      await Future<void>.delayed(Duration.zero);

      expect(store.writeCount, writesAfterSelection);

      engine
        ..emit(
          const AudioPlaybackSnapshot(
            position: Duration(seconds: 5),
            isPlaying: true,
          ),
        )
        ..emit(
          const AudioPlaybackSnapshot(
            position: Duration(seconds: 5),
            isPlaying: true,
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(store.writeCount, writesAfterSelection + 1);
    });

    test('keeps restored position until native seek catches up', () async {
      final store = _MemoryPlayerSessionStore();
      final track = _youtubeTrack('restored', isVideo: true);
      final sourceEngine = _FakeAudioPlaybackEngine();
      final source = PlayerController(
        <Track>[track],
        sessionStore: store,
        audioPlaybackEngine: sourceEngine,
      );
      addTearDown(source.dispose);
      source
        ..selectTrack(track)
        ..seekTo(73);
      await Future<void>.delayed(Duration.zero);

      final restoredEngine = _FakeAudioPlaybackEngine();
      final restored = PlayerController(
        const <Track>[],
        sessionStore: store,
        audioPlaybackEngine: restoredEngine,
      );
      addTearDown(restored.dispose);
      await restored.restoreSession();

      expect(restored.positionSeconds, 73);
      restored.togglePlaying();
      expect(restoredEngine.openInitialPositions, <Duration>[
        const Duration(seconds: 73),
      ]);
      expect(restoredEngine.openedVideoModes, <bool>[true]);

      restoredEngine.emit(
        const AudioPlaybackSnapshot(position: Duration.zero, isBuffering: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(restored.positionSeconds, 73);

      restoredEngine.emit(
        const AudioPlaybackSnapshot(
          position: Duration(seconds: 73),
          isPlaying: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(restored.positionSeconds, 73);

      restoredEngine.emit(
        const AudioPlaybackSnapshot(
          position: Duration(seconds: 74),
          isPlaying: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(restored.positionSeconds, 74);
    });

    test('plays a downloaded track from its local audio file', () {
      final engine = _FakeAudioPlaybackEngine();
      final track = Track(
        id: 'offline:video-id',
        title: 'Downloaded track',
        artist: 'Artist',
        album: 'Album',
        artworkAsset: 'assets/artwork/cover_01.png',
        durationSeconds: 180,
        lyrics: const <String>[],
        youtubeVideoId: 'video-id',
        localFilePath: '/music/video-id.webm',
      );
      final controller = PlayerController(<Track>[
        track,
      ], audioPlaybackEngine: engine);
      addTearDown(controller.dispose);

      controller.selectTrack(track);

      expect(engine.openedVideoIds, isEmpty);
      expect(engine.openedLocalFilePaths, <String>['/music/video-id.webm']);
      expect(controller.isBuffering, isTrue);
    });

    test('switches to an enumerated native audio output device', () async {
      final engine = _FakeAudioPlaybackEngine();
      final controller = PlayerController(<Track>[
        _youtubeTrack('first'),
      ], audioPlaybackEngine: engine);
      addTearDown(controller.dispose);

      expect(controller.outputDevices.map((device) => device.id), <String>[
        'auto',
        'alsa/Desk_Speakers',
      ]);
      expect(controller.selectedOutputDevice?.id, 'auto');

      await controller.selectOutputDevice(controller.outputDevices.last);

      expect(engine.selectedOutputDeviceIds, <String>['alsa/Desk_Speakers']);
      expect(controller.selectedOutputDevice?.id, 'alsa/Desk_Speakers');
      expect(controller.hasOutputDeviceError, isFalse);
    });
  });
}

Track _youtubeTrack(
  String videoId, {
  bool isVideo = false,
  bool videoAvailable = false,
}) {
  return Track(
    id: 'youtube:$videoId',
    title: 'Track $videoId',
    artist: 'Artist',
    album: 'Album',
    artworkAsset: 'assets/artwork/cover_01.png',
    durationSeconds: 180,
    lyrics: const <String>[],
    youtubeVideoId: videoId,
    isVideo: isVideo,
    videoAvailable: videoAvailable,
  );
}

class _MemoryPlayerSessionStore implements PlayerSessionStore {
  Map<String, Object?>? value;
  Object? readError;
  int deleteCount = 0;
  int writeCount = 0;

  @override
  Future<void> delete() async {
    deleteCount += 1;
    value = null;
  }

  @override
  Future<Map<String, Object?>?> read() async {
    if (readError case final error?) {
      throw error;
    }
    return value;
  }

  @override
  Future<void> write(Map<String, Object?> value) async {
    this.value = value;
    writeCount += 1;
  }
}

class _FakeAudioPlaybackEngine implements AudioPlaybackEngine {
  final StreamController<AudioPlaybackSnapshot> _states =
      StreamController<AudioPlaybackSnapshot>.broadcast();
  final StreamController<AudioOutputState> _outputStates =
      StreamController<AudioOutputState>.broadcast();
  final List<String> openedVideoIds = <String>[];
  final List<Duration> openInitialPositions = <Duration>[];
  final List<bool> openedVideoModes = <bool>[];
  final List<bool> openedAutoplayModes = <bool>[];
  final List<AudioQuality> openedAudioQualities = <AudioQuality>[];
  final List<String> openedLocalFilePaths = <String>[];
  final List<Duration> seekPositions = <Duration>[];
  final List<double> volumes = <double>[];
  final List<String> selectedOutputDeviceIds = <String>[];
  AudioOutputState _outputState = const AudioOutputState(
    devices: <AudioOutputDevice>[
      AudioOutputDevice.systemDefault(),
      AudioOutputDevice(id: 'alsa/Desk_Speakers', description: 'Desk speakers'),
    ],
    selectedDevice: AudioOutputDevice.systemDefault(),
  );

  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;

  @override
  AudioOutputState get outputState => _outputState;

  @override
  Stream<AudioOutputState> get outputStates => _outputStates.stream;

  @override
  get videoController => null;

  @override
  Future<void> dispose() async {
    await _states.close();
    await _outputStates.close();
  }

  void emit(AudioPlaybackSnapshot state) => _states.add(state);

  @override
  Future<void> open(
    String videoId, {
    Duration initialPosition = Duration.zero,
    bool isVideo = false,
    bool autoplay = true,
    AudioQuality audioQuality = AudioQuality.high,
  }) async {
    openedVideoIds.add(videoId);
    openInitialPositions.add(initialPosition);
    openedVideoModes.add(isVideo);
    openedAutoplayModes.add(autoplay);
    openedAudioQualities.add(audioQuality);
  }

  @override
  Future<void> openLocalFile(
    String path, {
    Duration initialPosition = Duration.zero,
  }) async {
    openedLocalFilePaths.add(path);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> setVolume(double value) async {
    volumes.add(value);
  }

  @override
  Future<void> setOutputDevice(AudioOutputDevice device) async {
    selectedOutputDeviceIds.add(device.id);
    _outputState = AudioOutputState(
      devices: _outputState.devices,
      selectedDevice: device,
    );
    _outputStates.add(_outputState);
  }

  @override
  Future<void> stop() async {}
}
