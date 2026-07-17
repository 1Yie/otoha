import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature, PointerDeviceKind;

import 'package:flutter/foundation.dart';
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
import 'package:otoha/src/models/youtube_library.dart';
import 'package:otoha/src/services/credential_store.dart';
import 'package:otoha/src/services/offline_library_store.dart';
import 'package:otoha/src/services/player_session_store.dart';
import 'package:otoha/src/services/youtube_sidecar_client.dart';
import 'package:otoha/src/state/app_locale_controller.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';
import 'package:otoha/src/state/offline_library_controller.dart';
import 'package:otoha/src/state/youtube_library_controller.dart';
import 'package:otoha/src/widgets/artwork_image.dart';
import 'package:otoha/src/widgets/player_bar.dart';
import 'package:otoha/src/widgets/expanded_lyrics.dart';
import 'package:otoha/src/workspaces/search_workspace.dart';
import 'package:otoha/src/workspaces/youtube_feed_workspace.dart';

void main() {
  testWidgets('restored video stays collapsed until explicitly opened', (
    tester,
  ) async {
    const video = Track(
      id: 'youtube:restored-video',
      title: 'Restored video',
      artist: 'Channel',
      album: 'YouTube Music',
      artworkAsset: '',
      durationSeconds: 180,
      lyrics: <String>[],
      youtubeVideoId: 'restored-video',
      isVideo: true,
    );
    final libraryController = _signedOutLibraryController();
    final store = _FixedPlayerSessionStore(<String, Object?>{
      'catalog': <Object?>[video.toJson()],
      'playOrderIds': <Object?>[video.id],
      'currentTrackId': video.id,
      'positionSeconds': 30,
      'volume': 0.72,
      'isPlaying': false,
      'isShuffled': false,
      'repeatMode': PlaybackRepeatMode.off.name,
    });
    addTearDown(libraryController.dispose);

    await tester.pumpWidget(
      OtohaApp(
        youtubeLibraryController: libraryController,
        playerSessionStore: store,
        initialTracks: const <Track>[video],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restored video'), findsOneWidget);
    expect(find.byKey(const Key('video-playback-overlay')), findsNothing);

    await tester.tap(find.byKey(const Key('player-now-playing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-playback-overlay')), findsOneWidget);
  });

  testWidgets('switching to video slides expanded playback from the bottom', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1120, 720));
    await _pumpVideoCapableApp(
      tester,
      videoId: 'video-transition',
      title: 'Video transition',
    );

    await tester.tap(find.byKey(const Key('player-media-mode')));
    await tester.pump();
    await tester.pump();

    final overlay = find.byKey(const Key('video-playback-overlay'));
    final slide = find.byKey(const Key('expanded-media-slide'));
    expect(overlay, findsOneWidget);
    expect(slide, findsOneWidget);
    expect(tester.widget<SlideTransition>(slide).position.value.dy, 1);

    await tester.pump(const Duration(milliseconds: 140));
    final halfwayOffset = tester
        .widget<SlideTransition>(slide)
        .position
        .value
        .dy;
    expect(halfwayOffset, greaterThan(0));
    expect(halfwayOffset, lessThan(1));

    await tester.pumpAndSettle();
    expect(tester.widget<SlideTransition>(slide).position.value.dy, 0);

    await tester.tap(find.byKey(const Key('close-video-playback')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(overlay, findsOneWidget);
    final closingOffset = tester
        .widget<SlideTransition>(slide)
        .position
        .value
        .dy;
    expect(closingOffset, greaterThan(0));
    expect(closingOffset, lessThan(1));

    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
  });

  testWidgets('reduced motion opens expanded video without transition frames', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1120, 720));
    await _pumpVideoCapableApp(
      tester,
      videoId: 'reduced-video-transition',
      title: 'Reduced video transition',
    );
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reduce-motion-switch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('history-back')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('player-media-mode')));
    await tester.pump();
    await tester.pump();

    final slide = find.byKey(const Key('expanded-media-slide'));
    expect(find.byKey(const Key('video-playback-overlay')), findsOneWidget);
    expect(tester.widget<SlideTransition>(slide).position.value.dy, 0);
  });

  testWidgets('artwork image reads absolute offline cover paths', (
    tester,
  ) async {
    final artwork = File(
      '${Directory.current.path}/assets/artwork/cover_01.png',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ArtworkImage(
          assetPath: artwork.path,
          semanticLabel: 'Offline cover',
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
  });

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('search-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('search-field')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Soft Signal'), findsWidgets);
    expect(find.byTooltip('Repeat off (/)'), findsOneWidget);
  });

  testWidgets('search opens as a workspace and participates in history', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.tap(find.byKey(const Key('search-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('search-workspace')), findsOneWidget);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
    expect(find.byKey(const Key('youtube-home-signed-out')), findsNothing);
    expect(
      find.byType(SegmentedButton<YouTubeMusicSearchFilter>),
      findsNothing,
    );
    final selectedSearchFilter = tester.widget<AnimatedContainer>(
      find.byKey(const Key('search-filter-all')),
    );
    final selectedSearchFilterDecoration =
        selectedSearchFilter.decoration! as BoxDecoration;
    expect(
      selectedSearchFilterDecoration.color,
      OtohaColors.text.withValues(alpha: 0.92),
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('search-filter-all')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('search-field')), 'Home');
    await tester.pump();
    final homeCommand = find.byKey(const Key('search-result-page-home'));
    expect(homeCommand, findsOneWidget);
    expect(
      find.descendant(
        of: homeCommand,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('history-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('search-workspace')), findsNothing);
    expect(find.byKey(const Key('youtube-home-signed-out')), findsOneWidget);
    expect(find.byKey(const Key('history-forward')), findsOneWidget);
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
        if (store.snapshot.downloads.isEmpty) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(store.snapshot.downloads, isEmpty);
    expect(offlineController.downloads, isEmpty);
    expect(store.snapshot.playlists.single.trackVideoIds, isEmpty);
    expect(find.byKey(const Key('offline-library-empty')), findsOneWidget);
  });

  testWidgets('downloads support batch playlist add and confirmed deletion', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    final downloads = <DownloadedTrack>[
      DownloadedTrack(
        videoId: 'first-video',
        title: 'First download',
        artist: 'First artist',
        album: 'First album',
        artworkAsset: 'assets/artwork/cover_01.png',
        durationSeconds: 180,
        filePath: '${Directory.systemTemp.path}/missing-first.webm',
        mimeType: 'audio/webm',
        downloadedAt: DateTime(2026),
      ),
      DownloadedTrack(
        videoId: 'second-video',
        title: 'Second download',
        artist: 'Second artist',
        album: 'Second album',
        artworkAsset: 'assets/artwork/cover_02.png',
        durationSeconds: 200,
        filePath: '${Directory.systemTemp.path}/missing-second.webm',
        mimeType: 'audio/webm',
        downloadedAt: DateTime(2026),
      ),
    ];
    final playlist = OfflinePlaylist(
      id: 'batch-playlist',
      name: 'Batch playlist',
      trackVideoIds: const <String>['first-video'],
      artworkVideoId: 'first-video',
      createdAt: DateTime(2026),
    );
    final store = _MemoryOfflineLibraryStore(
      OfflineLibrarySnapshot(
        downloads: downloads,
        playlists: <OfflinePlaylist>[playlist],
      ),
    );
    final offlineController = _TrackingOfflineLibraryController(
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

    await tester.tap(find.byKey(const Key('offline-selection-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('offline-select-first-video')));
    await tester.tap(find.byKey(const Key('offline-select-second-video')));
    await tester.pump();

    final selectedDownloadRow = find.byKey(
      const Key('offline-track-first-video'),
    );
    final selectedDownloadAction = find.byKey(
      const Key('youtube-track-action-first-video'),
    );
    final selectedDownloadOverlay = find.byKey(
      const Key('youtube-track-selected-first-video'),
    );
    final selectedDownloadCheckbox = find.byKey(
      const Key('offline-select-first-video'),
    );
    expect(
      tester.getRect(selectedDownloadAction),
      tester.getRect(selectedDownloadRow),
    );
    expect(
      tester
          .getRect(selectedDownloadAction)
          .contains(tester.getCenter(selectedDownloadCheckbox)),
      isTrue,
    );
    expect(
      tester.getRect(selectedDownloadOverlay),
      tester.getRect(selectedDownloadRow),
    );
    expect(
      tester
          .getRect(selectedDownloadOverlay)
          .contains(tester.getCenter(selectedDownloadCheckbox)),
      isTrue,
    );
    expect(find.byKey(const Key('offline-selected-count')), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offline-batch-add')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('offline-playlist-option-batch-playlist')),
    );
    await tester.pumpAndSettle();

    expect(store.snapshot.playlists.single.trackVideoIds, <String>[
      'first-video',
      'second-video',
    ]);

    await tester.tap(find.byKey(const Key('offline-selection-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('offline-select-all')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offline-batch-delete')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('delete-downloads-confirmation')),
      findsOneWidget,
    );
    expect(store.snapshot.downloads, hasLength(2));
    await tester.tap(find.byKey(const Key('cancel-delete-downloads')));
    await tester.pumpAndSettle();
    expect(store.snapshot.downloads, hasLength(2));
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('offline-batch-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-downloads')));
    await tester.pumpAndSettle();

    expect(offlineController.removeManyCalls, 1);
    expect(offlineController.lastRemoveManyTrackCount, 2);
    expect(find.byKey(const Key('offline-selected-count')), findsNothing);
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

    expect(
      tester.getRect(find.byKey(const Key('back-to-offline-playlists'))).top,
      tester
          .getRect(find.byKey(const Key('offline-playlist-detail-artwork')))
          .top,
    );
    final playlistTrackRow = find.byKey(
      const Key('offline-playlist-track-playlist-id-first-video'),
    );
    final playlistTrackAction = find.byKey(
      const Key('youtube-track-action-first-video'),
    );
    final playlistTrackRemove = find.byKey(
      const Key('remove-offline-playlist-track-playlist-id-first-video'),
    );
    expect(
      tester.getRect(playlistTrackAction),
      tester.getRect(playlistTrackRow),
    );
    expect(
      tester
          .getRect(playlistTrackAction)
          .contains(tester.getCenter(playlistTrackRemove)),
      isTrue,
    );
    await tester.tap(playlistTrackAction);
    await tester.pump();
    final playlistTrackOverlay = find.byKey(
      const Key('youtube-track-selected-first-video'),
    );
    expect(
      tester.getRect(playlistTrackOverlay),
      tester.getRect(playlistTrackRow),
    );
    expect(
      tester
          .getRect(playlistTrackOverlay)
          .contains(tester.getCenter(playlistTrackRemove)),
      isTrue,
    );

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
      find.byKey(
        const Key('remove-offline-playlist-track-playlist-id-first-video'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('remove-from-offline-playlist-confirmation')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('cancel-remove-from-offline-playlist')),
    );
    await tester.pumpAndSettle();
    expect(store.snapshot.playlists.single.trackVideoIds, <String>[
      'first-video',
      'second-video',
    ]);

    await tester.tap(
      find.byKey(
        const Key('remove-offline-playlist-track-playlist-id-first-video'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm-remove-from-offline-playlist')),
    );
    await tester.pumpAndSettle();
    expect(store.snapshot.playlists.single.trackVideoIds, <String>[
      'second-video',
    ]);

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
    'search workspace searches the local catalog and selects a track',
    (tester) async {
      await _setDesktopSurface(tester);
      await _pumpSignedOutApp(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 250));

      await tester.enterText(find.byKey(const Key('search-field')), 'room');
      await tester.pump();
      final resultRow = find.byKey(
        const Key('search-result-track-room-for-light'),
      );
      _expectForegroundInkCoversArtwork(
        tester,
        surface: resultRow,
        artwork: find.descendant(
          of: resultRow,
          matching: find.byType(ArtworkImage),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const Key('search-field')), findsOneWidget);
      expect(find.text('Room for Light'), findsWidgets);
    },
  );

  testWidgets('search workspace rows support scaled desktop text', (
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
          body: SearchWorkspace(
            workspaceController: workspaceController,
            playerController: playerController,
            shellController: shellController,
            youtubeLibraryController: libraryController,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    final firstResult = find.byKey(
      const Key('search-result-track-soft-signal'),
    );
    final secondResult = find.byKey(
      const Key('search-result-track-after-image'),
    );
    expect(
      tester.getTopLeft(firstResult).dy,
      tester.getTopLeft(secondResult).dy,
    );
    expect(
      tester.getTopLeft(firstResult).dx,
      isNot(tester.getTopLeft(secondResult).dx),
    );

    await tester.binding.setSurfaceSize(const Size(700, 896));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(firstResult).dx,
      tester.getTopLeft(secondResult).dx,
    );
    expect(
      tester.getTopLeft(secondResult).dy,
      greaterThan(tester.getTopLeft(firstResult).dy),
    );
  });

  testWidgets('search workspace classifies local albums and artists', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.tap(find.byKey(const Key('search-trigger')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const Key('search-filter-album')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('search-field')), 'static');
    await tester.pump();

    expect(
      find.byKey(const Key('search-result-local-album-static-bloom')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('search-filter-artist')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('search-field')), 'eloise');
    await tester.pump();
    final artist = find.byKey(
      const Key('search-result-local-artist-eloise-park'),
    );
    expect(artist, findsOneWidget);

    await tester.tap(artist);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'Room for Light',
    );
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

  testWidgets('authentication panel exposes credential-safe diagnostics', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController(
      signInError: const SidecarException(
        'INVALID_COOKIE',
        '',
        <String, Object?>{'diagnosticStage': 'auth.library', 'statusCode': 401},
      ),
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=expired-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-auth-error')), findsOneWidget);
    expect(find.byKey(const Key('youtube-auth-diagnostic')), findsOneWidget);
    expect(
      find.text('INVALID_COOKIE / auth.library / HTTP 401'),
      findsOneWidget,
    );
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
    expect(
      Theme.of(tester.element(aboutCard)).textTheme.bodyMedium?.fontFamily,
      'MiSans',
    );
  });

  testWidgets('Settings opens licenses and registers MiSans', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController();
    addTearDown(libraryController.dispose);
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    final licenses = find.byKey(const Key('settings-open-source-licenses'));
    expect(licenses, findsOneWidget);
    expect(find.text('Licenses and notices'), findsOneWidget);

    final miSansLicenses = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains('MiSans'))
        .toList();
    expect(miSansLicenses, hasLength(1));
    final miSansLicense = miSansLicenses.single.paragraphs
        .map((paragraph) => paragraph.text)
        .join('\n');
    expect(miSansLicense, contains('Xiaomi Inc.'));
    expect(miSansLicense, contains('non-transferable, non-exclusive'));

    await tester.tap(licenses);
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    final dragArea = find.byKey(const Key('license-page-drag-area'));
    final backButton = find.byType(BackButton);
    expect(dragArea, findsOneWidget);
    expect(backButton, findsOneWidget);
    expect(tester.widget<GestureDetector>(dragArea).onPanStart, isNotNull);
    expect(
      tester.getRect(dragArea).left,
      greaterThanOrEqualTo(tester.getRect(backButton).right),
    );

    await tester.tap(backButton);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('signed-in Home and Explore use YouTube feed data', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(2200, 720));
    final sidecarClient = _NoopSidecarClient(homeItemCount: 20);
    final libraryController = _signedOutLibraryController(
      client: sidecarClient,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    expect(find.byKey(const Key('youtube-home-feed')), findsOneWidget);
    expect(find.byKey(const Key('youtube-home-backdrop')), findsOneWidget);
    expect(find.byKey(const Key('youtube-home-tab-Podcasts')), findsOneWidget);
    expect(find.byKey(const Key('youtube-home-tab-Sleep')), findsOneWidget);
    final homeTabs = find.byKey(const Key('youtube-home-tabs'));
    expect(
      tester
          .getRect(find.byKey(const Key('youtube-home-tab-__for_you__')))
          .left,
      closeTo(tester.getRect(homeTabs).left + 2, 0.1),
    );
    final homeTabsLeft = find.byKey(const Key('youtube-home-tabs-left'));
    final homeTabsRight = find.byKey(const Key('youtube-home-tabs-right'));
    expect(tester.getSize(homeTabsLeft), const Size.square(36));
    expect(tester.getSize(homeTabsRight), const Size.square(36));
    expect(
      tester.getRect(homeTabsLeft).right,
      tester.getRect(homeTabsRight).left,
    );
    expect(tester.getRect(homeTabsRight).right, tester.getRect(homeTabs).right);
    expect(
      find.descendant(of: homeTabs, matching: find.byType(ShaderMask)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: homeTabsLeft,
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: homeTabsRight,
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.setSurfaceSize(const Size(1120, 720));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: homeTabsRight,
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('Listen again'), findsOneWidget);
    expect(find.byKey(const Key('youtube-feed-scroll-left-0')), findsOneWidget);
    expect(
      find.byKey(const Key('youtube-feed-scroll-right-0')),
      findsOneWidget,
    );
    final firstSectionLeft = find.byKey(
      const Key('youtube-feed-scroll-left-0'),
    );
    final firstSectionRight = find.byKey(
      const Key('youtube-feed-scroll-right-0'),
    );
    expect(tester.widget<IconButton>(firstSectionLeft).onPressed, isNull);
    expect(tester.widget<IconButton>(firstSectionRight).onPressed, isNotNull);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('youtube-feed-scroll-left-1')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('youtube-feed-scroll-right-1')),
          )
          .onPressed,
      isNull,
    );
    final sectionList = find.byKey(const Key('youtube-feed-section-list-0'));
    final sectionScrollable = find.descendant(
      of: sectionList,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(sectionScrollable).position;
    final visibleItemCount = (position.viewportDimension / 188).floor();
    await tester.tap(find.byKey(const Key('youtube-feed-scroll-right-0')));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(visibleItemCount * 188, 0.1));
    expect(tester.widget<IconButton>(firstSectionLeft).onPressed, isNotNull);
    expect(
      tester
          .getRect(
            find.byKey(
              Key('youtube-feed-song-feed-home-item-$visibleItemCount'),
            ),
          )
          .left,
      closeTo(tester.getRect(sectionList).left, 0.1),
    );
    for (var page = 0; page < 10; page += 1) {
      final rightButton = tester.widget<IconButton>(firstSectionRight);
      if (rightButton.onPressed == null) {
        break;
      }
      await tester.tap(firstSectionRight);
      await tester.pumpAndSettle();
    }
    expect(position.pixels % 188, closeTo(0, 0.1));
    final firstVisibleIndex = (position.pixels / 188).round();
    expect(
      tester
          .getRect(
            find.byKey(
              Key('youtube-feed-song-feed-home-item-$firstVisibleIndex'),
            ),
          )
          .left,
      closeTo(tester.getRect(sectionList).left, 0.1),
    );
    expect(
      tester
          .getRect(find.byKey(const Key('youtube-feed-song-feed-home-item-19')))
          .right,
      lessThanOrEqualTo(tester.getRect(sectionList).right + 0.1),
    );
    for (var page = 0; page < 10; page += 1) {
      final leftButton = tester.widget<IconButton>(firstSectionLeft);
      if (leftButton.onPressed == null) {
        break;
      }
      await tester.tap(firstSectionLeft);
      await tester.pumpAndSettle();
    }
    expect(position.pixels, closeTo(0, 0.1));
    expect(tester.widget<IconButton>(firstSectionLeft).onPressed, isNull);
    await tester.tap(find.byKey(const Key('youtube-feed-song-feed-home-item')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'Live recommendation',
    );
    await tester.tap(find.byKey(const Key('youtube-home-tab-Sleep')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final backdropSwitcher = find.byKey(
      const Key('youtube-feed-backdrop-switcher'),
    );
    expect(
      find.descendant(of: backdropSwitcher, matching: find.byType(Opacity)),
      findsAtLeastNWidgets(2),
    );
    await tester.pumpAndSettle();
    expect(libraryController.selectedHomeFilter, 'Sleep');
    expect(find.text('Sleep picks'), findsOneWidget);
    expect(
      find.byKey(const Key('youtube-feed-compact-column-0-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('youtube-feed-compact-column-0-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('youtube-feed-video-filtered-home-0')),
      findsOneWidget,
    );
    expect(find.text('1:00:00'), findsOneWidget);
    final compactArtwork = tester.getRect(
      find.byKey(const Key('youtube-feed-compact-artwork-filtered-home-0')),
    );
    final compactTitle = tester.getRect(find.text('Sleep long listen 0'));
    expect(
      compactArtwork.left,
      tester.getRect(find.byKey(const Key('youtube-feed-section-list-0'))).left,
    );
    expect(compactTitle.left, closeTo(compactArtwork.right + 8, 0.1));
    final selectedHomeTab = tester.widget<AnimatedContainer>(
      find.byKey(const Key('youtube-home-tab-Sleep')),
    );
    final selectedDecoration = selectedHomeTab.decoration! as BoxDecoration;
    expect(selectedDecoration.borderRadius, BorderRadius.circular(22));
    expect(selectedDecoration.border, isNull);
    expect(selectedDecoration.color, OtohaColors.text.withValues(alpha: 0.92));
    expect(
      find.ancestor(
        of: find.byKey(const Key('youtube-home-tab-Sleep')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AnimatedSwitcher>(backdropSwitcher).duration,
      const Duration(milliseconds: 520),
    );
    final homeFilterRequests = sidecarClient.methods
        .where((method) => method == 'feed.home.filter')
        .length;
    await tester.tap(find.byKey(const Key('youtube-home-refresh')));
    await tester.pumpAndSettle();
    expect(libraryController.selectedHomeFilter, 'Sleep');
    expect(find.text('Sleep picks'), findsOneWidget);
    expect(sidecarClient.methods.last, 'feed.home.filter');
    expect(
      sidecarClient.methods
          .where((method) => method == 'feed.home.filter')
          .length,
      homeFilterRequests + 1,
    );
    expect(
      (tester
                  .widget<AnimatedContainer>(
                    find.byKey(const Key('youtube-home-tab-Sleep')),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      OtohaColors.text.withValues(alpha: 0.92),
    );

    await tester.tap(find.byKey(const Key('sidebar-explore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-explore-feed')), findsOneWidget);
    expect(find.byKey(const Key('youtube-explore-backdrop')), findsOneWidget);
    expect(find.byKey(const Key('youtube-explore-tabs')), findsOneWidget);
    expect(
      find.byKey(const Key('youtube-explore-tab-__for_you__')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('youtube-explore-tab-FEmusic_charts:charts-params')),
      findsOneWidget,
    );
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
    expect(
      find.byKey(const Key('youtube-explore-tab-FEmusic_moods_and_genres')),
      findsNothing,
    );
    expect(find.text('Moods & genres'), findsNothing);
    expect(find.text('New releases'), findsOneWidget);
    expect(find.text('Fresh album'), findsOneWidget);
    expect(find.byKey(const Key('youtube-explore-end')), findsNothing);
  });

  testWidgets('ranked feed sections render chart semantics above artwork', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1120, 720));
    var tappedItemId = '';
    const rankedSection = YouTubeFeedSection(
      title: 'Popular songs',
      items: <YouTubeFeedItem>[
        YouTubeFeedItem(
          id: 'chart-up',
          itemType: 'song',
          title: 'Rising track',
          artists: <String>['Artist'],
          durationSeconds: 180,
          videoId: 'chart-up',
          rank: 1,
          trend: YouTubeChartTrend.up,
        ),
        YouTubeFeedItem(
          id: 'chart-down',
          itemType: 'song',
          title: 'Falling track',
          artists: <String>['Artist'],
          durationSeconds: 181,
          videoId: 'chart-down',
          rank: 2,
          trend: YouTubeChartTrend.down,
        ),
        YouTubeFeedItem(
          id: 'chart-neutral',
          itemType: 'song',
          title: 'Steady track',
          artists: <String>['Artist'],
          durationSeconds: 182,
          videoId: 'chart-neutral',
          rank: 3,
          trend: YouTubeChartTrend.neutral,
        ),
        YouTubeFeedItem(
          id: 'favorite-artist-up',
          itemType: 'artist',
          title: 'Favorite artist up',
          artists: <String>[],
          durationSeconds: 0,
          rank: 4,
          trend: YouTubeChartTrend.up,
        ),
        YouTubeFeedItem(
          id: 'favorite-artist-down',
          itemType: 'artist',
          title: 'Favorite artist down',
          artists: <String>[],
          durationSeconds: 0,
          rank: 5,
          trend: YouTubeChartTrend.down,
        ),
        YouTubeFeedItem(
          id: 'favorite-artist-neutral',
          itemType: 'artist',
          title: 'Favorite artist neutral',
          artists: <String>[],
          durationSeconds: 0,
          rank: 6,
          trend: YouTubeChartTrend.neutral,
        ),
        YouTubeFeedItem(
          id: 'chart-rank-only',
          itemType: 'artist',
          title: 'Ranked artist',
          artists: <String>[],
          durationSeconds: 0,
          rank: 7,
        ),
      ],
    );
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
          body: YouTubeFeedSectionView(
            section: rankedSection,
            sectionIndex: 7,
            loadingItemId: null,
            reduceMotion: true,
            onTap: (item) =>
                () => tappedItemId = item.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('youtube-feed-compact-column-7-0')),
      findsOneWidget,
    );
    String chartLabel(String id) => tester
        .widget<Semantics>(find.byKey(Key('youtube-feed-chart-rank-$id')))
        .properties
        .label!;
    expect(chartLabel('chart-up'), 'Rank 1, Trending up');
    expect(chartLabel('chart-down'), 'Rank 2, Trending down');
    expect(chartLabel('chart-neutral'), 'Rank 3, No rank change');
    expect(chartLabel('favorite-artist-up'), 'Rank 4, Trending up');
    expect(chartLabel('favorite-artist-down'), 'Rank 5, Trending down');
    expect(chartLabel('favorite-artist-neutral'), 'Rank 6, No rank change');
    expect(chartLabel('chart-rank-only'), 'Rank 7');
    final upTrend = tester.widget<Icon>(
      find.byKey(const Key('youtube-feed-chart-trend-chart-up')),
    );
    final downTrend = tester.widget<Icon>(
      find.byKey(const Key('youtube-feed-chart-trend-chart-down')),
    );
    final neutralTrend = tester.widget<Icon>(
      find.byKey(const Key('youtube-feed-chart-trend-chart-neutral')),
    );
    expect(upTrend.icon, Icons.arrow_drop_up_rounded);
    expect(upTrend.color, OtohaColors.accent);
    expect(upTrend.size, 22);
    expect(downTrend.icon, Icons.arrow_drop_down_rounded);
    expect(downTrend.color, const Color(0xFFFF315A));
    expect(downTrend.size, 22);
    expect(neutralTrend.icon, Icons.circle);
    expect(neutralTrend.color, OtohaColors.mutedText);
    expect(neutralTrend.size, 7);
    expect(
      find.byKey(const Key('youtube-feed-chart-trend-chart-rank-only')),
      findsNothing,
    );
    double trendGap(String id, String rank) {
      final slot = tester.getRect(
        find.byKey(Key('youtube-feed-chart-trend-slot-$id')),
      );
      final rankText = tester.getRect(
        find.descendant(
          of: find.byKey(Key('youtube-feed-chart-rank-$id')),
          matching: find.text(rank),
        ),
      );
      expect(slot.width, 22);
      return rankText.left - slot.right;
    }

    expect(trendGap('chart-up', '1'), closeTo(2, 0.1));
    expect(trendGap('chart-down', '2'), closeTo(2, 0.1));
    expect(trendGap('chart-neutral', '3'), closeTo(2, 0.1));
    final upRank = find.byKey(const Key('youtube-feed-chart-rank-chart-up'));
    final rank = tester.getRect(upRank);
    final trendRect = tester.getRect(
      find.byKey(const Key('youtube-feed-chart-trend-chart-up')),
    );
    final rankTextRect = tester.getRect(
      find.descendant(of: upRank, matching: find.text('1')),
    );
    final artwork = tester.getRect(
      find.byKey(const Key('youtube-feed-compact-artwork-chart-up')),
    );
    expect(rank.width, 44);
    expect(trendRect.right, lessThan(rankTextRect.left));
    expect(artwork.left, closeTo(rank.right + 8, 0.1));

    final row = find.byKey(const Key('youtube-feed-song-chart-up'));
    final surface = find.ancestor(of: row, matching: find.byType(Stack)).first;
    _expectForegroundInkCoversArtwork(
      tester,
      surface: surface,
      artwork: find.byKey(const Key('youtube-feed-compact-artwork-chart-up')),
      foregroundInk: row,
      coversSurface: true,
    );
    await tester.tap(row);
    await tester.pump();
    expect(tappedItemId, 'chart-up');
  });

  testWidgets('short Home feed proactively loads continuation pages', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1440, 896));
    final sidecarClient = _NoopSidecarClient(homeContinuationPages: 2);
    final libraryController = _signedOutLibraryController(
      client: sidecarClient,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pumpAndSettle();

    expect(
      sidecarClient.methods.where((method) => method == 'feed.home.more'),
      hasLength(2),
    );
    expect(
      libraryController.homeSections.map((section) => section.title),
      containsAll(<String>['More for you 1', 'More for you 2']),
    );
    expect(libraryController.hasMoreHome, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed proactive Home continuation does not retry in a loop', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1440, 896));
    final sidecarClient = _NoopSidecarClient(
      homeContinuationPages: 1,
      homeContinuationFails: true,
    );
    final libraryController = _signedOutLibraryController(
      client: sidecarClient,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pumpAndSettle();

    expect(
      sidecarClient.methods.where((method) => method == 'feed.home.more'),
      hasLength(1),
    );
    expect(libraryController.homeErrorMessage, YouTubeLibraryError.loadFailed);
    expect(tester.takeException(), isNull);
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

  testWidgets('podcast cards open a dedicated vertical episode page', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final sidecarClient = _NoopSidecarClient(podcastShow: true);
    final libraryController = _signedOutLibraryController(
      client: sidecarClient,
      accountWriteCooldown: Duration.zero,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('youtube-feed-podcast-podcast-show')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('youtube-podcast-show-detail')),
      findsOneWidget,
    );
    expect(find.text('Podcast show'), findsOneWidget);
    expect(find.text('Podcast episode'), findsOneWidget);
    expect(find.text('Save to library'), findsOneWidget);
    expect(find.text('Wrong recommendation'), findsNothing);
    expect(
      find.byKey(const Key('youtube-podcast-episode-podcast-episode')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('youtube-podcast-episode-podcast-episode')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-save-episode')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-save-episode')));
    await tester.pumpAndSettle();

    expect(sidecarClient.savedEpisodeRequests, <Map<String, Object?>>[
      <String, Object?>{'videoId': 'podcast-episode', 'saved': true},
    ]);
    expect(libraryController.isSavedEpisode('podcast-episode'), isTrue);
  });

  testWidgets(
    'library podcast card shows loading then opens shared show detail',
    (tester) async {
      await _setDesktopSurface(tester);
      final browseResponse = Completer<Map<String, Object?>>();
      final sidecarClient = _NoopSidecarClient(
        browseResponse: browseResponse.future,
      );
      final libraryController = _signedOutLibraryController(
        client: sidecarClient,
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(libraryController.dispose);
      await libraryController.signInWithCookie('SID=test-cookie');
      await tester.pumpWidget(
        OtohaApp(youtubeLibraryController: libraryController),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sidebar-library')));
      await tester.pumpAndSettle();
      final savedPodcastCard = find.byKey(
        const Key('youtube-feed-podcast-saved-podcast-show'),
      );
      final savedPodcastTile = find.ancestor(
        of: savedPodcastCard,
        matching: find.byType(YouTubeFeedItemCard),
      );

      await tester.tap(savedPodcastCard);
      await tester.pump();

      expect(
        find.descendant(
          of: savedPodcastTile,
          matching: find.byKey(const Key('youtube-feed-loading-overlay')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('youtube-podcast-show-detail')),
        findsNothing,
      );

      browseResponse.complete(<String, Object?>{
        'podcast': <String, Object?>{
          'id': 'saved-podcast-show',
          'libraryId': 'PLsaved-podcast-show',
          'title': 'Saved podcast detail',
          'subtitle': 'Podcast publisher',
          'description': 'Show description',
          'thumbnailUrl': null,
          'episodes': <Object?>[],
          'hasMore': false,
        },
      });
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('youtube-podcast-show-detail')),
        findsOneWidget,
      );
      expect(find.text('Saved podcast detail'), findsOneWidget);
      expect(find.text('Remove from library'), findsOneWidget);

      await tester.tap(find.byKey(const Key('youtube-podcast-library-toggle')));
      await tester.pumpAndSettle();

      expect(sidecarClient.podcastLibraryRequests, <Map<String, Object?>>[
        <String, Object?>{'podcastId': 'PLsaved-podcast-show', 'saved': false},
      ]);
      expect(find.text('Save to library'), findsOneWidget);
    },
  );

  testWidgets('library artist and playlist cards show item-scoped loading', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final browseResponse = Completer<Map<String, Object?>>();
    final playlistResponse = Completer<Map<String, Object?>>();
    final libraryController = _signedOutLibraryController(
      browseResponse: browseResponse.future,
      playlistResponse: playlistResponse.future,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar-library')));
    await tester.pumpAndSettle();
    final libraryScrollable = find
        .descendant(
          of: find.byKey(const Key('youtube-library-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final artistCard = find.byKey(
      const Key('youtube-feed-artist-followed-artist'),
    );
    await tester.scrollUntilVisible(
      artistCard,
      160,
      scrollable: libraryScrollable,
    );
    await tester.pumpAndSettle();

    await tester.tap(artistCard);
    await tester.pump();

    final artistTile = find.ancestor(
      of: artistCard,
      matching: find.byType(YouTubeFeedItemCard),
    );
    expect(
      find.descendant(
        of: artistTile,
        matching: find.byKey(const Key('youtube-feed-loading-overlay')),
      ),
      findsOneWidget,
    );

    browseResponse.complete(<String, Object?>{
      'artist': <String, Object?>{
        'title': 'Followed artist',
        'channelId': 'followed-artist',
        'subscribed': true,
      },
      'sections': <Object?>[],
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-feed-browse-back')), findsOneWidget);

    await tester.tap(find.byKey(const Key('youtube-feed-browse-back')));
    await tester.pumpAndSettle();
    final restoredLibraryScrollable = find.descendant(
      of: find.byKey(const Key('youtube-library-scroll')),
      matching: find.byType(Scrollable),
    );
    final restoredScrollState = tester.state<ScrollableState>(
      restoredLibraryScrollable,
    );
    restoredScrollState.position.jumpTo(
      restoredScrollState.position.maxScrollExtent * 0.5,
    );
    await tester.pumpAndSettle();
    final playlistCard = find.byKey(const Key('youtube-playlist-PL1'));
    expect(playlistCard, findsOneWidget);
    await tester.ensureVisible(playlistCard);
    await tester.pumpAndSettle();
    _expectForegroundInkCoversArtwork(
      tester,
      surface: playlistCard,
      artwork: find.descendant(
        of: playlistCard,
        matching: find.byType(ArtworkImage),
      ),
      coversSurface: true,
    );

    await tester.tap(playlistCard);
    await tester.pump();

    final playlistLoadingOverlay = find.descendant(
      of: playlistCard,
      matching: find.byKey(const Key('playlist-card-loading-overlay')),
    );
    expect(playlistLoadingOverlay, findsOneWidget);
    expect(
      tester.getRect(playlistLoadingOverlay),
      tester.getRect(playlistCard),
    );
    expect(libraryController.loadingPlaylistId, 'PL1');

    playlistResponse.complete(<String, Object?>{
      'playlist': <String, Object?>{'id': 'PL1', 'title': 'Road trip'},
      'tracks': <Object?>[],
      'hasMore': false,
    });
    await tester.pumpAndSettle();

    expect(libraryController.loadingPlaylistId, isNull);
    expect(
      find.byKey(const Key('youtube-playlist-detail-scroll')),
      findsOneWidget,
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

  testWidgets('Explore hides the mood and genre root but keeps its tabs', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final sidecarClient = _NoopSidecarClient();
    final libraryController = _signedOutLibraryController(
      client: sidecarClient,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-explore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-explore-tabs')), findsOneWidget);
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
    expect(
      find.byKey(const Key('youtube-explore-tab-FEmusic_moods_and_genres')),
      findsNothing,
    );
    expect(find.text('Moods & genres'), findsNothing);
    expect(find.text('New releases'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const Key(
          'youtube-explore-tab-FEmusic_moods_and_genres_category:chill-params',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(sidecarClient.methods, contains('feed.browse'));
    expect(
      libraryController.selectedExploreCategoryId,
      'FEmusic_moods_and_genres_category:chill-params',
    );
    expect(find.text('Chill picks'), findsOneWidget);
    final browseRequests = sidecarClient.methods
        .where((method) => method == 'feed.browse')
        .length;
    await tester.tap(find.byKey(const Key('youtube-explore-refresh')));
    await tester.pumpAndSettle();

    expect(sidecarClient.methods.last, 'feed.browse');
    expect(
      sidecarClient.methods.where((method) => method == 'feed.browse').length,
      browseRequests + 1,
    );
    expect(
      libraryController.selectedExploreCategoryId,
      'FEmusic_moods_and_genres_category:chill-params',
    );
    expect(find.text('Chill picks'), findsOneWidget);
    expect(
      (tester
                  .widget<AnimatedContainer>(
                    find.byKey(
                      const Key(
                        'youtube-explore-tab-FEmusic_moods_and_genres_category:chill-params',
                      ),
                    ),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      OtohaColors.text.withValues(alpha: 0.92),
    );
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
    expect(
      tester
          .getSize(find.byKey(const Key('youtube-history-bottom-padding')))
          .height,
      40,
    );
    await tester.tap(
      find.byKey(const Key('youtube-track-action-history-video')),
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

    final loadingRail = find.byKey(const Key('youtube-history-loading-rail'));
    expect(loadingRail, findsOneWidget);
    expect(
      tester.getTopLeft(loadingRail).dy -
          tester
              .getBottomLeft(find.byKey(const Key('youtube-history-header')))
              .dy,
      closeTo(16, 0.01),
    );

    refreshedHistory.complete(_historyResult());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-history-loading-rail')), findsNothing);
  });

  testWidgets('Library refresh separates the loading rail from the title', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final refreshedLibrary = Completer<Map<String, Object?>>();
    final libraryController = _signedOutLibraryController(
      refreshedLibraryResponse: refreshedLibrary.future,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sidebar-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('youtube-library-refresh')));
    await tester.pump();

    final loadingRail = find.byKey(const Key('youtube-library-loading-rail'));
    expect(loadingRail, findsOneWidget);
    expect(
      tester.getTopLeft(loadingRail).dy -
          tester
              .getBottomLeft(find.byKey(const Key('youtube-library-header')))
              .dy,
      closeTo(16, 0.01),
    );

    refreshedLibrary.complete(const <String, Object?>{
      'playlists': <Object?>[],
      'savedCollections': <Object?>[],
      'followedArtists': <Object?>[],
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-library-loading-rail')), findsNothing);
    expect(libraryController.isLoadingLibrary, isFalse);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('youtube-library-refresh')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('YouTube player exposes rating and comment controls', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final sidecarClient = _NoopSidecarClient();
    final libraryController = _signedOutLibraryController(
      client: sidecarClient,
      accountWriteCooldown: Duration.zero,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('youtube-feed-song-feed-home-item')));
    await tester.pump();
    expect(find.byKey(const Key('player-like')), findsOneWidget);
    expect(find.byKey(const Key('player-dislike')), findsOneWidget);
    expect(find.byKey(const Key('player-comments')), findsOneWidget);
    expect(find.byKey(const Key('player-queue')), findsOneWidget);
    expect(find.byKey(const Key('player-save-episode')), findsNothing);
    expect(sidecarClient.savedEpisodeRequests, isEmpty);

    await tester.tap(find.byKey(const Key('player-comments')));
    await tester.pump();
    expect(find.byKey(const Key('panel-comment-input')), findsOneWidget);
  });

  testWidgets('Library playlist details use the shared music track rows', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final libraryController = _signedOutLibraryController(
      client: _NoopSidecarClient(followedArtistCount: 7),
    );
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
    expect(find.text('YOUR MEDIA LIBRARY'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);
    expect(find.text('Saved music'), findsOneWidget);
    final libraryScrollable = find
        .descendant(
          of: find.byKey(const Key('youtube-library-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    void expectSquareArtwork(Finder artwork, Finder card) {
      final artworkSize = tester.getSize(artwork);
      final cardSize = tester.getSize(card);
      expect(artworkSize.width, closeTo(artworkSize.height, 0.01));
      expect(artworkSize.width, closeTo(cardSize.width, 0.01));
    }

    expect(find.byKey(const Key('youtube-saved-watch_later')), findsNothing);
    expect(find.byKey(const Key('youtube-playlist-WL')), findsNothing);
    expect(find.byKey(const Key('youtube-playlist-RDPN')), findsNothing);
    expect(
      find.byKey(const Key('youtube-podcast-playlist-grid')),
      findsNothing,
    );

    final savedPodcastCard = find.byKey(
      const Key('youtube-feed-podcast-saved-podcast-show'),
    );
    await tester.scrollUntilVisible(
      savedPodcastCard,
      120,
      scrollable: libraryScrollable,
    );
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: savedPodcastCard,
        matching: find.byKey(const Key('youtube-podcast-show-grid')),
      ),
      findsOneWidget,
    );
    final savedPodcastTile = find.ancestor(
      of: savedPodcastCard,
      matching: find.byType(YouTubeFeedItemCard),
    );
    expectSquareArtwork(
      find
          .descendant(of: savedPodcastTile, matching: find.byType(AspectRatio))
          .first,
      savedPodcastTile,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('youtube-feed-artist-followed-artist')),
      240,
      scrollable: libraryScrollable,
    );
    await tester.pumpAndSettle();
    final followedArtistCard = find.byKey(
      const Key('youtube-feed-artist-followed-artist'),
    );
    final followedArtistGrid = find.byKey(
      const Key('youtube-followed-artist-grid'),
    );
    final lastFollowedArtistCard = find.byKey(
      const Key('youtube-feed-artist-followed-artist-6'),
    );
    void expectWrappedArtistGeometry() {
      final gridRect = tester.getRect(followedArtistGrid);
      final firstCardRect = tester.getRect(followedArtistCard);
      final lastCardRect = tester.getRect(lastFollowedArtistCard);
      expect(firstCardRect.size, const Size(168, 224));
      expect(lastCardRect.size, const Size(168, 224));
      expect(lastCardRect.top, greaterThan(firstCardRect.top));
      expect(gridRect.top, closeTo(firstCardRect.top, 0.01));
      expect(gridRect.bottom, closeTo(lastCardRect.bottom, 0.01));
    }

    expect(followedArtistCard, findsOneWidget);
    expect(lastFollowedArtistCard, findsOneWidget);
    expectWrappedArtistGeometry();
    final followedArtistArtwork = find.byKey(
      const Key('youtube-feed-profile-artwork-followed-artist'),
    );
    expectSquareArtwork(followedArtistArtwork, followedArtistCard);
    expect(
      tester
          .widget<Material>(
            find
                .ancestor(
                  of: followedArtistCard,
                  matching: find.byType(Material),
                )
                .first,
          )
          .clipBehavior,
      Clip.antiAlias,
    );
    await tester.binding.setSurfaceSize(const Size(1120, 720));
    await tester.pumpAndSettle();
    tester.state<ScrollableState>(libraryScrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    expectSquareArtwork(
      find
          .descendant(of: savedPodcastTile, matching: find.byType(AspectRatio))
          .first,
      savedPodcastTile,
    );
    await tester.scrollUntilVisible(
      followedArtistCard,
      120,
      scrollable: libraryScrollable,
    );
    await tester.pumpAndSettle();
    expectWrappedArtistGeometry();
    expectSquareArtwork(followedArtistArtwork, followedArtistCard);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1440, 896));
    await tester.pumpAndSettle();
    final playlistCard = find.byKey(const Key('youtube-playlist-PL1'));
    await tester.scrollUntilVisible(
      playlistCard,
      -240,
      scrollable: libraryScrollable,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(playlistCard).clipBehavior, Clip.antiAlias);
    expect(
      tester.getSize(
        find.descendant(of: playlistCard, matching: find.byType(InkWell)),
      ),
      tester.getSize(playlistCard),
    );
    final playlistArtwork = find
        .descendant(of: playlistCard, matching: find.byType(ClipRRect))
        .first;
    expectSquareArtwork(playlistArtwork, playlistCard);

    await tester.binding.setSurfaceSize(const Size(1120, 720));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      playlistCard,
      -120,
      scrollable: libraryScrollable,
    );
    await tester.pumpAndSettle();
    expectSquareArtwork(playlistArtwork, playlistCard);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('youtube-playlist-PL1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('youtube-playlist-detail-scroll')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('youtube-track-video-1')), findsOneWidget);
    expect(find.byKey(const Key('youtube-track-video-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('youtube-track-action-video-2')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'City lights',
    );
    expect(
      find.byKey(const Key('youtube-track-selected-video-2')),
      findsOneWidget,
    );
    final selectedTrackRow = find.byKey(const Key('youtube-track-video-2'));
    final selectedTrackArtwork = find.descendant(
      of: selectedTrackRow,
      matching: find.byType(ArtworkImage),
    );
    final selectedTrackAction = find.byKey(
      const Key('youtube-track-action-video-2'),
    );
    expect(
      tester.getRect(selectedTrackAction),
      tester.getRect(selectedTrackRow),
    );
    expect(
      tester
          .getRect(selectedTrackAction)
          .contains(tester.getCenter(selectedTrackArtwork)),
      isTrue,
    );
    final selectedTrackOverlay = find.byKey(
      const Key('youtube-track-selected-video-2'),
    );
    expect(
      tester.getRect(selectedTrackOverlay),
      tester.getRect(selectedTrackRow),
    );
    expect(
      tester
          .getRect(selectedTrackOverlay)
          .contains(tester.getCenter(selectedTrackArtwork)),
      isTrue,
    );
  });

  testWidgets(
    'Library albums open shared details and show pending save state',
    (tester) async {
      await _setDesktopSurface(tester, const Size(1120, 720));
      final albumResponse = Completer<Map<String, Object?>>();
      final refreshedLibrary = Completer<Map<String, Object?>>();
      final sidecarClient = _NoopSidecarClient(
        includeSavedAlbum: true,
        albumLibraryResponse: albumResponse.future,
        refreshedLibraryResponse: refreshedLibrary.future,
      );
      final libraryController = _signedOutLibraryController(
        client: sidecarClient,
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(libraryController.dispose);
      await libraryController.signInWithCookie('SID=test-cookie');
      await tester.pumpWidget(
        OtohaApp(youtubeLibraryController: libraryController),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('sidebar-library')));
      await tester.pumpAndSettle();
      final libraryScrollable = find
          .descendant(
            of: find.byKey(const Key('youtube-library-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final albumCard = find.byKey(
        const Key('youtube-feed-album-MPRE-saved-album'),
      );
      await tester.scrollUntilVisible(
        albumCard,
        120,
        scrollable: libraryScrollable,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('youtube-album-grid')), findsOneWidget);
      final albumTile = find.ancestor(
        of: albumCard,
        matching: find.byType(YouTubeFeedItemCard),
      );
      final artwork = find
          .descendant(of: albumTile, matching: find.byType(AspectRatio))
          .first;
      final artworkSize = tester.getSize(artwork);
      expect(artworkSize.width, closeTo(artworkSize.height, 0.01));
      expect(artworkSize.width, closeTo(tester.getSize(albumTile).width, 0.01));
      _expectForegroundInkCoversArtwork(
        tester,
        surface: albumTile,
        artwork: artwork,
        foregroundInk: albumCard,
        coversSurface: true,
      );

      await tester.tap(albumCard);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('youtube-feed-collection-detail')),
        findsOneWidget,
      );
      expect(find.text('Saved album'), findsOneWidget);
      expect(find.text('Remove from library'), findsOneWidget);

      final toggle = find.byKey(const Key('youtube-album-library-toggle'));
      await tester.tap(toggle);
      await tester.pump();
      expect(libraryController.isAlbumSaved('MPRE-saved-album'), isFalse);
      expect(libraryController.albumLibraryWriteId, 'MPRE-saved-album');
      expect(
        find.descendant(
          of: toggle,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      albumResponse.complete(<String, Object?>{
        'albumId': 'MPRE-saved-album',
        'saved': false,
      });
      await tester.pump();
      expect(sidecarClient.albumLibraryRequests, <Map<String, Object?>>[
        <String, Object?>{'albumId': 'MPRE-saved-album', 'saved': false},
      ]);
      expect(libraryController.albumLibraryWriteId, isNull);
      expect(libraryController.isLoadingLibrary, isTrue);
      expect(
        find.descendant(
          of: toggle,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.text('Save to library'), findsOneWidget);

      refreshedLibrary.complete(const <String, Object?>{
        'playlists': <Object?>[],
        'savedCollections': <Object?>[],
        'followedArtists': <Object?>[],
        'albums': <Object?>[],
        'podcasts': <Object?>[],
      });
      await tester.pumpAndSettle();
      expect(libraryController.isLoadingLibrary, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved episode playlist uses feed card geometry and real durations',
    (tester) async {
      await _setDesktopSurface(tester);
      final libraryController = _signedOutLibraryController();
      addTearDown(libraryController.dispose);
      await libraryController.signInWithCookie('SID=test-cookie');
      await tester.pumpWidget(
        OtohaApp(youtubeLibraryController: libraryController),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sidebar-library')));
      await tester.pumpAndSettle();
      final libraryScrollable = find
          .descendant(
            of: find.byKey(const Key('youtube-library-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final scrollState = tester.state<ScrollableState>(libraryScrollable);
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final savedEpisodesCard = find.byKey(const Key('youtube-playlist-SE'));
      expect(savedEpisodesCard, findsOneWidget);
      expect(
        find.ancestor(
          of: savedEpisodesCard,
          matching: find.byKey(const Key('youtube-podcast-show-grid')),
        ),
        findsNothing,
      );
      final desktopSize = tester.getSize(savedEpisodesCard);
      expect(desktopSize.width, lessThanOrEqualTo(170));
      expect(desktopSize.height, lessThan(224));
      final savedEpisodesTitle = find.descendant(
        of: savedEpisodesCard,
        matching: find.text('Episodes for later'),
      );
      expect(savedEpisodesTitle, findsOneWidget);
      expect(
        tester.getBottomRight(savedEpisodesCard).dy,
        closeTo(tester.getBottomRight(savedEpisodesTitle).dy, 0.01),
      );

      await tester.binding.setSurfaceSize(const Size(1120, 720));
      await tester.pumpAndSettle();
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final minimumSize = tester.getSize(savedEpisodesCard);
      expect(minimumSize.width, lessThanOrEqualTo(170));
      expect(minimumSize.height, lessThan(224));
      expect(
        tester.getBottomRight(savedEpisodesCard).dy,
        closeTo(tester.getBottomRight(savedEpisodesTitle).dy, 0.01),
      );

      await tester.tap(savedEpisodesCard);
      await tester.pumpAndSettle();

      final savedEpisodeRow = find.byKey(
        const Key('youtube-track-saved-video'),
      );
      expect(savedEpisodeRow, findsOneWidget);
      expect(
        find.descendant(of: savedEpisodeRow, matching: find.text('3:00')),
        findsOneWidget,
      );
      final durationText = tester.widget<Text>(
        find.descendant(of: savedEpisodeRow, matching: find.text('3:00')),
      );
      expect(durationText.style?.fontFeatures, const <FontFeature>[
        FontFeature.tabularFigures(),
      ]);
      expect(
        find.descendant(of: savedEpisodeRow, matching: find.text('--:--')),
        findsNothing,
      );
    },
  );

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
    expect(
      find.byKey(const Key('youtube-feed-browse-artwork')),
      findsOneWidget,
    );
    expect(find.text('Subscriber picks'), findsOneWidget);
  });

  testWidgets(
    'artist details refresh metadata, follow state, shuffle, and albums',
    (tester) async {
      await _setDesktopSurface(tester);
      final libraryController = _signedOutLibraryController(
        artistDetail: true,
        accountWriteCooldown: Duration.zero,
        trackResponse: Future<Map<String, Object?>>.value(<String, Object?>{
          'track': <String, Object?>{
            'videoId': 'artist-song-one',
            'title': 'Artist song one',
            'artists': <String>['Fresh artist'],
            'durationSeconds': 247,
            'thumbnailUrl': 'https://example.test/artist-song-one.jpg',
          },
        }),
      );
      addTearDown(libraryController.dispose);
      await libraryController.signInWithCookie('SID=test-cookie');
      await tester.pumpWidget(
        OtohaApp(youtubeLibraryController: libraryController),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('youtube-feed-artist-subscriber-id')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('youtube-feed-browse-detail')),
        findsOneWidget,
      );
      expect(find.text('Fresh artist'), findsOneWidget);
      expect(
        find.byKey(const Key('youtube-artist-subscriber-count')),
        findsOneWidget,
      );
      expect(find.text('Monthly audience: 5.6M'), findsOneWidget);
      expect(find.text('Subscribers: 1.4M'), findsOneWidget);
      expect(find.text('Fresh artist metadata'), findsNothing);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Fresh album'), findsOneWidget);
      expect(find.byKey(const Key('youtube-artist-follow')), findsOneWidget);

      await tester.tap(find.byKey(const Key('youtube-artist-follow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('youtube-artist-following')), findsOneWidget);

      await tester.tap(find.byKey(const Key('youtube-artist-shuffle')));
      await tester.pumpAndSettle();
      final queue = find.byKey(const Key('panel-queue'));
      await tester.tap(find.byKey(const Key('player-queue')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('player-time'))).data,
        isNot(contains('--:--')),
      );
      expect(queue, findsOneWidget);
      expect(
        find.descendant(of: queue, matching: find.text('Artist song one')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: queue, matching: find.text('Artist song two')),
        findsOneWidget,
      );
    },
  );

  testWidgets('search workspace returns YouTube Music results when signed in', (
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
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byKey(const Key('search-field')), 'remote');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('search-result-youtube-song-remote-track')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester.widget<Text>(find.byKey(const Key('player-track'))).data,
      'Remote result',
    );
  });

  testWidgets('search uses an unclipped full-width loading rail', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final searchCompleter = Completer<Map<String, Object?>>();
    final libraryController = _signedOutLibraryController(
      client: _NoopSidecarClient(searchResponse: searchCompleter.future),
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-trigger')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('YOUTUBE MUSIC'), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), 'pending');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final workspace = find.byKey(const Key('search-workspace'));
    final loadingRail = find.byKey(const Key('search-loading-rail'));
    expect(loadingRail, findsOneWidget);
    expect(tester.getSize(loadingRail).height, closeTo(4, 0.01));
    expect(tester.getTopLeft(loadingRail).dx, tester.getTopLeft(workspace).dx);
    expect(tester.getSize(loadingRail).width, tester.getSize(workspace).width);

    searchCompleter.complete(const <String, Object?>{'items': <Object?>[]});
    await tester.pumpAndSettle();
    expect(loadingRail, findsNothing);
  });

  testWidgets('search centers delayed result loading over the compact row', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final collectionCompleter = Completer<Map<String, Object?>>();
    final client = _NoopSidecarClient(
      searchResponse: Future<Map<String, Object?>>.value(<String, Object?>{
        'items': <Object?>[
          _feedItem(
            id: 'delayed-album',
            title: 'Delayed album',
            itemType: 'album',
          ),
        ],
      }),
      collectionResponse: collectionCompleter.future,
    );
    final libraryController = YouTubeLibraryController(
      client: client,
      credentialStore: _EmptyCredentialStore(),
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-trigger')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byKey(const Key('search-field')), 'delayed');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final result = find.byKey(
      const Key('search-result-youtube-album-delayed-album'),
    );
    await tester.tap(result);
    await tester.pump();

    final overlay = find.byKey(
      const Key('search-result-loading-overlay-youtube-album-delayed-album'),
    );
    expect(overlay, findsOneWidget);
    expect(tester.getCenter(overlay), tester.getCenter(result));
    expect(
      find.descendant(
        of: overlay,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    collectionCompleter.complete(<String, Object?>{
      'tracks': <Object?>[
        <String, Object?>{
          'videoId': 'delayed-track',
          'title': 'Delayed track',
          'artists': <String>['Artist'],
          'durationSeconds': 180,
        },
      ],
    });
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
  });

  testWidgets('search details return to the same query and filter', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final client = _NoopSidecarClient(
      artistDetail: true,
      podcastShow: true,
      searchResponse: Future<Map<String, Object?>>.value(<String, Object?>{
        'items': <Object?>[
          _feedItem(
            id: 'search-album',
            title: 'Fresh album',
            itemType: 'album',
          ),
          _feedItem(
            id: 'search-playlist',
            title: 'Fresh playlist',
            itemType: 'playlist',
          ),
          _feedItem(
            id: 'search-artist',
            title: 'Fresh artist',
            itemType: 'artist',
          ),
          _feedItem(
            id: 'search-podcast',
            title: 'Fresh podcast',
            itemType: 'podcast',
          ),
        ],
      }),
    );
    final libraryController = YouTubeLibraryController(
      client: client,
      credentialStore: _EmptyCredentialStore(),
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-trigger')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byKey(const Key('search-field')), 'fresh');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('search-result-youtube-album-search-album')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const Key('youtube-feed-collection-detail')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('youtube-feed-collection-back')));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(
      find.byKey(const Key('search-result-youtube-playlist-search-playlist')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const Key('youtube-feed-collection-detail')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('youtube-feed-collection-back')));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(
      find.byKey(const Key('search-result-youtube-artist-search-artist')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('youtube-feed-browse-detail')), findsOneWidget);
    await tester.tap(find.byKey(const Key('youtube-feed-browse-back')));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(
      find.byKey(const Key('search-result-youtube-podcast-search-podcast')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const Key('youtube-podcast-show-detail')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('youtube-podcast-show-back')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('search-field')))
          .controller!
          .text,
      'fresh',
    );
    expect(libraryController.searchFilter, YouTubeMusicSearchFilter.all);
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
      find.byKey(const Key('youtube-track-action-album-track-1')),
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

  testWidgets('expanded lyrics read timed text from an offline bundle', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    const lyricsPath = '/offline/video-id/lyrics.lrc';
    final playerController = PlayerController(<Track>[
      const Track(
        id: 'youtube:dQw4w9WgXcQ',
        title: 'Offline lyrics track',
        artist: 'Offline artist',
        album: 'Offline album',
        artworkAsset: 'assets/artwork/cover_01.png',
        durationSeconds: 213,
        lyrics: <String>[],
        youtubeVideoId: 'dQw4w9WgXcQ',
        localFilePath: '/offline/video-id/audio.webm',
        localLyricsPath: lyricsPath,
      ),
    ]);
    final shellController = ShellController();
    final youtubeLibraryController = _signedOutLibraryController();
    addTearDown(playerController.dispose);
    addTearDown(shellController.dispose);
    addTearDown(youtubeLibraryController.dispose);

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
            readLyricsFile: (path) async {
              expect(path, lyricsPath);
              return '[00:01.25]Bundled first line\n'
                  '[00:03.50]Bundled second line\n';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bundled first line'), findsOneWidget);
    expect(find.text('Bundled second line'), findsOneWidget);
    expect(youtubeLibraryController.lyricsVideoId, isNull);
    playerController.seekTo(2);
    await tester.pump();
    expect(_lyricStyle(tester, 'Bundled first line').color, OtohaColors.accent);
    playerController.seekTo(4);
    await tester.pump();
    expect(
      _lyricStyle(tester, 'Bundled second line').color,
      OtohaColors.accent,
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

  testWidgets('compact feed rows center loading over the selected row', (
    tester,
  ) async {
    await _setDesktopSurface(tester, const Size(1120, 720));
    final trackResponse = Completer<Map<String, Object?>>();
    final libraryController = _signedOutLibraryController(
      trackResponse: trackResponse.future,
      filteredItemDurationSeconds: 0,
    );
    addTearDown(libraryController.dispose);
    await libraryController.signInWithCookie('SID=test-cookie');
    await tester.pumpWidget(
      OtohaApp(youtubeLibraryController: libraryController),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('youtube-home-tab-Sleep')));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('youtube-feed-video-filtered-home-0'));
    await tester.tap(row);
    await tester.pump();

    final overlay = find.byKey(
      const Key('youtube-feed-compact-loading-overlay'),
    );
    final rowSurface = find
        .ancestor(of: row, matching: find.byType(Stack))
        .first;
    expect(overlay, findsOneWidget);
    expect(tester.getRect(overlay), tester.getRect(rowSurface));
    expect(
      find.descendant(
        of: overlay,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    _expectForegroundInkCoversArtwork(
      tester,
      surface: rowSurface,
      artwork: find.byKey(
        const Key('youtube-feed-compact-artwork-filtered-home-0'),
      ),
      foregroundInk: row,
      coversSurface: true,
    );

    trackResponse.complete(<String, Object?>{
      'track': <String, Object?>{
        'videoId': 'filtered-home-0',
        'itemType': 'video',
        'title': 'Sleep long listen 0',
        'artists': <String>['Artist'],
        'album': 'YouTube Music',
        'durationSeconds': 3600,
        'thumbnailUrl': null,
      },
    });
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
    expect(find.byKey(const Key('video-playback-overlay')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('player-media-mode')),
        matching: find.byIcon(Icons.videocam_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('player-media-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-playback-overlay')), findsOneWidget);
  });
}

void _expectForegroundInkCoversArtwork(
  WidgetTester tester, {
  required Finder surface,
  required Finder artwork,
  Finder? foregroundInk,
  bool coversSurface = false,
}) {
  expect(surface, findsOneWidget);
  expect(artwork, findsOneWidget);
  final ink =
      foregroundInk ??
      find.descendant(of: surface, matching: find.byType(InkWell));
  expect(ink, findsOneWidget);

  final inkRect = tester.getRect(ink);
  final artworkRect = tester.getRect(artwork);
  expect(inkRect.left, lessThanOrEqualTo(artworkRect.left));
  expect(inkRect.top, lessThanOrEqualTo(artworkRect.top));
  expect(inkRect.right, greaterThanOrEqualTo(artworkRect.right));
  expect(inkRect.bottom, greaterThanOrEqualTo(artworkRect.bottom));
  if (coversSurface) {
    expect(inkRect, tester.getRect(surface));
  }

  final positionedFinder = find
      .ancestor(of: ink, matching: find.byType(Positioned))
      .first;
  final positioned = tester.widget<Positioned>(positionedFinder);
  expect(positioned.left, 0);
  expect(positioned.top, 0);
  expect(positioned.right, 0);
  expect(positioned.bottom, 0);
  final interactionStack = tester.widget<Stack>(
    find.ancestor(of: positionedFinder, matching: find.byType(Stack)).first,
  );
  expect(identical(interactionStack.children.last, positioned), isTrue);
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
  _NoopSidecarClient? client,
  Future<Map<String, Object?>>? browseResponse,
  Future<Map<String, Object?>>? refreshedLibraryResponse,
  List<Future<Map<String, Object?>>>? historyResponses,
  Future<Map<String, Object?>>? lyricsResponse,
  Future<Map<String, Object?>>? trackResponse,
  Future<Map<String, Object?>>? playlistResponse,
  SidecarException? signInError,
  int homeItemCount = 1,
  int filteredItemDurationSeconds = 3600,
  bool podcastShow = false,
  bool artistDetail = false,
  Duration accountWriteCooldown = const Duration(seconds: 2),
}) {
  return YouTubeLibraryController(
    client:
        client ??
        _NoopSidecarClient(
          browseResponse: browseResponse,
          refreshedLibraryResponse: refreshedLibraryResponse,
          historyResponses: historyResponses,
          lyricsResponse: lyricsResponse,
          trackResponse: trackResponse,
          playlistResponse: playlistResponse,
          signInError: signInError,
          homeItemCount: homeItemCount,
          filteredItemDurationSeconds: filteredItemDurationSeconds,
          podcastShow: podcastShow,
          artistDetail: artistDetail,
        ),
    credentialStore: _EmptyCredentialStore(),
    accountWriteCooldown: accountWriteCooldown,
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
    this.refreshedLibraryResponse,
    List<Future<Map<String, Object?>>>? historyResponses,
    this.lyricsResponse,
    this.trackResponse,
    this.searchResponse,
    this.collectionResponse,
    this.playlistResponse,
    this.signInError,
    this.homeItemCount = 1,
    this.filteredItemDurationSeconds = 3600,
    this.podcastShow = false,
    this.artistDetail = false,
    this.includeSavedAlbum = false,
    this.albumLibraryResponse,
    this.homeContinuationPages = 0,
    this.homeContinuationFails = false,
    this.followedArtistCount = 1,
  }) : historyResponses = List<Future<Map<String, Object?>>>.of(
         historyResponses ?? const <Future<Map<String, Object?>>>[],
       );

  final Future<Map<String, Object?>>? browseResponse;
  final Future<Map<String, Object?>>? refreshedLibraryResponse;
  final List<Future<Map<String, Object?>>> historyResponses;
  final Future<Map<String, Object?>>? lyricsResponse;
  final Future<Map<String, Object?>>? trackResponse;
  final Future<Map<String, Object?>>? searchResponse;
  final Future<Map<String, Object?>>? collectionResponse;
  final Future<Map<String, Object?>>? playlistResponse;
  final SidecarException? signInError;
  final int homeItemCount;
  final int filteredItemDurationSeconds;
  final bool podcastShow;
  final bool artistDetail;
  final bool includeSavedAlbum;
  final Future<Map<String, Object?>>? albumLibraryResponse;
  final int homeContinuationPages;
  final bool homeContinuationFails;
  final int followedArtistCount;
  final List<Map<String, Object?>> savedEpisodeRequests =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> podcastLibraryRequests =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> albumLibraryRequests =
      <Map<String, Object?>>[];
  final List<String> methods = <String>[];
  int _libraryMediaRequestCount = 0;
  int _homeContinuationRequests = 0;

  @override
  Stream<SidecarEvent> get events => const Stream<SidecarEvent>.empty();

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    methods.add(method);
    if (method == 'podcast.episode_later.set') {
      savedEpisodeRequests.add(Map<String, Object?>.of(params));
    }
    if (method == 'podcast.library.set') {
      podcastLibraryRequests.add(Map<String, Object?>.of(params));
    }
    if (method == 'album.library.set') {
      albumLibraryRequests.add(Map<String, Object?>.of(params));
      if (albumLibraryResponse != null) {
        return await albumLibraryResponse!;
      }
      return <String, Object?>{
        'albumId': params['albumId']!,
        'saved': params['saved']!,
      };
    }
    if (method == 'feed.home.more' && homeContinuationFails) {
      throw const SidecarException(
        'HOME_CONTINUATION_FAILED',
        'Home continuation failed.',
      );
    }
    if (method == 'auth.cookie.signIn' && signInError != null) {
      throw signInError!;
    }
    if (method == 'feed.browse' && browseResponse != null) {
      return await browseResponse!;
    }
    if (method == 'library.media') {
      final isRefresh = _libraryMediaRequestCount++ > 0;
      if (isRefresh && refreshedLibraryResponse != null) {
        return await refreshedLibraryResponse!;
      }
    }
    if (method == 'history.get' && historyResponses.isNotEmpty) {
      return await historyResponses.removeAt(0);
    }
    if (method == 'lyrics.get' && lyricsResponse != null) {
      return await lyricsResponse!;
    }
    if (method == 'feed.track' && trackResponse != null) {
      return await trackResponse!;
    }
    if (method == 'feed.collection' && collectionResponse != null) {
      return await collectionResponse!;
    }
    if (method == 'library.playlist' &&
        params['playlistId'] != 'SE' &&
        playlistResponse != null) {
      return await playlistResponse!;
    }
    if (method == 'library.playlist' && params['playlistId'] == 'SE') {
      return <String, Object?>{
        'playlist': <String, Object?>{
          'id': 'SE',
          'title': 'Episodes for later',
        },
        'tracks': <Object?>[
          <String, Object?>{
            'videoId': 'saved-video',
            'title': 'Saved episode',
            'artists': <String>['Podcast author'],
            'durationSeconds': 180,
            'itemType': 'non_music_track',
          },
        ],
        'hasMore': false,
      };
    }
    return switch (method) {
      'auth.cookie.signIn' => <String, Object?>{'authenticated': true},
      'library.media' => <String, Object?>{
        'playlists': <Object?>[
          <String, Object?>{
            'id': 'PL1',
            'title': 'Road trip',
            'owner': 'Listener',
            'itemCount': '2 songs',
            'thumbnailUrl': 'https://example.test/playlist.jpg',
          },
          <String, Object?>{
            'id': 'SE',
            'title': 'Episodes for later',
            'thumbnailUrl': 'https://example.test/saved-episodes.jpg',
          },
        ],
        'podcasts': <Object?>[
          _feedItem(
            id: 'saved-podcast-show',
            title: 'Saved podcast',
            itemType: 'podcast',
          ),
        ],
        'albums': <Object?>[
          if (includeSavedAlbum)
            _feedItem(
              id: 'MPRE-saved-album',
              title: 'Saved album',
              itemType: 'album',
              thumbnailUrl: 'https://example.test/saved-album.jpg',
            ),
        ],
        'savedCollections': <Object?>[
          <String, Object?>{
            'id': 'liked_videos',
            'specialKind': 'liked_videos',
            'title': 'Liked videos',
          },
        ],
        'followedArtists': List<Object?>.generate(
          followedArtistCount,
          (index) => _feedItem(
            id: index == 0 ? 'followed-artist' : 'followed-artist-$index',
            title: index == 0
                ? 'Followed artist'
                : 'Followed artist ${index + 1}',
            itemType: 'artist',
          ),
        ),
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
      'library.special' => <String, Object?>{
        'playlist': <String, Object?>{
          'id': params['kind']!,
          'specialKind': params['kind']!,
          'title': 'Liked videos',
        },
        'tracks': <Object?>[
          <String, Object?>{
            'videoId': 'saved-video',
            'title': 'Saved track',
            'artists': <String>['Artist'],
            'durationSeconds': 180,
          },
        ],
        'hasMore': false,
      },
      'library.playlist.more' => const <String, Object?>{
        'tracks': <Object?>[],
        'hasMore': false,
      },
      'library.special.more' => const <String, Object?>{
        'tracks': <Object?>[],
        'hasMore': false,
      },
      'history.get' => _historyResult(),
      'feed.home' => <String, Object?>{
        'filters': <Object?>[
          'Podcasts',
          'Sleep',
          'Relax',
          'Feel good',
          'Energize',
          'Workout',
          'Romance',
          'Sad',
          'Commute',
          'Party',
          'Focus',
        ],
        'selectedFilter': null,
        'hasMore': homeContinuationPages > 0,
        'sections': <Object?>[
          if (podcastShow)
            <String, Object?>{
              'title': 'Recommended shows',
              'items': <Object?>[
                _feedItem(
                  id: 'podcast-show',
                  title: 'Podcast show',
                  itemType: 'podcast',
                ),
              ],
            },
          <String, Object?>{
            'title': 'Listen again',
            'items': <Object?>[
              for (var index = 0; index < homeItemCount; index += 1)
                _feedItem(
                  id: index == 0 ? 'feed-home-item' : 'feed-home-item-$index',
                  title: index == 0
                      ? 'Live recommendation'
                      : 'Recommendation $index',
                  itemType: 'song',
                  videoId: index == 0
                      ? 'video-home-item'
                      : 'video-home-item-$index',
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
                thumbnailUrl: 'https://example.test/subscriber.jpg',
              ),
            ],
          },
        ],
      },
      'feed.home.more' => <String, Object?>{
        'sections': <Object?>[
          <String, Object?>{
            'title': 'More for you ${_homeContinuationRequests + 1}',
            'items': <Object?>[
              _feedItem(
                id: 'continued-home-${_homeContinuationRequests + 1}',
                title: 'Continued recommendation',
                itemType: 'song',
                videoId: 'continued-home-${_homeContinuationRequests + 1}',
              ),
            ],
          },
        ],
        'hasMore': ++_homeContinuationRequests < homeContinuationPages,
      },
      'feed.home.filter' => <String, Object?>{
        'sections': <Object?>[
          <String, Object?>{
            'title': '${params['filter']} picks',
            'itemsPerColumn': 4,
            'items': <Object?>[
              for (var index = 0; index < 12; index += 1)
                _feedItem(
                  id: 'filtered-home-$index',
                  title: '${params['filter']} long listen $index',
                  itemType: 'video',
                  videoId: 'filtered-home-$index',
                  durationSeconds: filteredItemDurationSeconds == 0
                      ? 0
                      : filteredItemDurationSeconds + index,
                ),
            ],
          },
        ],
        'filters': <Object?>[
          'Podcasts',
          'Sleep',
          'Relax',
          'Feel good',
          'Energize',
          'Workout',
          'Romance',
          'Sad',
          'Commute',
          'Party',
          'Focus',
        ],
        'selectedFilter': params['filter'],
      },
      'feed.explore' => <String, Object?>{
        'sections': <Object?>[
          <String, Object?>{
            'title': 'Moods & genres',
            'items': <Object?>[
              <String, Object?>{
                'id': 'FEmusic_moods_and_genres',
                'itemType': 'category',
                'title': 'Moods & genres',
                'subtitle': 'Mood & genre',
                'artists': <String>[],
                'durationSeconds': 0,
              },
              <String, Object?>{
                'id': 'FEmusic_charts',
                'itemType': 'category',
                'title': 'Charts',
                'subtitle': 'Charts',
                'browseParams': 'charts-params',
                'artists': <String>[],
                'durationSeconds': 0,
              },
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
      'feed.browse' =>
        podcastShow && params['itemType'] == 'podcast'
            ? <String, Object?>{
                'podcast': <String, Object?>{
                  'id': params['id']!,
                  'libraryId': params['id'] == 'saved-podcast-show'
                      ? 'PLsaved-podcast-show'
                      : 'PLpodcast-show',
                  'title': 'Podcast show',
                  'subtitle': 'Podcast publisher',
                  'description': 'Show description',
                  'thumbnailUrl': null,
                  'episodes': <Object?>[
                    <String, Object?>{
                      'id': 'podcast-episode',
                      'itemType': 'episode',
                      'title': 'Podcast episode',
                      'subtitle': 'Today',
                      'description': 'Episode description',
                      'videoId': 'podcast-episode',
                      'artists': <String>[],
                      'durationSeconds': 0,
                    },
                  ],
                  'hasMore': false,
                },
              }
            : artistDetail && params['itemType'] == 'artist'
            ? <String, Object?>{
                'artist': <String, Object?>{
                  'title': 'Fresh artist',
                  'subtitle': 'Fresh artist metadata',
                  'audience': 'Monthly audience: 5.6M',
                  'thumbnailUrl': 'https://example.test/fresh-artist.jpg',
                  'channelId': 'UCfresh-artist',
                  'subscriberCount': '1.4M',
                  'subscribed': false,
                },
                'sections': <Object?>[
                  <String, Object?>{
                    'title': 'Top songs',
                    'items': <Object?>[
                      _feedItem(
                        id: 'artist-song-one',
                        title: 'Artist song one',
                        itemType: 'song',
                        videoId: 'artist-song-one',
                        durationSeconds: 0,
                      ),
                      _feedItem(
                        id: 'artist-song-two',
                        title: 'Artist song two',
                        itemType: 'song',
                        videoId: 'artist-song-two',
                      ),
                    ],
                  },
                  <String, Object?>{
                    'title': 'Albums',
                    'items': <Object?>[
                      _feedItem(
                        id: 'artist-album',
                        title: 'Fresh album',
                        itemType: 'album',
                      ),
                    ],
                  },
                ],
              }
            : _feedResult(
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
      'search.music' =>
        searchResponse == null
            ? <String, Object?>{
                'items': <Object?>[
                  _feedItem(
                    id: 'remote-track',
                    title: 'Remote result',
                    itemType: 'song',
                    videoId: 'remote-video',
                  ),
                ],
              }
            : await searchResponse!,
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
  String? thumbnailUrl,
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
            'thumbnailUrl': thumbnailUrl,
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
  String? thumbnailUrl,
  int durationSeconds = 180,
}) {
  return <String, Object?>{
    'id': id,
    'itemType': itemType,
    'title': title,
    'subtitle': 'Artist',
    'videoId': videoId,
    'artists': <String>['Artist'],
    'album': itemType == 'album' ? title : null,
    'durationSeconds': durationSeconds,
    'thumbnailUrl': thumbnailUrl,
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

class _FixedPlayerSessionStore implements PlayerSessionStore {
  _FixedPlayerSessionStore(this.value);

  final Map<String, Object?> value;

  @override
  Future<Map<String, Object?>?> read() async => value;

  @override
  Future<void> write(Map<String, Object?> value) async {}

  @override
  Future<void> delete() async {}
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

class _TrackingOfflineLibraryController extends OfflineLibraryController {
  _TrackingOfflineLibraryController({
    required super.store,
    required super.youtubeLibraryController,
  });

  int removeManyCalls = 0;
  int lastRemoveManyTrackCount = 0;

  @override
  Future<void> removeMany(Iterable<DownloadedTrack> tracks) {
    removeManyCalls += 1;
    final selected = tracks.toList(growable: false);
    lastRemoveManyTrackCount = selected.length;
    return Future<void>.value();
  }
}

Future<void> _setDesktopSurface(
  WidgetTester tester, [
  Size size = const Size(1440, 896),
]) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpVideoCapableApp(
  WidgetTester tester, {
  required String videoId,
  required String title,
}) async {
  final libraryController = _signedOutLibraryController();
  addTearDown(libraryController.dispose);
  final track = Track(
    id: 'youtube:$videoId',
    title: title,
    artist: 'Channel',
    album: 'YouTube Music',
    artworkAsset: '',
    durationSeconds: 180,
    lyrics: const <String>[],
    youtubeVideoId: videoId,
    videoAvailable: true,
  );
  await tester.pumpWidget(
    OtohaApp(
      youtubeLibraryController: libraryController,
      initialTracks: <Track>[track],
    ),
  );
  await tester.pump();
}
