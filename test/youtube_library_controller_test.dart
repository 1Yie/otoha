import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/models/youtube_library.dart';
import 'package:otoha/src/services/credential_store.dart';
import 'package:otoha/src/services/youtube_sidecar_client.dart';
import 'package:otoha/src/state/youtube_library_controller.dart';

void main() {
  test('stays offline without a saved credential', () async {
    final client = _FakeSidecarClient();
    final store = _MemoryCredentialStore();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: store,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.status, YouTubeAccountStatus.signedOut);
    expect(client.methods, isEmpty);
  });

  test('clears legacy OAuth credentials', () async {
    final client = _FakeSidecarClient();
    final store = _MemoryCredentialStore()
      ..value = jsonEncode(<String, Object?>{
        'kind': 'google_oauth',
        'value': <String, Object?>{'access_token': 'legacy'},
      });
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: store,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.status, YouTubeAccountStatus.signedOut);
    expect(store.value, isNull);
    expect(client.methods, isEmpty);
  });

  test('Cookie sign-in stores credentials and loads playlists', () async {
    final client = _FakeSidecarClient();
    final store = _MemoryCredentialStore();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: store,
    );
    addTearDown(controller.dispose);

    await controller.signInWithCookie('SID=test-cookie');
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, YouTubeAccountStatus.signedIn);
    expect(controller.profileName, 'Test listener');
    expect(controller.profileAvatarUrl, 'https://example.test/avatar.jpg');
    expect(controller.playlists.single.title, 'Road trip');
    expect(controller.homeSections.single.title, 'Listen again');
    expect(controller.exploreSections.single.title, 'New releases');
    expect(
      SavedCredential.fromJson(
        (jsonDecode(store.value!)! as Map<Object?, Object?>)
            .cast<String, Object?>(),
      ).kind,
      'cookie',
    );
    expect(client.methods, <String>[
      'auth.cookie.signIn',
      'library.playlists',
      'feed.home',
      'feed.explore',
    ]);
  });

  test('loads selected playlist tracks', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);

    await controller.signInWithCookie('SID=test-cookie');
    await controller.openPlaylist(controller.playlists.single);

    expect(controller.selectedPlaylist?.playlist.title, 'Road trip');
    expect(controller.selectedPlaylist?.tracks.first.title, 'Night drive');
  });

  test('loads a feed album as a simulated playback collection', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    final tracks = await controller.loadFeedCollection(
      controller.exploreSections.single.items.single,
    );

    expect(tracks.map((track) => track.title), <String>[
      'Album track',
      'Second album track',
    ]);
    expect(client.methods.last, 'feed.collection');
  });

  test(
    'opens feed collections as details and replaces Explore after browsing',
    () async {
      final client = _FakeSidecarClient();
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');

      await controller.openFeedCollection(
        controller.exploreSections.single.items.single,
        source: 'explore',
      );
      expect(controller.selectedFeedCollection?.title, 'Fresh album');
      expect(
        controller.selectedFeedCollection?.tracks.first.title,
        'Album track',
      );
      expect(
        controller.selectedFeedCollection?.thumbnailUrl,
        'https://example.test/feed.jpg',
      );
      expect(controller.selectedFeedCollection?.artists, <String>['Artist']);

      await controller.openFeedBrowse(
        const YouTubeFeedItem(
          id: 'FEmusic_moods_and_genres_category',
          itemType: 'category',
          title: 'Chill',
          artists: <String>[],
          durationSeconds: 0,
          browseParams: 'chill-params',
        ),
        source: 'explore',
      );
      expect(controller.selectedFeedCollection, isNull);
      expect(controller.selectedFeedBrowse, isNull);
      expect(controller.exploreSections.single.title, 'Chill picks');
      expect(client.methods.last, 'feed.browse');
    },
  );

  test('keeps one-track collections out of the collection detail', () async {
    final client = _FakeSidecarClient(singleCollection: true);
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    final tracks = await controller.openFeedCollection(
      controller.exploreSections.single.items.single,
      source: 'explore',
    );

    expect(tracks.single.title, 'Album track');
    expect(controller.selectedFeedCollection, isNull);
  });

  test('resolves a missing feed-song duration before playback', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);

    final track = await controller.resolveFeedTrack(
      const YouTubeFeedItem(
        id: 'feed-song',
        itemType: 'song',
        title: 'Feed song',
        videoId: 'video-feed-song',
        artists: <String>['Card artist'],
        durationSeconds: 0,
      ),
    );

    expect(track.durationSeconds, 247);
    expect(track.thumbnailUrl, 'https://example.test/resolved.jpg');
    expect(client.methods.last, 'feed.track');
  });

  test('searches YouTube Music through the sidecar', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await controller.searchMusic('night drive');

    expect(controller.searchQuery, 'night drive');
    expect(controller.searchResults.single.title, 'Remote result');
    expect(controller.searchResults.single.isPlayable, isTrue);
    expect(client.methods.last, 'search.music');
  });
}

