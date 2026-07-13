import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/app/otoha_app.dart';
import 'package:otoha/src/app/theme.dart';
import 'package:otoha/src/models/catalog.dart';
import 'package:otoha/src/services/credential_store.dart';
import 'package:otoha/src/services/youtube_sidecar_client.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';
import 'package:otoha/src/state/youtube_library_controller.dart';
import 'package:otoha/src/widgets/player_bar.dart';

void main() {
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

  testWidgets('right panel selection swaps without removing the shell', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    await _pumpSignedOutApp(tester);

    await tester.tap(find.byKey(const Key('player-queue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel-queue')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-lyrics')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('panel-lyrics')), findsOneWidget);
    expect(find.byKey(const Key('player-track')), findsOneWidget);
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

    expect(find.byKey(const Key('panel-devices')), findsOneWidget);
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
        const Key('youtube-feed-category-FEmusic_moods_and_genres_category'),
      ),
      findsOneWidget,
    );
    expect(find.text('Moods & genres'), findsOneWidget);
    expect(find.text('New releases'), findsOneWidget);
    expect(find.text('Fresh album'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const Key('youtube-feed-category-FEmusic_moods_and_genres_category'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-explore-feed')), findsOneWidget);
    expect(find.text('Chill picks'), findsOneWidget);
    expect(find.byKey(const Key('youtube-explore-feed-back')), findsNothing);
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
    await tester.tap(find.byKey(const Key('youtube-playlist-PL1')));
    await tester.pumpAndSettle();

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
    addTearDown(playerController.dispose);
    addTearDown(shellController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOtohaTheme(),
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
    expect(find.text('Lyrics'), findsOneWidget);

    await tester.tap(find.byKey(const Key('expanded-lyrics-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expanded-lyrics-overlay')), findsNothing);
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
      tester.getCenter(find.byKey(const Key('player-now-playing'))).dx,
      closeTo(560, 0.1),
    );
  });
}

YouTubeLibraryController _signedOutLibraryController() {
  return YouTubeLibraryController(
    client: _NoopSidecarClient(),
    credentialStore: _EmptyCredentialStore(),
  );
}

Future<void> _pumpSignedOutApp(WidgetTester tester) async {
  final controller = _signedOutLibraryController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(OtohaApp(youtubeLibraryController: controller));
}

class _NoopSidecarClient extends YouTubeSidecarClient {
  _NoopSidecarClient() : super(entryPath: 'unused');

  @override
  Stream<SidecarEvent> get events => const Stream<SidecarEvent>.empty();

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
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

Future<void> _setDesktopSurface(
  WidgetTester tester, [
  Size size = const Size(1440, 896),
]) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
