import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/models/youtube_library.dart';
import 'package:otoha/src/services/credential_store.dart';
import 'package:otoha/src/services/lyric_cache.dart';
import 'package:otoha/src/services/remote_metadata_cache.dart';
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
    expect(controller.homeFilters, <String>['Podcasts', 'Sleep']);
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

  test('invalid Cookie sign-in clears saved credentials', () async {
    final client = _FakeSidecarClient(
      errorMethod: 'auth.cookie.signIn',
      error: const SidecarException('INVALID_COOKIE', ''),
    );
    final store = _MemoryCredentialStore()..value = 'stale credential';
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: store,
    );
    addTearDown(controller.dispose);

    await controller.signInWithCookie('SID=expired-cookie');

    expect(controller.status, YouTubeAccountStatus.error);
    expect(controller.errorMessage, YouTubeLibraryError.authenticationFailed);
    expect(controller.errorDiagnostic, 'INVALID_COOKIE');
    expect(store.value, isNull);
  });

  test(
    'sidecar startup failures are not reported as invalid Cookies',
    () async {
      final client = _FakeSidecarClient(
        errorMethod: 'auth.cookie.signIn',
        error: const SidecarException('SIDECAR_NOT_FOUND', ''),
      );
      final store = _MemoryCredentialStore()..value = 'existing credential';
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: store,
      );
      addTearDown(controller.dispose);

      await controller.signInWithCookie('SID=test-cookie');

      expect(controller.status, YouTubeAccountStatus.error);
      expect(controller.errorMessage, YouTubeLibraryError.loadFailed);
      expect(controller.errorDiagnostic, 'SIDECAR_NOT_FOUND');
      expect(store.value, 'existing credential');
    },
  );

  test(
    'unexpected authentication failures preserve credentials and diagnostics',
    () async {
      final client = _FakeSidecarClient(
        errorMethod: 'auth.cookie.signIn',
        error: const SidecarException(
          'AUTHENTICATION_FAILED',
          '',
          <String, Object?>{
            'diagnosticStage': 'auth.profile',
            'statusCode': 500,
            'upstreamCode': 'UND_ERR_SOCKET',
          },
        ),
      );
      final store = _MemoryCredentialStore()..value = 'existing credential';
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: store,
      );
      addTearDown(controller.dispose);

      await controller.signInWithCookie('SID=test-cookie');

      expect(controller.status, YouTubeAccountStatus.error);
      expect(controller.errorMessage, YouTubeLibraryError.loadFailed);
      expect(
        controller.errorDiagnostic,
        'AUTHENTICATION_FAILED / auth.profile / HTTP 500 / UND_ERR_SOCKET',
      );
      expect(store.value, 'existing credential');
    },
  );

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

  test(
    'reloads signed-in YouTube Music data in the selected language',
    () async {
      final client = _FakeSidecarClient();
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');

      await controller.setLocale('zh');

      expect(controller.locale, 'zh-CN');
      final localeRequest = client.requests.singleWhere(
        (request) => request.method == 'session.setLocale',
      );
      expect(localeRequest.params, <String, Object?>{'locale': 'zh-CN'});
      expect(client.methods.sublist(client.methods.length - 4), <String>[
        'session.setLocale',
        'library.playlists',
        'feed.home',
        'feed.explore',
      ]);
    },
  );

  test('loads authenticated playback history only when requested', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    expect(controller.historyTracks, isEmpty);
    await controller.loadHistory();

    expect(controller.historyTracks.single.title, 'History track');
    expect(controller.hasLoadedHistory, isTrue);
    expect(
      client.methods.where((method) => method == 'history.get'),
      hasLength(1),
    );

    await controller.loadHistory();
    expect(
      client.methods.where((method) => method == 'history.get'),
      hasLength(1),
    );
  });

  test('restores the saved Cookie session after the sidecar exits', () async {
    final client = _FakeSidecarClient();
    final store = _MemoryCredentialStore();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: store,
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');
    await Future<void>.delayed(Duration.zero);
    final methodsBeforeExit = client.methods.length;

    client.emit(SidecarEvent('sidecar.exit', <String, Object?>{'exitCode': 1}));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, YouTubeAccountStatus.signedIn);
    expect(client.methods.sublist(methodsBeforeExit), <String>[
      'session.restore',
      'library.playlists',
      'feed.home',
      'feed.explore',
    ]);
  });

  test('appends real Home continuation sections without duplicates', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    expect(controller.hasMoreHome, isTrue);
    await controller.loadMoreHome();

    expect(controller.homeSections.map((section) => section.title), <String>[
      'Listen again',
      'More for you',
    ]);
    expect(controller.hasMoreHome, isFalse);
    expect(client.methods.last, 'feed.home.more');

    await controller.loadMoreHome();
    expect(
      client.methods.where((method) => method == 'feed.home.more'),
      hasLength(1),
    );
  });

  test('applies a native YouTube Music Home filter', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await controller.selectHomeFilter('Sleep');

    expect(controller.selectedHomeFilter, 'Sleep');
    expect(controller.homeSections.single.title, 'Sleep picks');
    expect(controller.homeFilters, <String>['Podcasts', 'Sleep']);
    expect(client.methods.last, 'feed.home.filter');
    expect(client.requests.last.params, <String, Object?>{'filter': 'Sleep'});
  });

  test('appends Explore continuation sections without duplicates', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    expect(controller.hasMoreExplore, isTrue);
    await controller.loadMoreExplore();

    expect(controller.exploreSections.map((section) => section.title), <String>[
      'New releases',
      'More to explore',
    ]);
    expect(controller.hasMoreExplore, isFalse);
    expect(client.methods.last, 'feed.explore.more');

    await controller.loadMoreExplore();
    expect(
      client.methods.where((method) => method == 'feed.explore.more'),
      hasLength(1),
    );
  });

  test('uses fresh remote metadata before requesting Home again', () async {
    final client = _FakeSidecarClient();
    final cache = _MemoryMetadataCache()
      ..entries['feed.home.v2'] = RemoteMetadataCacheEntry(
        cachedAt: DateTime.now(),
        data: <String, Object?>{
          ...client._feed('Cached Home', 'Cached recommendation', 'song'),
          'filters': <Object?>['Podcasts', 'Sleep'],
        },
      );
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      metadataCache: cache,
    );
    addTearDown(controller.dispose);

    await controller.signInWithCookie('SID=test-cookie');

    expect(controller.homeSections.single.title, 'Cached Home');
    expect(client.methods.where((method) => method == 'feed.home'), isEmpty);
  });

  test('does not send a rapid second account write', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await controller.rateVideo('video-1', YouTubeRating.liked);
    await controller.rateVideo('video-1', YouTubeRating.disliked);

    expect(
      client.methods.where((method) => method == 'interaction.rate'),
      hasLength(1),
    );
    expect(controller.isAccountWriteCoolingDown, isTrue);
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

      expect(controller.exploreCategories.map((item) => item.title), <String>[
        'Chill',
        'Pop',
      ]);
      expect(controller.exploreSections.single.title, 'New releases');

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
      expect(controller.exploreCategories.map((item) => item.title), <String>[
        'Chill',
        'Pop',
      ]);
      expect(
        controller.selectedExploreCategoryId,
        'FEmusic_moods_and_genres_category:chill-params',
      );
      expect(client.methods.last, 'feed.browse');
    },
  );

  test(
    'opens podcast shows as dedicated episode details with pagination',
    () async {
      final client = _FakeSidecarClient();
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');

      await controller.openFeedBrowse(
        const YouTubeFeedItem(
          id: 'MPSPpodcast-show',
          itemType: 'podcast',
          title: 'Podcast show',
          artists: <String>[],
          durationSeconds: 0,
        ),
        source: 'explore',
      );

      expect(controller.selectedFeedBrowse, isNull);
      expect(controller.exploreSections.single.title, 'New releases');
      expect(controller.selectedPodcastShow?.title, 'Podcast show');
      expect(
        controller.selectedPodcastShow?.episodes.map((item) => item.title),
        <String>['Newest episode'],
      );

      await controller.loadMorePodcastShow();

      expect(
        controller.selectedPodcastShow?.episodes.map((item) => item.title),
        <String>['Newest episode', 'Older episode'],
      );
      expect(controller.selectedPodcastShow?.hasMore, isFalse);
      expect(
        client.methods,
        containsAllInOrder(<String>['feed.browse', 'feed.browse.more']),
      );
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

  test('loads remote lyrics through the sidecar', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await controller.loadLyrics(
      videoId: 'dQw4w9WgXcQ',
      title: 'Track title',
      artist: 'Artist',
      album: 'Album',
      durationSeconds: 213,
    );

    expect(controller.lyricsVideoId, 'dQw4w9WgXcQ');
    expect(controller.lyricsLines.map((line) => line.text), <String>[
      'First line',
      'Second line',
    ]);
    expect(controller.isLoadingLyrics, isFalse);
    expect(client.methods.last, 'lyrics.get');
  });

  test('uses the persistent lyric cache before calling the sidecar', () async {
    final client = _FakeSidecarClient();
    final cache = _MemoryLyricCache()
      ..entries['dQw4w9WgXcQ'] = const <YouTubeLyricLine>[
        YouTubeLyricLine(text: 'Cached line', startSeconds: 1),
      ];
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      lyricCache: cache,
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');
    client.methods.clear();

    await controller.loadLyrics(
      videoId: 'dQw4w9WgXcQ',
      title: 'Track title',
      artist: 'Artist',
      album: 'Album',
      durationSeconds: 213,
    );

    expect(controller.lyricsLines.single.text, 'Cached line');
    expect(client.methods, isNot(contains('lyrics.get')));
  });

  test('uses official untimed lyrics without persisting them', () async {
    final client = _FakeSidecarClient(
      lyricsResult: <String, Object?>{
        'source': 'youtube_music',
        'lines': <Object?>[
          <String, Object?>{
            'text': 'Official lyric line',
            'startSeconds': null,
          },
        ],
      },
    );
    final cache = _MemoryLyricCache();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      lyricCache: cache,
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await controller.loadLyrics(
      videoId: 'dQw4w9WgXcQ',
      title: 'Track title',
      artist: 'Artist',
      album: 'Album',
      durationSeconds: 213,
    );

    expect(controller.lyricsLines.single.text, 'Official lyric line');
    expect(controller.lyricsLines.single.startSeconds, isNull);
    expect(cache.entries, isEmpty);
  });

  test('updates an account rating and loads then posts comments', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      accountWriteCooldown: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await controller.rateVideo('video-1', YouTubeRating.liked);
    await controller.loadComments('video-1');
    final posted = await controller.postComment('video-1', 'Great track');

    expect(controller.ratingFor('video-1'), YouTubeRating.liked);
    expect(controller.comments.single.author, 'Commenter');
    expect(controller.comments.single.text, 'Great track');
    expect(posted, isTrue);
    expect(
      client.methods,
      containsAllInOrder(<String>[
        'interaction.rate',
        'comments.get',
        'comments.create',
        'comments.get',
      ]),
    );
  });
}