class _FakeSidecarClient extends YouTubeSidecarClient {
  _FakeSidecarClient({this.singleCollection = false})
    : super(entryPath: 'unused');

  final bool singleCollection;
  final StreamController<SidecarEvent> _controller =
      StreamController<SidecarEvent>.broadcast(sync: true);
  final List<String> methods = <String>[];

  @override
  Stream<SidecarEvent> get events => _controller.stream;

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    methods.add(method);
    switch (method) {
      case 'auth.cookie.signIn':
        _controller.add(
          SidecarEvent('auth.credentials', <String, Object?>{
            'credential': <String, Object?>{
              'kind': 'cookie',
              'value': params['cookie']!,
            },
          }),
        );
        return <String, Object?>{
          'authenticated': true,
          'mode': 'cookie',
          'profile': <String, Object?>{
            'displayName': 'Test listener',
            'avatarUrl': 'https://example.test/avatar.jpg',
          },
        };
      case 'library.playlists':
        return <String, Object?>{
          'playlists': <Object?>[
            <String, Object?>{
              'id': 'PL1',
              'title': 'Road trip',
              'owner': 'Listener',
              'itemCount': '1 song',
              'thumbnailUrl': 'https://example.test/playlist.jpg',
            },
          ],
        };
      case 'library.playlist':
        return <String, Object?>{
          'playlist': <String, Object?>{'id': 'PL1', 'title': 'Road trip'},
          'tracks': <Object?>[
            <String, Object?>{
              'videoId': 'video-1',
              'title': 'Night drive',
              'artists': <String>['Artist'],
              'durationSeconds': 180,
              'album': 'Album',
              'thumbnailUrl': 'https://example.test/track.jpg',
            },
            <String, Object?>{
              'videoId': 'video-2',
              'title': 'City lights',
              'artists': <String>['Artist'],
              'durationSeconds': 190,
              'album': 'Album',
              'thumbnailUrl': null,
            },
          ],
        };
      case 'feed.home':
        return _feed('Listen again', 'Live recommendation', 'song');
      case 'feed.explore':
        return _feed('New releases', 'Fresh album', 'album');
      case 'feed.collection':
        return <String, Object?>{
          'tracks': <Object?>[
            <String, Object?>{
              'videoId': 'album-track',
              'title': 'Album track',
              'artists': <String>['Artist'],
              'durationSeconds': 200,
            },
            if (!singleCollection)
              <String, Object?>{
                'videoId': 'second-album-track',
                'title': 'Second album track',
                'artists': <String>['Artist'],
                'durationSeconds': 201,
              },
          ],
        };
      case 'feed.browse':
        return _feed('Chill picks', 'Curated playlist', 'playlist');
      case 'feed.track':
        return <String, Object?>{
          'track': <String, Object?>{
            'videoId': params['videoId']!,
            'title': 'Resolved song',
            'artists': <String>['Resolved artist'],
            'durationSeconds': 247,
            'thumbnailUrl': 'https://example.test/resolved.jpg',
          },
        };
      case 'search.music':
        return <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'id': 'remote-track',
              'itemType': 'song',
              'title': 'Remote result',
              'subtitle': 'Remote artist',
              'videoId': 'remote-video',
              'artists': <String>['Remote artist'],
              'durationSeconds': 211,
              'thumbnailUrl': 'https://example.test/remote.jpg',
            },
          ],
        };
      default:
        return const <String, Object?>{};
    }
  }

  @override
  Future<void> dispose() => _controller.close();

  Map<String, Object?> _feed(String section, String title, String itemType) {
    return <String, Object?>{
      'sections': <Object?>[
        <String, Object?>{
          'title': section,
          'items': <Object?>[
            <String, Object?>{
              'id': 'feed-1',
              'itemType': itemType,
              'title': title,
              'subtitle': 'Artist',
              'videoId': itemType == 'song' ? 'video-feed-1' : null,
              'artists': <String>['Artist'],
              'album': null,
              'durationSeconds': 120,
              'thumbnailUrl': 'https://example.test/feed.jpg',
            },
          ],
        },
      ],
    };
  }
}

class _MemoryCredentialStore implements CredentialStore {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
