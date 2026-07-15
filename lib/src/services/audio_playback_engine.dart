import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'desktop_proxy_environment.dart';
import 'youtube_sidecar_client.dart';

enum AudioPlaybackFailure { engineCouldNotPlay, streamUnavailable, startFailed }

class AudioOutputDevice {
  const AudioOutputDevice({required this.id, required this.description});

  const AudioOutputDevice.systemDefault() : id = 'auto', description = '';

  final String id;
  final String description;

  bool get isSystemDefault => id == 'auto';
}

class AudioOutputState {
  const AudioOutputState({
    this.devices = const <AudioOutputDevice>[],
    this.selectedDevice,
  });

  final List<AudioOutputDevice> devices;
  final AudioOutputDevice? selectedDevice;
}

class AudioPlaybackSnapshot {
  const AudioPlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.error,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final AudioPlaybackFailure? error;

  AudioPlaybackSnapshot copyWith({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    AudioPlaybackFailure? error,
    bool clearError = false,
  }) {
    return AudioPlaybackSnapshot(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      error: clearError ? null : error ?? this.error,
    );
  }
}

abstract interface class AudioPlaybackEngine {
  Stream<AudioPlaybackSnapshot> get states;
  AudioOutputState get outputState;
  Stream<AudioOutputState> get outputStates;
  VideoController? get videoController;

  Future<void> open(
    String videoId, {
    Duration initialPosition,
    bool isVideo,
    bool autoplay,
  });
  Future<void> openLocalFile(String path, {Duration initialPosition});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double value);
  Future<void> setOutputDevice(AudioOutputDevice device);
  Future<void> stop();
  Future<void> dispose();
}

class MediaKitAudioPlaybackEngine implements AudioPlaybackEngine {
  factory MediaKitAudioPlaybackEngine(
    YouTubeSidecarClient client, {
    Map<String, String> proxyEnvironment = const <String, String>{},
  }) {
    return MediaKitAudioPlaybackEngine._(client, proxyEnvironment);
  }

  MediaKitAudioPlaybackEngine._(this._client, this._proxyEnvironment)
    : _player = Player(
        configuration: const PlayerConfiguration(
          protocolWhitelist: <String>[
            'udp',
            'rtp',
            'tcp',
            'tls',
            'data',
            'file',
            'http',
            'https',
            'httpproxy',
            'crypto',
          ],
        ),
      ) {
    _outputState = _outputStateFor(
      _player.state.audioDevices,
      _player.state.audioDevice,
    );
    _subscriptions = <StreamSubscription<Object?>>[
      _player.stream.position.listen((position) => _update(position: position)),
      _player.stream.duration.listen((duration) => _update(duration: duration)),
      _player.stream.playing.listen(
        (isPlaying) => _update(isPlaying: isPlaying),
      ),
      _player.stream.buffering.listen(
        (isBuffering) => _update(isBuffering: isBuffering),
      ),
      _player.stream.completed.listen((isCompleted) {
        if (isCompleted) {
          _update(isCompleted: true, isPlaying: false);
        }
      }),
      _player.stream.error.listen((error) {
        if (error.isNotEmpty) {
          _update(error: AudioPlaybackFailure.engineCouldNotPlay);
        }
      }),
      _player.stream.audioDevice.listen(_updateOutputDevice),
      _player.stream.audioDevices.listen(_updateOutputDevices),
    ];
  }

  final YouTubeSidecarClient _client;
  final Map<String, String> _proxyEnvironment;
  final Player _player;
  VideoController? _videoController;
  final StreamController<AudioPlaybackSnapshot> _states =
      StreamController<AudioPlaybackSnapshot>.broadcast();
  final StreamController<AudioOutputState> _outputStates =
      StreamController<AudioOutputState>.broadcast();
  late final List<StreamSubscription<Object?>> _subscriptions;
  AudioPlaybackSnapshot _snapshot = const AudioPlaybackSnapshot();
  late AudioOutputState _outputState;
  int _request = 0;
  bool _isDisposed = false;

  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;

  @override
  AudioOutputState get outputState => _outputState;

  @override
  Stream<AudioOutputState> get outputStates => _outputStates.stream;

  @override
  VideoController get videoController =>
      _videoController ??= VideoController(_player);

