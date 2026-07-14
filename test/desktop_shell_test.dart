import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otoha/src/app/otoha_app.dart';
import 'package:otoha/src/app/theme.dart';
import 'package:otoha/src/data/mock_catalog.dart';
import 'package:otoha/src/models/catalog.dart';
import 'package:otoha/src/models/offline_library.dart';
import 'package:otoha/src/services/credential_store.dart';
import 'package:otoha/src/services/offline_library_store.dart';
import 'package:otoha/src/services/youtube_sidecar_client.dart';
import 'package:otoha/src/state/app_locale_controller.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';
import 'package:otoha/src/state/offline_library_controller.dart';
import 'package:otoha/src/state/youtube_library_controller.dart';
import 'package:otoha/src/widgets/player_bar.dart';
import 'package:otoha/src/widgets/expanded_lyrics.dart';
import 'package:otoha/src/widgets/search_palette.dart';

void main() {
  testWidgets('production startup does not expose mock player data', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    final offlineController = OfflineLibraryController(
      store: _MemoryOfflineLibraryStore(),
      youtubeLibraryController: libraryController,
    );
    addTearDown(libraryController.dispose);
    addTearDown(offlineController.dispose);

    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        offlineLibraryController: offlineController,
      ),
    );
    await tester.pump();

    expect(offlineController.isInitialized, isTrue);
    expect(find.text('Soft Signal'), findsNothing);
    expect(find.text('No track selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-queue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel-queue-empty')), findsOneWidget);
  });

  testWidgets('workspace navigation keeps the selected player track', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.tap(find.byKey(const Key('player-queue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('After Image').first);
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-explore')));
    await tester.pumpAndSettle();

    expect(find.text('Explore'), findsWidgets);
    expect(find.byKey(const Key('player-track')), findsOneWidget);
    expect(find.text('After Image'), findsWidgets);
  });

  testWidgets('desktop playback shortcuts control the current queue', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byTooltip('Repeat off (/)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('After Image'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('Soft Signal'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(find.byTooltip('Repeat all (/)'), findsOneWidget);
  });

  testWidgets('playback shortcuts do not intercept search input', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-field')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Soft Signal'), findsWidgets);
    expect(find.byTooltip('Repeat off (/)'), findsOneWidget);
  });

  testWidgets('Your Space opens distinct offline downloads and playlists', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    final offlineController = OfflineLibraryController(
      store: _MemoryOfflineLibraryStore(),
      youtubeLibraryController: libraryController,
    );
    addTearDown(libraryController.dispose);
    addTearDown(offlineController.dispose);
    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        offlineLibraryController: offlineController,
      ),
    );

    await tester.tap(find.byKey(const Key('sidebar-downloads')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-library-scroll')), findsOneWidget);
    expect(find.byKey(const Key('offline-library-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-playlists')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-playlists-scroll')), findsOneWidget);
    expect(find.byKey(const Key('offline-playlists-empty')), findsOneWidget);
  });

  testWidgets('download deletion requires confirmation', (tester) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    final download = DownloadedTrack(
      videoId: 'download-video',
      title: 'Downloaded track',
      artist: 'Artist',
      album: 'Album',
      artworkAsset: 'assets/artwork/cover_01.png',
      durationSeconds: 180,
      filePath: '/tmp/download-video.webm',
      mimeType: 'audio/webm',
      downloadedAt: DateTime(2026),
    );
    final store = _MemoryOfflineLibraryStore(
      OfflineLibrarySnapshot(
        downloads: <DownloadedTrack>[download],
        playlists: <OfflinePlaylist>[
          OfflinePlaylist(
            id: 'playlist-id',
            name: 'Offline playlist',
            trackVideoIds: const <String>['download-video'],
            createdAt: DateTime(2026),
          ),
        ],
      ),
    );
    final offlineController = OfflineLibraryController(
      store: store,
      youtubeLibraryController: libraryController,
    );
    addTearDown(libraryController.dispose);
    addTearDown(offlineController.dispose);
    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        offlineLibraryController: offlineController,
      ),
    );

    await tester.tap(find.byKey(const Key('sidebar-downloads')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offline-add-download-video')));
    await tester.pumpAndSettle();
    final playlistOption = find.byKey(
      const Key('offline-playlist-option-playlist-id'),
    );
    expect(playlistOption, findsOneWidget);
    expect(
      find.byKey(const Key('offline-playlist-option-artwork-playlist-id')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: playlistOption,
        matching: find.text('Offline playlist'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: playlistOption, matching: find.text('1 tracks')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offline-delete-download-video')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('delete-download-confirmation')),
      findsOneWidget,
    );
    expect(store.snapshot.downloads, hasLength(1));
    await tester.tap(find.byKey(const Key('cancel-delete-download')));
    await tester.pumpAndSettle();
    expect(store.snapshot.downloads, hasLength(1));
    expect(store.snapshot.playlists.single.trackVideoIds, <String>[
      'download-video',
    ]);

    await tester.tap(find.byKey(const Key('offline-delete-download-video')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-download')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (offlineController.downloads.isEmpty) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(store.snapshot.downloads, isEmpty);
    expect(store.snapshot.playlists.single.trackVideoIds, isEmpty);
    expect(find.byKey(const Key('offline-library-empty')), findsOneWidget);
  });

  testWidgets('offline playlist supports rename and cover selection', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    final downloads = <DownloadedTrack>[
      DownloadedTrack(
        videoId: 'first-video',
        title: 'First track',
        artist: 'Artist one',
        album: 'First album',
        artworkAsset: 'assets/artwork/cover_01.png',
        durationSeconds: 180,
        filePath: '/tmp/first-video.webm',
        mimeType: 'audio/webm',
        downloadedAt: DateTime(2026),
      ),
      DownloadedTrack(
        videoId: 'second-video',
        title: 'Second track',
        artist: 'Artist two',
        album: 'Second album',
        artworkAsset: 'assets/artwork/cover_02.png',
        durationSeconds: 200,
        filePath: '/tmp/second-video.webm',
        mimeType: 'audio/webm',
        downloadedAt: DateTime(2026),
      ),
    ];
    final playlist = OfflinePlaylist(
      id: 'playlist-id',
      name: 'Original name',
      trackVideoIds: const <String>['first-video', 'second-video'],
      createdAt: DateTime(2026),
    );
    final store = _MemoryOfflineLibraryStore(
      OfflineLibrarySnapshot(
        downloads: downloads,
        playlists: <OfflinePlaylist>[playlist],
      ),
    );
    final offlineController = OfflineLibraryController(
      store: store,
      youtubeLibraryController: libraryController,
    );
    addTearDown(libraryController.dispose);
    addTearDown(offlineController.dispose);
    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        offlineLibraryController: offlineController,
      ),
    );

    await tester.tap(find.byKey(const Key('sidebar-playlists')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offline-playlist-playlist-id')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('rename-offline-playlist-playlist-id')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('offline-playlist-rename')),
      'Renamed playlist',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename playlist'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed playlist'), findsOneWidget);
    expect(store.snapshot.playlists.single.name, 'Renamed playlist');

    await tester.tap(
      find.byKey(const Key('choose-offline-playlist-cover-playlist-id')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('offline-playlist-cover-second-video')),
    );
    await tester.pumpAndSettle();

    expect(store.snapshot.playlists.single.artworkVideoId, 'second-video');

    await tester.tap(
      find.byKey(const Key('delete-offline-playlist-playlist-id')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('delete-offline-playlist-confirmation')),
      findsOneWidget,
    );
    expect(store.snapshot.playlists, hasLength(1));

    await tester.tap(find.byKey(const Key('confirm-delete-offline-playlist')));
    await tester.pumpAndSettle();

    expect(store.snapshot.playlists, isEmpty);
    expect(find.byKey(const Key('offline-playlists-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-offline-playlist')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('offline-playlist-name')),
      'Created playlist',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create playlist'));
    for (final elapsed in <Duration>[
      Duration.zero,
      const Duration(milliseconds: 16),
      const Duration(milliseconds: 80),
      const Duration(milliseconds: 160),
    ]) {
      await tester.pump(elapsed);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    expect(store.snapshot.playlists.single.name, 'Created playlist');
  });

  testWidgets(
    'command palette searches the local catalog and selects a track',
    (tester) async {
      await _setDesktopSurface(tester);
      await _pumpSignedOutApp(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search-field')), 'room');
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('search-result-track-room-for-light')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-field')), findsNothing);
      expect(find.text('Room for Light'), findsWidgets);
    },
  );

  testWidgets('search palette rows support scaled desktop text', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final workspaceController = WorkspaceController();
    final playerController = PlayerController(MockCatalog.tracks);
    final shellController = ShellController();
    final libraryController = _signedOutLibraryController();
    addTearDown(workspaceController.dispose);
    addTearDown(playerController.dispose);
    addTearDown(shellController.dispose);
    addTearDown(libraryController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildOtohaTheme(),
        supportedLocales: AppLocaleController.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              SearchPalette(
                workspaceController: workspaceController,
                playerController: playerController,
                shellController: shellController,
                youtubeLibraryController: libraryController,
                reduceMotion: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('queue panel opens without removing the shell', (tester) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.tap(find.byKey(const Key('player-queue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel-queue')), findsOneWidget);
    expect(find.byKey(const Key('player-lyrics')), findsNothing);
    expect(find.byKey(const Key('player-track')), findsOneWidget);
  });

  testWidgets('queue rows contain long artist names without overflow', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    const longArtist =
        'A very long artist name with multiple collaborators and guests';
    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        initialTracks: const <Track>[
          Track(
            id: 'long-queue-track',
            title: 'A track with constrained queue metadata',
            artist: longArtist,
            album: 'Queue regression',
            artworkAsset: 'assets/artwork/cover_01.png',
            durationSeconds: 180,
            lyrics: <String>[],
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('player-queue')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final artistText = tester.widget<Text>(find.text(longArtist));
    expect(artistText.maxLines, 1);
    expect(artistText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('volume adjustment opens from the player control', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    expect(find.byKey(const Key('player-volume-slider')), findsNothing);

    await tester.tap(find.byKey(const Key('player-volume')));
    await tester.pump();

    expect(find.byKey(const Key('player-volume-popup')), findsOneWidget);
    expect(find.byKey(const Key('player-volume-slider')), findsOneWidget);
  });

  testWidgets('output device control is directly available in the player bar', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.tap(find.byKey(const Key('player-devices')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('panel-devices-unavailable')), findsOneWidget);
  });

  testWidgets('profile opens YouTube authentication panel', (tester) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('panel-account')), findsOneWidget);
    expect(find.byKey(const Key('youtube-cookie-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('youtube-cookie-field')),
      'SID=test-cookie',
    );
    await tester.pump();

    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('youtube-cookie-submit')),
    );
    expect(submit.onPressed, isNotNull);
  });

  testWidgets('signed-in account drawer keeps its avatar at 64 pixels', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-connected')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('youtube-account-avatar'))),
      const Size(64, 64),
    );
  });

  testWidgets('signed-out Library opens the account panel', (tester) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('youtube-library-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('panel-account')), findsOneWidget);
  });

  testWidgets('Settings switches the app between English and Chinese', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    final localeController = AppLocaleController(
      initialLocale: const Locale('en'),
    );
    addTearDown(libraryController.dispose);
    addTearDown(localeController.dispose);
    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        localeController: localeController,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.byKey(const Key('language-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simplified Chinese').last);
    await tester.pumpAndSettle();

    expect(localeController.locale, const Locale('zh'));
    expect(find.text('设置'), findsWidgets);
    expect(find.text('动画'), findsOneWidget);
  });

  testWidgets('Settings displays the app icon and package version', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    PackageInfo.setMockInitialValues(
      appName: 'Otoha',
      packageName: 'im.ingstar.otoha',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-about')), findsOneWidget);
    expect(find.byKey(const Key('settings-about-icon')), findsOneWidget);
    final aboutCard = find.byKey(const Key('settings-about'));
    expect(
      find.descendant(of: aboutCard, matching: find.text('Otoha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: aboutCard, matching: find.text('Version 1.0.0')),
      findsOneWidget,
    );
  });

  testWidgets('signed-in Home and Explore use YouTube feed data', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    expect(find.byKey(const Key('youtube-home-feed')), findsOneWidget);
    expect(find.text('Listen again'), findsOneWidget);
    expect(find.byKey(const Key('youtube-feed-scroll-left-0')), findsOneWidget);
    expect(
      find.byKey(const Key('youtube-feed-scroll-right-0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('youtube-feed-song-feed-home-item')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'Live recommendation',
    );

    await tester.tap(find.byKey(const Key('sidebar-explore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-explore-feed')), findsOneWidget);
    expect(
      find.byKey(
        const Key(
          'youtube-explore-tab-FEmusic_moods_and_genres_category:chill-params',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key(
          'youtube-explore-tab-FEmusic_moods_and_genres_category:pop-params',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Moods & genres'), findsNothing);
    expect(find.text('New releases'), findsOneWidget);
    expect(find.text('Fresh album'), findsOneWidget);
    expect(find.byKey(const Key('youtube-explore-end')), findsNothing);
    await tester.tap(
      find.byKey(
        const Key(
          'youtube-explore-tab-FEmusic_moods_and_genres_category:chill-params',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-explore-feed')), findsOneWidget);
    expect(find.text('Chill picks'), findsOneWidget);
    expect(find.byKey(const Key('youtube-explore-feed-back')), findsNothing);
  });

  testWidgets('switching to a YouTube track preloads lyrics before full view', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('youtube-feed-song-feed-home-item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expanded-lyrics-overlay')), findsNothing);
    expect(libraryController.lyricsVideoId, 'video-home-item');
    expect(libraryController.lyricsLines, isNotEmpty);
    expect(
      (tester.widget<IconButton>(find.byKey(const Key('player-play'))).icon
              as Icon)
          .icon,
      Icons.pause_rounded,
    );
  });

  testWidgets(
    'full lyrics shows loading while a track lyric request is pending',
    (tester) async {
      await _setDesktopSurface(tester);
      final lyricsResponse = Completer<Map<String, Object?>>();
      final libraryController = _signedOutLibraryController(
        lyricsResponse: lyricsResponse.future,
      );
      addTearDown(libraryController.dispose);
      await libraryController.signInWithCookie('SID=test-cookie');
      await tester.pumpWidget(
        OtohaApp(youtubeLibraryController: libraryController),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('youtube-feed-song-feed-home-item')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-track')));
      await tester.pump();

      expect(find.byKey(const Key('expanded-lyrics-overlay')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      lyricsResponse.complete(<String, Object?>{
        'lines': <Object?>[
          <String, Object?>{'text': 'Loaded line', 'startSeconds': 1.0},
        ],
      });
      await tester.pumpAndSettle();

      expect(find.text('Loaded line'), findsOneWidget);
    },
  );

  testWidgets('Explore category tabs show progress while loading', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final browseResponse = Completer<Map<String, Object?>>();
    final libraryController = _signedOutLibraryController(
      browseResponse: browseResponse.future,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-explore')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key(
          'youtube-explore-tab-FEmusic_moods_and_genres_category:chill-params',
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    browseResponse.complete(
      _feedResult(
        section: 'Chill picks',
        id: 'chill-playlist',
        title: 'Chill playlist',
        itemType: 'playlist',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Chill picks'), findsOneWidget);
  });

  testWidgets('History loads authenticated playback records and plays them', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-history')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-history-workspace')), findsOneWidget);
    expect(find.text('History track'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('youtube-history-track-history-video')),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'History track',
    );
  });

  testWidgets('History refresh shows a loading line', (tester) async {
    await _setDesktopSurface(tester);
    final refreshedHistory = Completer<Map<String, Object?>>();
    final libraryController = _signedOutLibraryController(
      historyResponses: <Future<Map<String, Object?>>>[
        Future<Map<String, Object?>>.value(_historyResult()),
        refreshedHistory.future,
      ],
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-history-scroll')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('youtube-history-refresh')),
        matching: find.byType(CustomScrollView),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('youtube-history-refresh')));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    refreshedHistory.complete(_historyResult());
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('YouTube player omits rating and comment controls', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('youtube-feed-song-feed-home-item')));
    await tester.pump();
    expect(find.byKey(const Key('player-like')), findsNothing);
    expect(find.byKey(const Key('player-dislike')), findsNothing);
    expect(find.byKey(const Key('player-comments')), findsNothing);
    expect(find.byKey(const Key('player-queue')), findsOneWidget);
  });

  testWidgets('Library playlist details use the shared music track rows', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-library-scroll')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('youtube-library-refresh')),
        matching: find.byType(CustomScrollView),
      ),
      findsOneWidget,
    );
    expect(find.text('YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Your playlists'), findsOneWidget);
    final playlistCard = find.byKey(const Key('youtube-playlist-PL1'));
    expect(tester.widget<Material>(playlistCard).clipBehavior, Clip.antiAlias);
    expect(
      tester.getSize(
        find.descendant(of: playlistCard, matching: find.byType(InkWell)),
      ),
      tester.getSize(playlistCard),
    );
    await tester.tap(find.byKey(const Key('youtube-playlist-PL1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('youtube-playlist-detail-scroll')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('youtube-track-video-1')), findsOneWidget);
    expect(find.byKey(const Key('youtube-track-video-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('youtube-track-video-2')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'City lights',
    );
    expect(
      find.byKey(const Key('youtube-track-selected-video-2')),
      findsOneWidget,
    );
  });

  testWidgets('subscriber cards open a browsable selection list', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('youtube-feed-profile-artwork-subscriber-id')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const Key('youtube-feed-profile-artwork-subscriber-id')),
      ),
      const Size(168, 168),
    );
    expect(
      tester.getSize(
        find.byKey(const Key('youtube-feed-artist-subscriber-id')),
      ),
      const Size(168, 224),
    );
    expect(
      tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.byKey(
                    const Key('youtube-feed-artist-subscriber-id'),
                  ),
                  matching: find.byType(Material),
                )
                .first,
          )
          .clipBehavior,
      Clip.antiAlias,
    );
    await tester.tap(
      find.byKey(const Key('youtube-feed-artist-subscriber-id')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-feed-browse-detail')), findsOneWidget);
    expect(find.text('Subscriber picks'), findsOneWidget);
  });

  testWidgets('search palette returns YouTube Music results when signed in', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-trigger')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'remote');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('search-result-youtube-song-remote-track')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'Remote result',
    );
  });

  testWidgets('album detail selection preserves card artist metadata', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-explore')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('youtube-feed-album-feed-explore-item')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('youtube-feed-detail-track-album-track-1')),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('youtube-track-selected-album-track-1')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.byKey(
                    const Key('youtube-feed-detail-track-album-track-1'),
                  ),
                  matching: find.byType(Material),
                )
                .first,
          )
          .clipBehavior,
      Clip.antiAlias,
    );
    expect(find.text('Artist - Fresh album'), findsOneWidget);
  });

  testWidgets('top progress rail expands on hover', (tester) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    final progress = find.byKey(const Key('player-progress'));
    expect(
      tester.getTopLeft(progress).dy,
      tester.getTopLeft(find.byKey(const Key('player-bar'))).dy,
    );
    expect(find.byKey(const Key('player-progress-thumb')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(progress));
    await tester.pump();

    expect(find.byKey(const Key('player-progress-thumb')), findsOneWidget);

    final scrub = await tester.startGesture(tester.getCenter(progress));
    await tester.pump();

    expect(
      find.byKey(const Key('player-progress-thumb-selected')),
      findsOneWidget,
    );

    await scrub.up();
  });

  testWidgets('zero-duration metadata keeps player progress finite', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final playerController = PlayerController(const <Track>[
      Track(
        id: 'unknown-duration',
        title: 'Unknown duration',
        artist: 'Artist',
        album: 'YouTube Music',
        artworkAsset: '',
        durationSeconds: 0,
        lyrics: <String>[],
      ),
    ]);
    final shellController = ShellController();
    final libraryController = _signedOutLibraryController();
    addTearDown(playerController.dispose);
    addTearDown(shellController.dispose);
    addTearDown(libraryController.dispose);
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
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MusicPlayerBar(
              playerController: playerController,
              shellController: shellController,
            ),
          ),
        ),
      ),
    );

    final progress = find.byKey(const Key('player-progress'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(progress));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('player-progress-thumb')), findsOneWidget);
  });

  testWidgets('centered now playing opens and closes full lyrics', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.tap(find.byKey(const Key('player-now-playing')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expanded-lyrics-overlay')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('expanded-lyrics-overlay'))).top,
      0,
    );
    final overlayRect = tester.getRect(
      find.byKey(const Key('expanded-lyrics-overlay')),
    );
    final closeRect = tester.getRect(
      find.byKey(const Key('expanded-lyrics-close')),
    );
    expect(closeRect.top, 4);
    expect(closeRect.right, overlayRect.right - 8);

    await tester.tap(find.byKey(const Key('expanded-lyrics-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expanded-lyrics-overlay')), findsNothing);
  });

  testWidgets('expanded lyrics use the current player track and remote text', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final playerController = PlayerController(<Track>[
      const Track(
        id: 'dQw4w9WgXcQ',
        title: 'Bottom player title',
        artist: 'Bottom player artist',
        album: 'Bottom player album',
        artworkAsset:
            'https://lh3.googleusercontent.com/cover=w544-h544-l90-rj',
        durationSeconds: 213,
        lyrics: <String>[],
      ),
    ]);
    final shellController = ShellController();
    final youtubeLibraryController = _signedOutLibraryController();
    addTearDown(playerController.dispose);
    addTearDown(shellController.dispose);
    addTearDown(youtubeLibraryController.dispose);
    await youtubeLibraryController.signInWithCookie('SID=test-cookie');

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
          body: ExpandedLyricsOverlay(
            playerController: playerController,
            shellController: shellController,
            youtubeLibraryController: youtubeLibraryController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('expanded-lyrics-track-title')),
      findsOneWidget,
    );
    expect(find.text('Bottom player title'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(find.byKey(const Key('expanded-lyrics-top-fade')), findsOneWidget);
    expect(
      find.byKey(const Key('expanded-lyrics-bottom-fade')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('expanded-lyrics-top-fade')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('expanded-lyrics-top-fade')),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('expanded-lyrics-scroll-configuration')),
        matching: find.byType(Scrollbar),
      ),
      findsNothing,
    );
    playerController.seekTo(0);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_lyricStyle(tester, 'First line').color, isNot(OtohaColors.accent));
    playerController.seekTo(1);
    await tester.pump();
    expect(_lyricStyle(tester, 'First line').color, OtohaColors.accent);
    playerController.seekTo(2);
    await tester.pump();
    expect(_lyricStyle(tester, 'Second line').color, OtohaColors.accent);
    expect(
      find.descendant(
        of: find.byKey(const Key('expanded-lyrics-overlay')),
        matching: find.byType(VerticalDivider),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('expanded-lyrics-playback-progress')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('expanded-lyrics-drag-area')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('expanded-lyrics-overlay')),
        matching: find.byType(Scrollbar),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('expanded-lyrics-previous')), findsOneWidget);
    expect(
      find.byKey(const Key('expanded-lyrics-toggle-playing')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('expanded-lyrics-next')), findsOneWidget);

    await tester.tap(find.byKey(const Key('expanded-lyrics-toggle-playing')));
    await tester.pump();
    expect(playerController.isPlaying, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const Key('expanded-lyrics-toggle-playing')),
        matching: find.byIcon(Icons.pause_rounded),
      ),
      findsOneWidget,
    );

    final waveform = find.byKey(const Key('expanded-lyrics-playback-progress'));
    await tester.tapAt(tester.getCenter(waveform) + const Offset(120, 0));
    await tester.pump();
    expect(playerController.positionSeconds, greaterThan(0));

    await tester.tap(find.byKey(const Key('expanded-lyrics-toggle-playing')));
    await tester.pump();
    expect(playerController.isPlaying, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const Key('expanded-lyrics-toggle-playing')),
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shell fits at the minimum supported desktop size', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1120, 720));
    await _pumpSignedOutApp(tester);

    expect(find.byKey(const Key('sidebar-home')), findsOneWidget);
    expect(find.byKey(const Key('player-track')), findsOneWidget);
    expect(find.byKey(const Key('player-progress')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('workspace-clip'))).top,
      AppMetrics.titleBarHeight,
    );
    expect(
      tester.getCenter(find.byKey(const Key('player-now-playing'))).dx,
      closeTo(560, 0.1),
    );
  });

  testWidgets('Chinese Queue remains stable at the minimum desktop size', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1120, 720));
    final libraryController = _signedOutLibraryController();
    final localeController = AppLocaleController(
      initialLocale: const Locale('en'),
    );
    addTearDown(libraryController.dispose);
    addTearDown(localeController.dispose);
    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        localeController: localeController,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simplified Chinese').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-queue')));
    await tester.pumpAndSettle();

    expect(find.text('队列'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

TextStyle _lyricStyle(WidgetTester tester, String text) {
  return tester
      .widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text(text),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      )
      .style;
}

YouTubeLibraryController _signedOutLibraryController({
  Future<Map<String, Object?>>? browseResponse,
  List<Future<Map<String, Object?>>>? historyResponses,
  Future<Map<String, Object?>>? lyricsResponse,
}) {
  return YouTubeLibraryController(
    client: _NoopSidecarClient(
      browseResponse: browseResponse,
      historyResponses: historyResponses,
      lyricsResponse: lyricsResponse,
    ),
    credentialStore: _EmptyCredentialStore(),
  );
}

Future<void> _pumpSignedOutApp(WidgetTester tester) async {
  final controller = _signedOutLibraryController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    OtohaApp(
      youtubeLibraryController: controller,
      initialTracks: MockCatalog.tracks,
    ),
  );
}

