import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:otoha/src/models/catalog.dart';
import 'package:otoha/src/services/audio_playback_engine.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';
import 'package:otoha/src/widgets/player_bar.dart';

void main() {
  testWidgets('buffering pulses the progress rail without replacing metadata', (
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

    engine.emit(const AudioPlaybackSnapshot(isPlaying: true));
    await tester.pump();

    expect(find.byKey(const Key('player-progress-buffering')), findsNothing);
    expect(find.byKey(const Key('player-progress-elapsed')), findsOneWidget);
  });

  testWidgets('uses a monospaced font for elapsed and total time', (
    tester,
  ) async {
    final player = PlayerController(<Track>[_youtubeTrack()]);
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

    expect(
      tester
          .widget<Text>(find.byKey(const Key('player-time')))
          .style
          ?.fontFamily,
      'monospace',
    );
  });
}

Track _youtubeTrack() {
  return const Track(
    id: 'youtube:buffering-track',
    title: 'Buffering track',
    artist: 'Artist',
    album: 'Album',
    artworkAsset: 'assets/artwork/cover_01.png',
    durationSeconds: 180,
    lyrics: <String>[],
    youtubeVideoId: 'buffering-track',
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
  Future<void> dispose() async {
    await _states.close();
    await _outputStates.close();
  }

  void emit(AudioPlaybackSnapshot state) => _states.add(state);

  @override
  Future<void> open(
    String videoId, {
    Duration initialPosition = Duration.zero,
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