class _FakeSidecarClient extends YouTubeSidecarClient {
  _FakeSidecarClient({
    this.singleCollection = false,
    this.lyricsResult,
    this.errorMethod,
    this.error,
  }) : super(entryPath: 'unused');

  final bool singleCollection;
  final Map<String, Object?>? lyricsResult;
  final String? errorMethod;
  final SidecarException? error;
  final StreamController<SidecarEvent> _controller =
      StreamController<SidecarEvent>.broadcast(sync: true);
  final List<String> methods = <String>[];
  final List<_SidecarRequest> requests = <_SidecarRequest>[];

  @override
  Stream<SidecarEvent> get events => _controller.stream;

  void emit(SidecarEvent event) => _controller.add(event);

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    methods.add(method);
    requests.add(_SidecarRequest(method, Map<String, Object?>.of(params)));
    if (method == errorMethod) {
      throw error!;
    }
    switch (method) {
      case 'session.restore':
        return <String, Object?>{
          'authenticated': true,
          'mode': 'cookie',
          'profile': <String, Object?>{
            'displayName': 'Test listener',
            'avatarUrl': 'https://example.test/avatar.jpg',
          },
        };
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
      case 'history.get':
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
      case 'feed.home':
        return <String, Object?>{
          ..._feed(
            'Listen again',
            'Live recommendation',
            'song',
            hasMore: true,
          ),
          'filters': <Object?>['Podcasts', 'Sleep'],
          'selectedFilter': null,
        };
      case 'feed.home.filter':
        return <String, Object?>{
          ..._feed(
            '${params['filter']} picks',
            '${params['filter']} recommendation',
            'playlist',
          ),
          'filters': <Object?>['Podcasts', 'Sleep'],
          'selectedFilter': params['filter'],
        };
      case 'feed.home.more':
        return _feed('More for you', 'Another recommendation', 'song');
      case 'feed.explore':
        return <String, Object?>{
          'sections': <Object?>[
            <String, Object?>{
              'title': 'Moods & genres',
              'items': <Object?>[
                <String, Object?>{
                  'id': 'FEmusic_moods_and_genres_category',
                  'itemType': 'category',
                  'title': 'Chill',
                  'artists': <String>[],
                  'durationSeconds': 0,
                  'browseParams': 'chill-params',
                },
                <String, Object?>{
                  'id': 'FEmusic_moods_and_genres_category',
                  'itemType': 'category',
                  'title': 'Pop',
                  'artists': <String>[],
                  'durationSeconds': 0,
                  'browseParams': 'pop-params',
                },
              ],
            },
            (_feed('New releases', 'Fresh album', 'album')['sections']!
                    as List<Object?>)
                .single,
          ],
          'hasMore': true,
        };
      case 'feed.explore.more':
        return _feed('More to explore', 'Another discovery', 'album');
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
        if (params['itemType'] == 'podcast') {
          return <String, Object?>{
            'podcast': <String, Object?>{
              'id': params['id']!,
              'title': 'Podcast show',
              'subtitle': 'Podcast publisher',
              'description': 'Show description',
              'thumbnailUrl': 'https://example.test/podcast.jpg',
              'episodes': <Object?>[
                <String, Object?>{
                  'id': 'newest-episode',
                  'itemType': 'episode',
                  'title': 'Newest episode',
                  'subtitle': 'Today',
                  'description': 'Episode description',
                  'videoId': 'newest-episode',
                  'artists': <String>[],
                  'durationSeconds': 0,
                },
              ],
              'hasMore': true,
            },
          };
        }
        return _feed('Chill picks', 'Curated playlist', 'playlist');
      case 'feed.browse.more':
        return <String, Object?>{
          'episodes': <Object?>[
            <String, Object?>{
              'id': 'older-episode',
              'itemType': 'episode',
              'title': 'Older episode',
              'subtitle': 'Last week',
              'videoId': 'older-episode',
              'artists': <String>[],
              'durationSeconds': 0,
            },
          ],
          'hasMore': false,
        };
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
      case 'lyrics.get':
        return lyricsResult ??
            <String, Object?>{
              'source': 'lrclib',
              'lines': <Object?>[
                <String, Object?>{'text': 'First line', 'startSeconds': 1.0},
                <String, Object?>{'text': 'Second line', 'startSeconds': 2.0},
              ],
            };
      case 'interaction.rate':
        return <String, Object?>{'rating': params['rating']!};
      case 'comments.get':
        return <String, Object?>{
          'comments': <Object?>[
            <String, Object?>{
              'id': 'comment-1',
              'author': 'Commenter',
              'text': 'Great track',
              'publishedTime': 'now',
              'avatarUrl': 'https://example.test/commenter.jpg',
              'likeCount': '1',
            },
          ],
        };
      case 'comments.create':
        return const <String, Object?>{'posted': true};
      default:
        return const <String, Object?>{};
    }
  }

  @override
  Future<void> dispose() => _controller.close();

  Map<String, Object?> _feed(
    String section,
    String title,
    String itemType, {
    bool hasMore = false,
  }) {
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
      'hasMore': hasMore,
    };
  }
}

class _SidecarRequest {
  const _SidecarRequest(this.method, this.params);

  final String method;
  final Map<String, Object?> params;
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

class _MemoryMetadataCache implements RemoteMetadataCache {
  final Map<String, RemoteMetadataCacheEntry> entries =
      <String, RemoteMetadataCacheEntry>{};

  @override
  Future<void> clear() async => entries.clear();

  @override
  Future<RemoteMetadataCacheEntry?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    entries[key] = RemoteMetadataCacheEntry(
      cachedAt: DateTime.now(),
      data: data,
    );
  }
}

class _MemoryLyricCache implements LyricCache {
  final Map<String, List<YouTubeLyricLine>> entries =
      <String, List<YouTubeLyricLine>>{};

  @override
  Future<List<YouTubeLyricLine>?> read(String videoId) async =>
      entries[videoId];

  @override
  Future<void> write(String videoId, List<YouTubeLyricLine> lines) async {
    entries[videoId] = lines;
  }
}