  @override
  Future<void> open(
    String videoId, {
    Duration initialPosition = Duration.zero,
    bool isVideo = false,
    bool autoplay = true,
  }) async {
    if (isVideo) {
      videoController;
    }
    final request = ++_request;
    _update(
      isPlaying: false,
      isBuffering: true,
      isCompleted: false,
      clearError: true,
    );
    try {
      final result = await _client.call('playback.resolve', <String, Object?>{
        'videoId': videoId,
        'mediaType': isVideo ? 'video' : 'audio',
      });
      if (request != _request || _isDisposed) {
        return;
      }
      final stream = (result['stream']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final url = stream['url'] as String?;
      final audioUrl = stream['audioUrl'] as String?;
      await _player.stop();
      if (request != _request || _isDisposed) {
        return;
      }
      if (url == null || url.isEmpty) {
        throw const SidecarException('PLAYBACK_UNAVAILABLE', '');
      }
      await _configureProxyFor(url);
      await _configureExternalAudio(isVideo ? audioUrl : null);
      await _player.open(Media(url), play: false);
      if (request != _request || _isDisposed) {
        return;
      }
      if (initialPosition > Duration.zero) {
        await _waitUntilMediaIsSeekable();
        if (request != _request || _isDisposed) {
          return;
        }
        await _player.seek(initialPosition);
      }
      if (autoplay) {
        await _player.play();
      }
    } on SidecarException {
      if (request == _request && !_isDisposed) {
        _update(
          isPlaying: false,
          isBuffering: false,
          error: AudioPlaybackFailure.streamUnavailable,
        );
      }
    } on Object {
      if (request == _request && !_isDisposed) {
        _update(
          isPlaying: false,
          isBuffering: false,
          error: AudioPlaybackFailure.startFailed,
        );
      }
    }
  }

  @override
  Future<void> openLocalFile(
    String path, {
    Duration initialPosition = Duration.zero,
  }) async {
    final request = ++_request;
    _update(
      isPlaying: false,
      isBuffering: true,
      isCompleted: false,
      clearError: true,
    );
    try {
      await _player.stop();
      if (request != _request || _isDisposed) {
        return;
      }
      await _configureExternalAudio(null);
      await _player.open(Media(path), play: false);
      if (request != _request || _isDisposed) {
        return;
      }
      if (initialPosition > Duration.zero) {
        await _waitUntilMediaIsSeekable();
        if (request != _request || _isDisposed) {
          return;
        }
        await _player.seek(initialPosition);
      }
      await _player.play();
    } on Object {
      if (request == _request && !_isDisposed) {
        _update(
          isPlaying: false,
          isBuffering: false,
          error: AudioPlaybackFailure.startFailed,
        );
      }
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double value) => _player.setVolume(value * 100);

  @override
  Future<void> setOutputDevice(AudioOutputDevice device) async {
    await _player.setAudioDevice(AudioDevice(device.id, device.description));
    _setOutputState(
      AudioOutputState(devices: _outputState.devices, selectedDevice: device),
    );
  }

  @override
  Future<void> stop() async {
    _request += 1;
    await _player.stop();
    await _configureExternalAudio(null);
    _update(
      position: Duration.zero,
      isPlaying: false,
      isBuffering: false,
      isCompleted: false,
      clearError: true,
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _request += 1;
    await Future.wait<void>(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await _player.dispose();
    await _states.close();
    await _outputStates.close();
  }

  Future<void> _configureProxyFor(String url) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    final proxy = DesktopProxyEnvironment.proxyUrlFor(
      Uri.parse(url),
      environment: _proxyEnvironment,
    );
    await platform.setProperty(
      'stream-lavf-o',
      proxy == null ? '' : 'http_proxy=$proxy',
    );
  }

  Future<void> _configureExternalAudio(String? url) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('audio-file', url ?? '');
    }
  }

  Future<void> _waitUntilMediaIsSeekable() async {
    if (_player.state.duration > Duration.zero) {
      return;
    }
    await _player.stream.duration
        .firstWhere((duration) => duration > Duration.zero)
        .timeout(const Duration(seconds: 15));
  }

  void _update({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    AudioPlaybackFailure? error,
    bool clearError = false,
  }) {
    if (_isDisposed) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      position: position,
      duration: duration,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      isCompleted: isCompleted,
      error: error,
      clearError: clearError,
    );
    _states.add(_snapshot);
  }

  void _updateOutputDevice(AudioDevice device) {
    _setOutputState(
      AudioOutputState(
        devices: _outputState.devices,
        selectedDevice: _outputDeviceFor(device),
      ),
    );
  }

  void _updateOutputDevices(List<AudioDevice> devices) {
    _setOutputState(_outputStateFor(devices, _player.state.audioDevice));
  }

  AudioOutputState _outputStateFor(
    List<AudioDevice> devices,
    AudioDevice selectedDevice,
  ) {
    final outputDevices = devices.map(_outputDeviceFor).toList(growable: false);
    final selected = _outputDeviceFor(selectedDevice);
    AudioOutputDevice? selectedOutputDevice;
    for (final device in outputDevices) {
      if (device.id == selected.id) {
        selectedOutputDevice = device;
        break;
      }
    }
    return AudioOutputState(
      devices: outputDevices,
      selectedDevice: selectedOutputDevice ?? selected,
    );
  }

  AudioOutputDevice _outputDeviceFor(AudioDevice device) =>
      AudioOutputDevice(id: device.name, description: device.description);

  void _setOutputState(AudioOutputState state) {
    if (_isDisposed) {
      return;
    }
    _outputState = state;
    _outputStates.add(state);
  }
}
