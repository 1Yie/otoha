import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:otoha/src/app/theme.dart';
import 'package:otoha/src/models/catalog.dart';
import 'package:otoha/src/services/audio_playback_engine.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';
import 'package:otoha/src/widgets/player_bar.dart';

void main() {
  testWidgets('buffering rail stays visible until playback progress begins', (
    tester,
  ) async {
    final engine = _BufferingAudioPlaybackEngine();
    final player = PlayerController(<Track>[
      _youtubeTrack(),
    ], audioPlaybackEngine: engine);
    final shell = ShellController();
    addTearDown(player.dispose);
    addTearDown(shell.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MusicPlayerBar(
            playerController: player,
            shellController: shell,
          ),
        ),
      ),
    );

    player.selectTrack(player.currentTrack!);
    await tester.pump();

    expect(find.byKey(const Key('player-progress-buffering')), findsOneWidget);
    expect(find.byKey(const Key('player-progress-elapsed')), findsNothing);
    expect(find.text('Artist - Album'), findsOneWidget);
    expect(find.text('Buffering audio...'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('player-play')),
        matching: find.byIcon(Icons.pause_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('player-play')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('player-play')),
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('player-play')));
    await tester.pump();

    engine.emit(
      const AudioPlaybackSnapshot(isPlaying: true, isBuffering: true),
    );
    await tester.pump();

    expect(find.byKey(const Key('player-progress-buffering')), findsOneWidget);
    expect(find.byKey(const Key('player-progress-elapsed')), findsNothing);

    engine.emit(
      const AudioPlaybackSnapshot(
        position: Duration(milliseconds: 200),
        isPlaying: true,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('player-progress-buffering')), findsNothing);
    expect(find.byKey(const Key('player-progress-elapsed')), findsOneWidget);
  });

  testWidgets('uses MiSans with tabular elapsed and total time', (
    tester,
  ) async {
    final player = PlayerController(<Track>[_youtubeTrack()]);
    final shell = ShellController();
    addTearDown(player.dispose);
    addTearDown(shell.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildOtohaTheme(),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MusicPlayerBar(
            playerController: player,
            shellController: shell,
          ),
        ),
      ),
    );

    final timeStyle = tester
        .widget<Text>(find.byKey(const Key('player-time')))
        .style;
    expect(timeStyle?.fontFamily, 'MiSans');
    expect(timeStyle?.fontFeatures, const <FontFeature>[
      FontFeature.tabularFigures(),
    ]);
  });

  testWidgets('does not truncate playback times above one hundred minutes', (
    tester,
  ) async {
    final engine = _BufferingAudioPlaybackEngine();
    final player = PlayerController(<Track>[
      _youtubeTrack(durationSeconds: 6671),
    ], audioPlaybackEngine: engine);
    final shell = ShellController();
    addTearDown(player.dispose);
    addTearDown(shell.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MusicPlayerBar(
            playerController: player,
            shellController: shell,
          ),
        ),
      ),
    );

    player.selectTrack(player.currentTrack!);
    player.seekTo(const Duration(minutes: 100, seconds: 1).inSeconds);
    await tester.pump();

    expect(find.text('100:01 / 111:11'), findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byKey(const Key('player-time')),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('uses video-specific errors for video tracks', (tester) async {
    final engine = _BufferingAudioPlaybackEngine();
    final player = PlayerController(<Track>[
      _youtubeTrack(isVideo: true),
    ], audioPlaybackEngine: engine);
    final shell = ShellController();
    addTearDown(player.dispose);
    addTearDown(shell.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MusicPlayerBar(
            playerController: player,
            shellController: shell,
          ),
        ),
      ),
    );

    player.selectTrack(player.currentTrack!);
    await tester.pump();
    engine.emit(
      const AudioPlaybackSnapshot(
        error: AudioPlaybackFailure.engineCouldNotPlay,
      ),
    );
    await tester.pump();
    engine.emit(
      const AudioPlaybackSnapshot(
        error: AudioPlaybackFailure.engineCouldNotPlay,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(player.playbackError, AudioPlaybackFailure.engineCouldNotPlay);
    expect(find.text('The video engine could not play this video.'), findsOne);
    expect(find.textContaining('audio engine'), findsNothing);
  });

  testWidgets('offers an explicit audio and video mode switch', (tester) async {
    final engine = _BufferingAudioPlaybackEngine();
    final player = PlayerController(<Track>[
      _youtubeTrack(videoAvailable: true),
    ], audioPlaybackEngine: engine);
    final shell = ShellController();
    addTearDown(player.dispose);
    addTearDown(shell.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MusicPlayerBar(
            playerController: player,
            shellController: shell,
          ),
        ),
      ),
    );

    player.selectTrack(player.currentTrack!);
    await tester.pump();
    expect(player.currentTrack?.isVideo, isFalse);
    expect(find.byTooltip('Switch to video'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('player-media-mode')),
        matching: find.byIcon(Icons.videocam_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('player-media-mode')));
    await tester.pump();
    expect(player.currentTrack?.isVideo, isTrue);
    expect(find.byTooltip('Switch to audio'), findsOneWidget);
  });
}

Track _youtubeTrack({
  int durationSeconds = 180,
  bool isVideo = false,
  bool videoAvailable = false,
}) {
  return Track(
    id: 'youtube:buffering-track',
    title: 'Buffering track',
    artist: 'Artist',
    album: 'Album',
    artworkAsset: 'assets/artwork/cover_01.png',
    durationSeconds: durationSeconds,
    lyrics: const <String>[],
    youtubeVideoId: 'buffering-track',
    isVideo: isVideo,
    videoAvailable: videoAvailable,
  );
}

class _BufferingAudioPlaybackEngine implements AudioPlaybackEngine {
  final StreamController<AudioPlaybackSnapshot> _states =
      StreamController<AudioPlaybackSnapshot>.broadcast();
  final StreamController<AudioOutputState> _outputStates =
      StreamController<AudioOutputState>.broadcast();

  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;

  @override
  AudioOutputState get outputState => const AudioOutputState();

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
  }) async {}

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
  Future<void> setVolume(double value) async {}

  @override
  Future<void> setOutputDevice(AudioOutputDevice device) async {}

  @override
  Future<void> stop() async {}
}