class _NoopSidecarClient extends YouTubeSidecarClient {
  _NoopSidecarClient({
    this.browseResponse,
    List<Future<Map<String, Object?>>>? historyResponses,
    this.lyricsResponse,
  }) : historyResponses = List<Future<Map<String, Object?>>>.of(
         historyResponses ?? const <Future<Map<String, Object?>>>[],
       );

  final Future<Map<String, Object?>>? browseResponse;
  final List<Future<Map<String, Object?>>> historyResponses;
  final Future<Map<String, Object?>>? lyricsResponse;

  @override
  Stream<SidecarEvent> get events => const Stream<SidecarEvent>.empty();

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    if (method == 'feed.browse' && browseResponse != null) {
      return await browseResponse!;
    }
    if (method == 'history.get' && historyResponses.isNotEmpty) {
      return await historyResponses.removeAt(0);
    }
    if (method == 'lyrics.get' && lyricsResponse != null) {
      return await lyricsResponse!;
    }
    return switch (method) {
      'auth.cookie.signIn' => <String, Object?>{'authenticated': true},
      'library.playlists' => <String, Object?>{
        'playlists': <Object?>[
          <String, Object?>{
            'id': 'PL1',
            'title': 'Road trip',
            'owner': 'Listener',
            'itemCount': '2 songs',
            'thumbnailUrl': 'https://example.test/playlist.jpg',
          },
        ],
      },
      'library.playlist' => <String, Object?>{
        'playlist': <String, Object?>{
          'id': 'PL1',
          'title': 'Road trip',
          'thumbnailUrl': 'https://example.test/playlist.jpg',
        },
        'tracks': <Object?>[
          <String, Object?>{
            'videoId': 'video-1',
            'title': 'Night drive',
            'artists': <String>['Artist'],
            'album': 'Road trip',
            'durationSeconds': 180,
            'thumbnailUrl': null,
          },
          <String, Object?>{
            'videoId': 'video-2',
            'title': 'City lights',
            'artists': <String>['Artist'],
            'album': 'Road trip',
            'durationSeconds': 190,
            'thumbnailUrl': null,
          },
        ],
      },
      'history.get' => _historyResult(),
      'feed.home' => <String, Object?>{
        'sections': <Object?>[
          <String, Object?>{
            'title': 'Listen again',
            'items': <Object?>[
              _feedItem(
                id: 'feed-home-item',
                title: 'Live recommendation',
                itemType: 'song',
                videoId: 'video-home-item',
              ),
            ],
          },
          <String, Object?>{
            'title': 'From subscriptions',
            'items': <Object?>[
              _feedItem(
                id: 'subscriber-id',
                title: 'Subscribed creator',
                itemType: 'artist',
              ),
            ],
          },
        ],
      },
      'feed.explore' => <String, Object?>{
        'sections': <Object?>[
          <String, Object?>{
            'title': 'Moods & genres',
            'items': <Object?>[
              <String, Object?>{
                'id': 'FEmusic_moods_and_genres_category',
                'itemType': 'category',
                'title': 'Chill',
                'subtitle': 'Mood & genre',
                'browseParams': 'chill-params',
                'artists': <String>[],
                'durationSeconds': 0,
              },
              <String, Object?>{
                'id': 'FEmusic_moods_and_genres_category',
                'itemType': 'category',
                'title': 'Pop',
                'subtitle': 'Mood & genre',
                'browseParams': 'pop-params',
                'artists': <String>[],
                'durationSeconds': 0,
              },
            ],
          },
          <String, Object?>{
            'title': 'New releases',
            'items': <Object?>[
              <String, Object?>{
                'id': 'feed-explore-item',
                'itemType': 'album',
                'title': 'Fresh album',
                'subtitle': 'Artist',
                'artists': <String>['Artist'],
                'durationSeconds': 0,
              },
            ],
          },
        ],
      },
      'feed.browse' => _feedResult(
        section: params['id'] == 'subscriber-id'
            ? 'Subscriber picks'
            : 'Chill picks',
        id: 'chill-playlist',
        title: 'Chill playlist',
        itemType: 'playlist',
      ),
      'feed.collection' => <String, Object?>{
        'tracks': <Object?>[
          <String, Object?>{
            'videoId': 'album-track-1',
            'title': 'First album track',
            'artists': <String>[],
            'album': 'Fresh album',
            'durationSeconds': 210,
            'thumbnailUrl': null,
          },
          <String, Object?>{
            'videoId': 'album-track-2',
            'title': 'Second album track',
            'artists': <String>['Artist'],
            'album': 'Fresh album',
            'durationSeconds': 190,
            'thumbnailUrl': null,
          },
        ],
      },
      'search.music' => <String, Object?>{
        'items': <Object?>[
          _feedItem(
            id: 'remote-track',
            title: 'Remote result',
            itemType: 'song',
            videoId: 'remote-video',
          ),
        ],
      },
      'lyrics.get' => <String, Object?>{
        'lines': <Object?>[
          <String, Object?>{'text': 'First line', 'startSeconds': 1.0},
          <String, Object?>{'text': 'Second line', 'startSeconds': 2.0},
        ],
      },
      'interaction.rate' => <String, Object?>{'rating': params['rating']!},
      'comments.get' => <String, Object?>{
        'comments': <Object?>[
          <String, Object?>{
            'id': 'comment-1',
            'author': 'Commenter',
            'text': 'Great track',
            'publishedTime': 'now',
            'avatarUrl': null,
            'likeCount': '1',
          },
        ],
      },
      'comments.create' => const <String, Object?>{'posted': true},
      _ => const <String, Object?>{},
    };
  }

  @override
  Future<void> dispose() async {}
}

