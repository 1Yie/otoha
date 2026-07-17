import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:otoha/src/app/theme.dart';
import 'package:otoha/src/models/catalog.dart';
import 'package:otoha/src/services/audio_playback_engine.dart';
import 'package:otoha/src/state/app_locale_controller.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';
import 'package:otoha/src/widgets/video_playback_overlay.dart';

void main() {
  const windowManagerChannel = MethodChannel('window_manager');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
  });

  testWidgets('video overlay keeps a close path without a native surface', (
    tester,
  ) async {
    final shellController = ShellController()..openExpandedMedia();
    addTearDown(shellController.dispose);
    const track = Track(
      id: 'youtube:video-id',
      title: 'Live session',
      artist: 'Channel',
      album: 'YouTube Music',
      artworkAsset: '',
      durationSeconds: 240,
      lyrics: <String>[],
      youtubeVideoId: 'video-id',
      isVideo: true,
    );
    final playerController = PlayerController(const <Track>[track]);
    addTearDown(playerController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocaleController.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: VideoPlaybackOverlay(
          track: track,
          playerController: playerController,
          shellController: shellController,
        ),
      ),
    );

    expect(find.byKey(const Key('video-playback-overlay')), findsOneWidget);
    expect(
      find.byKey(const Key('video-playback-surface-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Live session'), findsOneWidget);
    expect(find.byKey(const Key('video-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('video-playback-progress')), findsOneWidget);
    expect(find.byKey(const Key('video-volume')), findsOneWidget);
    expect(find.byKey(const Key('video-switch-to-audio')), findsOneWidget);
    expect(find.byKey(const Key('video-playback-drag-area')), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    final closeButton = tester.widget<IconButton>(
      find.byKey(const Key('close-video-playback')),
    );
    expect(
      closeButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
      OtohaColors.text,
    );

    await tester.tap(find.byKey(const Key('video-play-pause')));
    await tester.pump();
    expect(playerController.isPlaying, isTrue);
    await tester.tap(find.byKey(const Key('video-play-pause')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('close-video-playback')));
    await tester.pump();

    expect(shellController.isExpandedLyricsOpen, isFalse);

    shellController.openExpandedMedia();
    await tester.pump();
    await tester.tap(find.byKey(const Key('video-switch-to-audio')));
    await tester.pump();
    expect(playerController.currentTrack?.isVideo, isFalse);
    expect(shellController.isExpandedLyricsOpen, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('video overlay uses video-specific playback errors', (
    tester,
  ) async {
    const track = Track(
      id: 'youtube:video-id',
      title: 'Live session',
      artist: 'Channel',
      album: 'YouTube Music',
      artworkAsset: '',
      durationSeconds: 240,
      lyrics: <String>[],
      youtubeVideoId: 'video-id',
      isVideo: true,
    );
    final engine = _FailingPlaybackEngine();
    addTearDown(engine.dispose);
    final playerController = PlayerController(const <Track>[
      track,
    ], audioPlaybackEngine: engine);
    addTearDown(playerController.dispose);
    final shellController = ShellController()..openExpandedMedia();
    addTearDown(shellController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocaleController.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: VideoPlaybackOverlay(
          track: track,
          playerController: playerController,
          shellController: shellController,
        ),
      ),
    );

    playerController.togglePlaying();
    await tester.pump();

    expect(
      find.text('YouTube did not provide a playable video stream.'),
      findsOneWidget,
    );
    expect(find.textContaining('audio engine'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop fullscreen keeps the mounted video state in place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var nativeFullscreen = false;
    final fullscreenValues = <bool>[];
    final windowMethods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          windowMethods.add(call.method);
          switch (call.method) {
            case 'isFullScreen':
              return nativeFullscreen;
            case 'setFullScreen':
              final arguments = call.arguments! as Map<Object?, Object?>;
              nativeFullscreen = arguments['isFullScreen']! as bool;
              fullscreenValues.add(nativeFullscreen);
              return null;
          }
          throw MissingPluginException('Unexpected call: ${call.method}');
        });
    final shellController = ShellController()..openExpandedMedia();
    addTearDown(shellController.dispose);
    const track = Track(
      id: 'youtube:video-id',
      title: 'Live session',
      artist: 'Channel',
      album: 'YouTube Music',
      artworkAsset: '',
      durationSeconds: 240,
      lyrics: <String>[],
      youtubeVideoId: 'video-id',
      isVideo: true,
    );
    final playerController = PlayerController(const <Track>[track]);
    addTearDown(playerController.dispose);
    final videoState = _FakeVideoState();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocaleController.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: VideoPlaybackOverlay(
          track: track,
          playerController: playerController,
          shellController: shellController,
          videoStateOverride: videoState,
        ),
      ),
    );
    await tester.pumpAndSettle();
    windowMethods.clear();

    tester
        .widget<IconButton>(find.byKey(const Key('video-fullscreen')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(videoState.toggleCalls, 0);
    expect(windowMethods, <String>['isFullScreen', 'setFullScreen']);
    expect(fullscreenValues, <bool>[true]);
    expect(nativeFullscreen, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const Key('video-fullscreen')),
        matching: find.byIcon(Icons.fullscreen_exit_rounded),
      ),
      findsOneWidget,
    );

    nativeFullscreen = false;
    await _emitWindowEvent(tester, 'leave-full-screen');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('video-fullscreen')),
        matching: find.byIcon(Icons.fullscreen_rounded),
      ),
      findsOneWidget,
    );
    nativeFullscreen = true;
    await _emitWindowEvent(tester, 'enter-full-screen');
    await tester.pump();

    tester
        .widget<IconButton>(find.byKey(const Key('close-video-playback')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(nativeFullscreen, isFalse);
    expect(fullscreenValues, <bool>[true, false]);
    expect(videoState.exitCalls, 0);
    expect(shellController.isExpandedLyricsOpen, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _emitWindowEvent(WidgetTester tester, String eventName) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'window_manager',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onEvent', <String, Object?>{'eventName': eventName}),
    ),
    (_) {},
  );
}

class _FakeVideoState extends VideoState {
  int toggleCalls = 0;
  int exitCalls = 0;
  bool fullscreen = false;

  @override
  bool isFullscreen() => fullscreen;

  @override
  Future<void> toggleFullscreen() async {
    toggleCalls += 1;
    fullscreen = !fullscreen;
  }

  @override
  Future<void> exitFullscreen() async {
    exitCalls += 1;
    fullscreen = false;
  }
}

class _FailingPlaybackEngine implements AudioPlaybackEngine {
  final StreamController<AudioPlaybackSnapshot> _states =
      StreamController<AudioPlaybackSnapshot>.broadcast();

  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;

  @override
  AudioOutputState get outputState => const AudioOutputState();

  @override
  Stream<AudioOutputState> get outputStates => const Stream.empty();

  @override
  VideoController? get videoController => null;

  @override
  Future<void> open(
    String videoId, {
    Duration initialPosition = Duration.zero,
    bool isVideo = false,
    bool autoplay = true,
  }) async {
    _states.add(
      const AudioPlaybackSnapshot(
        error: AudioPlaybackFailure.streamUnavailable,
      ),
    );
  }

  @override
  Future<void> openLocalFile(
    String path, {
    Duration initialPosition = Duration.zero,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setOutputDevice(AudioOutputDevice device) async {}

  @override
  Future<void> setVolume(double value) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _states.close();
}
