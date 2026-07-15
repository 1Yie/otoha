import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