Map<String, Object?> _feedResult({
  required String section,
  required String id,
  required String title,
  required String itemType,
  String? videoId,
}) {
  return <String, Object?>{
    'sections': <Object?>[
      <String, Object?>{
        'title': section,
        'items': <Object?>[
          <String, Object?>{
            'id': id,
            'itemType': itemType,
            'title': title,
            'subtitle': 'Artist',
            'videoId': videoId,
            'artists': <String>['Artist'],
            'album': 'Album',
            'durationSeconds': 180,
            'thumbnailUrl': null,
          },
        ],
      },
    ],
  };
}

Map<String, Object?> _historyResult() {
  return <String, Object?>{
    'tracks': <Object?>[
      <String, Object?>{
        'videoId': 'history-video',
        'title': 'History track',
        'artists': <String>['History artist'],
        'album': 'History album',
        'durationSeconds': 213,
        'thumbnailUrl': 'https://example.test/history.jpg',
      },
    ],
  };
}

Map<String, Object?> _feedItem({
  required String id,
  required String title,
  required String itemType,
  String? videoId,
}) {
  return <String, Object?>{
    'id': id,
    'itemType': itemType,
    'title': title,
    'subtitle': 'Artist',
    'videoId': videoId,
    'artists': <String>['Artist'],
    'album': itemType == 'album' ? title : null,
    'durationSeconds': 180,
    'thumbnailUrl': null,
  };
}

class _EmptyCredentialStore implements CredentialStore {
  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _MemoryOfflineLibraryStore implements OfflineLibraryStore {
  _MemoryOfflineLibraryStore([this.snapshot = const OfflineLibrarySnapshot()]);

  OfflineLibrarySnapshot snapshot;

  @override
  Future<String> defaultDownloadDirectory() async => '/tmp/otoha-downloads';

  @override
  Future<OfflineLibrarySnapshot> read() async => snapshot;

  @override
  Future<void> write(OfflineLibrarySnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}

Future<void> _setDesktopSurface(
  WidgetTester tester, [
  Size size = const Size(1440, 896),
]) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
