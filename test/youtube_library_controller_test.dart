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

  test(
    'Cookie sign-in stores credentials and loads the media library',
    () async {
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
      expect(controller.playlists.map((item) => item.id), <String>['PL1']);
      expect(controller.podcasts.map((item) => item.id), <String>[
        'MPSP-saved-show',
      ]);
      expect(controller.albums.map((item) => item.id), <String>[
        'MPRE-saved-album',
      ]);
      expect(
        controller.savedCollections.map((item) => item.specialKind),
        <String?>['liked_videos'],
      );
      expect(controller.followedArtists.single.title, 'Artist one');
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
        'library.media',
        'feed.home',
        'feed.explore',
      ]);
    },
  );

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

  test(
    'loads selected playlist tracks incrementally without duplicates',
    () async {
      final playlistResponse = Completer<Map<String, Object?>>();
      final client = _FakeSidecarClient(
        playlistResponse: playlistResponse.future,
      );
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
      );
      addTearDown(controller.dispose);

      await controller.signInWithCookie('SID=test-cookie');
      final openFuture = controller.openPlaylist(
        controller.playlists.singleWhere((playlist) => playlist.id == 'PL1'),
      );
      expect(controller.loadingPlaylistId, 'PL1');

      playlistResponse.complete(<String, Object?>{
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
        'hasMore': true,
      });
      await openFuture;

      expect(controller.loadingPlaylistId, isNull);
      expect(controller.selectedPlaylist?.playlist.title, 'Road trip');
      expect(controller.selectedPlaylist?.tracks.first.title, 'Night drive');
      expect(controller.selectedPlaylist?.hasMore, isTrue);

      await controller.loadMorePlaylist();

      expect(
        controller.selectedPlaylist?.tracks.map((track) => track.videoId),
        <String>['video-1', 'video-2', 'video-3'],
      );
      expect(controller.selectedPlaylist?.hasMore, isFalse);
      expect(client.methods.last, 'library.playlist.more');

      await controller.loadMorePlaylist();
      expect(
        client.methods.where((method) => method == 'library.playlist.more'),
        hasLength(1),
      );
    },
  );

  test('clears the pending playlist identity after a failed open', () async {
    final client = _FakeSidecarClient(
      errorMethod: 'library.playlist',
      error: const SidecarException(
        'PLAYLIST_LOAD_FAILED',
        'Playlist detail failed.',
      ),
    );
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);

    await controller.signInWithCookie('SID=test-cookie');
    await controller.openPlaylist(
      controller.playlists.singleWhere((playlist) => playlist.id == 'PL1'),
    );

    expect(controller.loadingPlaylistId, isNull);
    expect(controller.isLoadingPlaylist, isFalse);
    expect(controller.selectedPlaylist, isNull);
    expect(controller.errorMessage, isNotNull);
  });

  test(
    'removes and restores a saved podcast show with a media refresh',
    () async {
      final client = _FakeSidecarClient();
      final cache = _MemoryMetadataCache();
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
        metadataCache: cache,
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');

      final savedPodcast = controller.podcasts.single;
      await controller.openFeedBrowse(savedPodcast, source: 'library');
      final detail = controller.selectedPodcastShow!;
      expect(controller.isPodcastSaved(detail.id), isTrue);

      await controller.togglePodcastLibrary(detail);
      expect(controller.isPodcastSaved(detail.id), isFalse);

      await controller.togglePodcastLibrary(detail);
      expect(controller.isPodcastSaved(detail.id), isTrue);
      expect(
        client.methods.where((method) => method == 'podcast.library.set'),
        hasLength(2),
      );
      expect(
        client.requests
            .where((request) => request.method == 'podcast.library.set')
            .map((request) => request.params['podcastId']),
        everyElement('PLsaved-podcast-show'),
      );
      expect(
        client.methods.where((method) => method == 'library.media'),
        hasLength(3),
      );
      final cachedPodcasts =
          cache.entries['library.media.v4']!.data['podcasts']! as List<Object?>;
      expect(
        cachedPodcasts.cast<Map<Object?, Object?>>().map(
          (podcast) => podcast['id'],
        ),
        contains('MPSP-saved-show'),
      );
    },
  );

  test('removes and restores an album with a media refresh', () async {
    final client = _FakeSidecarClient();
    final cache = _MemoryMetadataCache();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      metadataCache: cache,
      accountWriteCooldown: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    final album = controller.albums.single;
    await controller.openFeedCollection(album, source: 'library');
    final detail = controller.selectedFeedCollection!;

    await controller.toggleAlbumLibrary(detail);
    expect(controller.isAlbumSaved(detail.id), isFalse);

    await controller.toggleAlbumLibrary(detail);
    expect(controller.isAlbumSaved(detail.id), isTrue);
    expect(controller.albumLibraryWriteId, isNull);
    expect(
      client.requests
          .where((request) => request.method == 'album.library.set')
          .map((request) => request.params),
      <Map<String, Object?>>[
        <String, Object?>{'albumId': 'MPRE-saved-album', 'saved': false},
        <String, Object?>{'albumId': 'MPRE-saved-album', 'saved': true},
      ],
    );
    expect(
      client.methods.where((method) => method == 'library.media'),
      hasLength(3),
    );
    final cachedAlbums =
        cache.entries['library.media.v4']!.data['albums']! as List<Object?>;
    expect(
      cachedAlbums.cast<Map<Object?, Object?>>().map((item) => item['id']),
      contains('MPRE-saved-album'),
    );
  });

  test('rolls back an optimistic album update when the write fails', () async {
    final client = _FakeSidecarClient(
      errorMethod: 'album.library.set',
      error: const SidecarException(
        'ALBUM_LIBRARY_UPDATE_FAILED',
        'Album update failed.',
      ),
    );
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      accountWriteCooldown: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');
    final album = controller.albums.single;
    await controller.openFeedCollection(album, source: 'library');

    await controller.toggleAlbumLibrary(controller.selectedFeedCollection!);

    expect(controller.isAlbumSaved(album.id), isTrue);
    expect(controller.albumLibraryWriteId, isNull);
    expect(controller.feedActionErrorMessage, YouTubeLibraryError.actionFailed);
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
        'library.media',
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
    expect(controller.hasMoreHistory, isTrue);
    expect(
      client.methods.where((method) => method == 'history.get'),
      hasLength(1),
    );

    await controller.loadHistory();
    expect(
      client.methods.where((method) => method == 'history.get'),
      hasLength(1),
    );

    await controller.loadMoreHistory();
    expect(controller.historyTracks.map((track) => track.videoId), <String>[
      'history-video',
      'history-video-2',
    ]);
    expect(controller.hasMoreHistory, isFalse);
    expect(
      client.methods.where((method) => method == 'history.more'),
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
      'library.media',
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

    await controller.selectHomeFilter('Sleep');
    expect(
      client.methods.where((method) => method == 'feed.home.filter'),
      hasLength(1),
    );

    await controller.selectHomeFilter('Sleep', forceRefresh: true);
    expect(controller.selectedHomeFilter, 'Sleep');
    expect(controller.homeSections.single.title, 'Sleep picks');
    expect(
      client.methods.where((method) => method == 'feed.home.filter'),
      hasLength(2),
    );
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

  test('ignores legacy Explore v3 cache before loading ranked data', () async {
    final client = _FakeSidecarClient(
      exploreResponse: Future<Map<String, Object?>>.value(
        _rankedExploreResponse('Live ranked track'),
      ),
    );
    final cache = _MemoryMetadataCache()
      ..entries['feed.explore.v3'] = RemoteMetadataCacheEntry(
        cachedAt: DateTime.now(),
        data: _rankedExploreResponse('Legacy rankless track', ranked: false),
      );
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      metadataCache: cache,
    );
    addTearDown(controller.dispose);

    await controller.signInWithCookie('SID=test-cookie');

    final item = controller.exploreSections.single.items.single;
    expect(item.title, 'Live ranked track');
    expect(item.rank, 1);
    expect(item.trend, YouTubeChartTrend.up);
    expect(
      client.methods.where((method) => method == 'feed.explore'),
      hasLength(1),
    );
    expect(cache.entries, contains('feed.explore.v4'));
  });

  test(
    'uses fresh ranked Explore v4 metadata without requesting it again',
    () async {
      final client = _FakeSidecarClient();
      final cache = _MemoryMetadataCache()
        ..entries['feed.explore.v4'] = RemoteMetadataCacheEntry(
          cachedAt: DateTime.now(),
          data: _rankedExploreResponse('Cached ranked track'),
        );
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
        metadataCache: cache,
      );
      addTearDown(controller.dispose);

      await controller.signInWithCookie('SID=test-cookie');

      final item = controller.exploreSections.single.items.single;
      expect(item.title, 'Cached ranked track');
      expect(item.rank, 1);
      expect(item.trend, YouTubeChartTrend.up);
      expect(
        client.methods.where((method) => method == 'feed.explore'),
        isEmpty,
      );
    },
  );

  test('hydrates cached Home continuation before loading more', () async {
    final homeResponse = Completer<Map<String, Object?>>();
    final client = _FakeSidecarClient(homeResponse: homeResponse.future);
    final cache = _MemoryMetadataCache()
      ..entries['feed.home.v2'] = RemoteMetadataCacheEntry(
        cachedAt: DateTime.now(),
        data: <String, Object?>{
          ...client._feed(
            'Cached Home',
            'Cached recommendation',
            'song',
            hasMore: true,
          ),
          'filters': <Object?>['Podcasts', 'Sleep'],
        },
      );
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      metadataCache: cache,
    );
    addTearDown(controller.dispose);

    final signIn = controller.signInWithCookie('SID=test-cookie');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.homeSections.single.title, 'Cached Home');
    expect(controller.hasMoreHome, isTrue);
    await controller.loadMoreHome();
    expect(
      client.methods.where((method) => method == 'feed.home.more'),
      isEmpty,
    );

    homeResponse.complete(<String, Object?>{
      ...client._feed(
        'Hydrated Home',
        'Live recommendation',
        'song',
        hasMore: true,
      ),
      'filters': <Object?>['Podcasts', 'Sleep'],
    });
    await signIn;

    expect(controller.homeSections.single.title, 'Hydrated Home');
    await controller.loadMoreHome();
    expect(
      client.methods,
      containsAllInOrder(<String>['feed.home', 'feed.home.more']),
    );
  });

  test(
    'retains cached Home sections when continuation hydration fails',
    () async {
      final client = _FakeSidecarClient(
        errorMethod: 'feed.home',
        error: const SidecarException('HOME_FEED_FAILED', 'Home failed.'),
      );
      final cache = _MemoryMetadataCache()
        ..entries['feed.home.v2'] = RemoteMetadataCacheEntry(
          cachedAt: DateTime.now(),
          data: <String, Object?>{
            ...client._feed(
              'Cached Home',
              'Cached recommendation',
              'song',
              hasMore: true,
            ),
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
      expect(controller.hasMoreHome, isFalse);
      expect(controller.homeErrorMessage, YouTubeLibraryError.loadFailed);
      await controller.loadMoreHome();
      expect(
        client.methods.where((method) => method == 'feed.home.more'),
        isEmpty,
      );
    },
  );

  test('media library refresh bypasses a fresh cache entry', () async {
    final client = _FakeSidecarClient();
    final cache = _MemoryMetadataCache()
      ..entries['library.media.v4'] = RemoteMetadataCacheEntry(
        cachedAt: DateTime.now(),
        data: <String, Object?>{
          'playlists': <Object?>[],
          'savedCollections': <Object?>[],
          'podcasts': <Object?>[],
          'albums': <Object?>[],
          'followedArtists': <Object?>[],
        },
      );
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      metadataCache: cache,
    );
    addTearDown(controller.dispose);

    await controller.signInWithCookie('SID=test-cookie');
    expect(
      client.methods.where((method) => method == 'library.media'),
      isEmpty,
    );

    await controller.loadMediaLibrary(forceRefresh: true);

    expect(
      client.methods.where((method) => method == 'library.media'),
      hasLength(1),
    );
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

  test(
    'retains episode save-for-later without an automatic library card',
    () async {
      final client = _FakeSidecarClient();
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');
      await controller.resolveFeedTrack(
        YouTubeFeedItem.fromJson(<String, Object?>{
          'id': 'saved-video',
          'videoId': 'saved-video',
          'title': 'Saved episode',
          'subtitle': 'Podcast author',
          'itemType': 'episode',
          'artists': <Object?>['Podcast author'],
          'durationSeconds': 180,
        }),
      );

      await controller.toggleSavedEpisode(
        'saved-video',
        title: 'Saved episode',
        artist: 'Podcast author',
        album: 'Saved podcast',
        artworkUrl: 'https://example.test/saved-episode.jpg',
        durationSeconds: 180,
      );

      expect(controller.isSavedEpisode('saved-video'), isTrue);

      await controller.toggleSavedEpisode(
        'saved-video',
        title: 'Saved episode',
        artist: 'Podcast author',
        album: 'Saved podcast',
        artworkUrl: 'https://example.test/saved-episode.jpg',
        durationSeconds: 180,
      );

      expect(controller.isSavedEpisode('saved-video'), isFalse);
      expect(
        client.methods.where((method) => method == 'podcast.episode_later.set'),
        hasLength(2),
      );
    },
  );

  test('does not send a saved-episode write for an ordinary song', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
      accountWriteCooldown: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');
    client.methods.clear();

    await controller.toggleSavedEpisode(
      'ordinary-song',
      title: 'Ordinary song',
      artist: 'Artist',
      album: 'Album',
      artworkUrl: '',
      durationSeconds: 180,
    );

    expect(controller.isSavedEpisode('ordinary-song'), isFalse);
    expect(client.methods, isNot(contains('podcast.episode_later.set')));
  });

  test(
    'refreshes the media library after saving an episode for later',
    () async {
      final client = _FakeSidecarClient();
      final cache = _MemoryMetadataCache();
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
        metadataCache: cache,
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');
      client.methods.clear();
      await controller.resolveFeedTrack(
        YouTubeFeedItem.fromJson(<String, Object?>{
          'id': 'new-video',
          'videoId': 'new-video',
          'title': 'New episode',
          'subtitle': 'Podcast author',
          'itemType': 'episode',
          'artists': <Object?>['Podcast author'],
          'durationSeconds': 180,
        }),
      );

      await controller.toggleSavedEpisode(
        'new-video',
        title: 'New episode',
        artist: 'Podcast author',
        album: 'Saved podcast',
        artworkUrl: 'https://example.test/new-episode.jpg',
        durationSeconds: 180,
      );

      expect(
        client.methods,
        containsAllInOrder(<String>[
          'podcast.episode_later.set',
          'library.media',
        ]),
      );
      expect(controller.isSavedEpisode('new-video'), isTrue);
      expect(
        cache.entries['library.media.v4']!.data.containsKey('episodePlaylists'),
        isFalse,
      );
    },
  );

  test(
    'keeps a successful saved-episode update when library refresh fails',
    () async {
      final client = _FakeSidecarClient(
        refreshedLibraryError: const SidecarException(
          'YOUTUBE_ERROR',
          'Refresh failed.',
        ),
      );
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');
      await controller.resolveFeedTrack(
        YouTubeFeedItem.fromJson(<String, Object?>{
          'id': 'new-video',
          'videoId': 'new-video',
          'title': 'New episode',
          'subtitle': 'Podcast author',
          'itemType': 'episode',
          'artists': <Object?>['Podcast author'],
          'durationSeconds': 180,
        }),
      );
      await controller.toggleSavedEpisode(
        'new-video',
        title: 'New episode',
        artist: 'Podcast author',
        album: 'Saved podcast',
        artworkUrl: 'https://example.test/new-episode.jpg',
        durationSeconds: 180,
      );

      expect(controller.isSavedEpisode('new-video'), isTrue);
      expect(controller.feedActionErrorMessage, isNull);
    },
  );

  test(
    'keeps a successful podcast removal when library refresh fails',
    () async {
      final client = _FakeSidecarClient(
        refreshedLibraryError: const SidecarException(
          'YOUTUBE_ERROR',
          'Refresh failed.',
        ),
      );
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');
      final savedPodcast = controller.podcasts.single;
      await controller.openFeedBrowse(savedPodcast, source: 'library');

      await controller.togglePodcastLibrary(controller.selectedPodcastShow!);

      expect(controller.isPodcastSaved(savedPodcast.id), isFalse);
      expect(controller.feedActionErrorMessage, isNull);
      expect(
        client.methods,
        containsAllInOrder(<String>['podcast.library.set', 'library.media']),
      );
    },
  );

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

  test('opens a one-track album as a collection detail', () async {
    final client = _FakeSidecarClient(singleCollection: true);
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    final album = controller.exploreSections.single.items.single;
    final tracks = await controller.openFeedCollection(
      album,
      source: 'explore',
    );

    expect(tracks, hasLength(1));
    expect(controller.selectedFeedCollection?.id, album.id);
    expect(controller.selectedFeedCollection?.itemType, 'album');
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

  test(
    'uses refreshed artist metadata and its canonical subscription identity',
    () async {
      final client = _FakeSidecarClient();
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
        accountWriteCooldown: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');

      await controller.openFeedBrowse(
        const YouTubeFeedItem(
          id: 'UCstale-card',
          itemType: 'artist',
          title: 'Stale artist name',
          subtitle: 'Stale metadata',
          artists: <String>[],
          durationSeconds: 0,
          thumbnailUrl: 'https://example.test/stale-artist.jpg',
        ),
        source: 'home',
      );

      final detail = controller.selectedFeedBrowse!;
      expect(detail.title, 'Fresh artist name');
      expect(detail.subtitle, 'Fresh artist metadata');
      expect(detail.audience, 'Monthly audience: 5.6M');
      expect(detail.thumbnailUrl, 'https://example.test/fresh-artist.jpg');
      expect(detail.subscriberCount, '1.2M subscribers');
      expect(detail.channelId, 'UCcanonical-artist');
      expect(detail.sections.map((section) => section.title), <String>[
        'Top songs',
        'Albums',
      ]);
      expect(controller.isFollowingArtist('UCcanonical-artist'), isTrue);

      await controller.toggleArtistFollow(detail.channelId!);

      expect(controller.isFollowingArtist('UCcanonical-artist'), isFalse);
      expect(client.requests.last.method, 'interaction.subscription');
      expect(client.requests.last.params, <String, Object?>{
        'channelId': 'UCcanonical-artist',
        'subscribed': false,
      });
    },
  );

  test('keeps one-track playlists out of the collection detail', () async {
    final client = _FakeSidecarClient(singleCollection: true);
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    final tracks = await controller.openFeedCollection(
      const YouTubeFeedItem(
        id: 'PLsingle',
        itemType: 'playlist',
        title: 'Single-track playlist',
        artists: <String>['Artist'],
        durationSeconds: 0,
      ),
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

  test('silently refreshes suspicious cached feed durations', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    final durationSeconds = await controller.resolveFeedTrackDuration(
      const YouTubeFeedItem(
        id: 'feed-song',
        itemType: 'song',
        title: 'Feed song',
        videoId: 'video-feed-song',
        artists: <String>['Card artist'],
        durationSeconds: 45,
      ),
    );

    expect(durationSeconds, 247);
    expect(client.methods.last, 'feed.track');
    expect(controller.loadingFeedItemId, isNull);
    expect(controller.feedActionErrorMessage, isNull);
    expect(notifications, 0);
  });

  test('searches YouTube Music through the sidecar with a filter', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await controller.searchMusic(
      'night drive',
      filter: YouTubeMusicSearchFilter.album,
    );

    expect(controller.searchQuery, 'night drive');
    expect(controller.searchFilter, YouTubeMusicSearchFilter.album);
    expect(controller.searchResults.single.title, 'Remote result');
    expect(controller.searchResults.single.isPlayable, isTrue);
    expect(client.methods.last, 'search.music');
    expect(client.requests.last.params, <String, Object?>{
      'query': 'night drive',
      'filter': 'album',
    });
  });

  test(
    'keeps the newest search filter when an older request finishes last',
    () async {
      final firstResponse = Completer<Map<String, Object?>>();
      final secondResponse = Completer<Map<String, Object?>>();
      final client = _DeferredSearchSidecarClient(
        <Completer<Map<String, Object?>>>[firstResponse, secondResponse],
      );
      final controller = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');

      final oldSearch = controller.searchMusic(
        'night drive',
        filter: YouTubeMusicSearchFilter.song,
      );
      final newSearch = controller.searchMusic(
        'night drive',
        filter: YouTubeMusicSearchFilter.artist,
      );
      secondResponse.complete(_searchResponse('Newest artist', 'new-artist'));
      await newSearch;
      firstResponse.complete(_searchResponse('Stale song', 'stale-song'));
      await oldSearch;

      expect(controller.searchFilter, YouTubeMusicSearchFilter.artist);
      expect(controller.searchResults.single.title, 'Newest artist');
    },
  );

  test('stores local search state without calling the sidecar', () async {
    final client = _FakeSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);

    await controller.searchMusic(
      'local artist',
      filter: YouTubeMusicSearchFilter.artist,
    );

    expect(controller.searchQuery, 'local artist');
    expect(controller.searchFilter, YouTubeMusicSearchFilter.artist);
    expect(controller.searchResults, isEmpty);
    expect(client.methods, isNot(contains('search.music')));
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

Map<String, Object?> _rankedExploreResponse(
  String title, {
  bool ranked = true,
}) => <String, Object?>{
  'sections': <Object?>[
    <String, Object?>{
      'title': 'Popular songs',
      'items': <Object?>[
        <String, Object?>{
          'id': 'popular-track',
          'itemType': 'song',
          'title': title,
          'videoId': 'popular-track',
          'artists': <String>['Chart artist'],
          'durationSeconds': 180,
          if (ranked) 'rank': 1,
          if (ranked) 'trend': 'up',
        },
      ],
    },
  ],
  'hasMore': false,
};

class _FakeSidecarClient extends YouTubeSidecarClient {
  _FakeSidecarClient({
    this.singleCollection = false,
    this.lyricsResult,
    this.errorMethod,
    this.error,
    this.refreshedLibraryError,
    this.playlistResponse,
    this.homeResponse,
    this.exploreResponse,
  }) : super(entryPath: 'unused');

  final bool singleCollection;
  final Map<String, Object?>? lyricsResult;
  final String? errorMethod;
  final SidecarException? error;
  final SidecarException? refreshedLibraryError;
  final Future<Map<String, Object?>>? playlistResponse;
  final Future<Map<String, Object?>>? homeResponse;
  final Future<Map<String, Object?>>? exploreResponse;
  final StreamController<SidecarEvent> _controller =
      StreamController<SidecarEvent>.broadcast(sync: true);
  final List<String> methods = <String>[];
  final List<_SidecarRequest> requests = <_SidecarRequest>[];
  final Set<String> savedEpisodeVideoIds = <String>{'saved-video'};
  final Set<String> savedPodcastIds = <String>{'MPSP-saved-show'};
  final Set<String> savedAlbumIds = <String>{'MPRE-saved-album'};
  int _libraryMediaRequestCount = 0;

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
      case 'library.media':
        final isRefresh = _libraryMediaRequestCount++ > 0;
        if (isRefresh && refreshedLibraryError != null) {
          throw refreshedLibraryError!;
        }
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
          'podcasts': <Object?>[
            for (final podcastId in savedPodcastIds)
              <String, Object?>{
                'id': podcastId,
                'itemType': 'podcast',
                'title': 'Saved podcast',
                'subtitle': 'Podcast author',
                'artists': <String>['Podcast author'],
                'durationSeconds': 0,
                'thumbnailUrl': 'https://example.test/podcast.jpg',
              },
          ],
          'albums': <Object?>[
            for (final albumId in savedAlbumIds)
              <String, Object?>{
                'id': albumId,
                'itemType': 'album',
                'title': 'Saved album',
                'subtitle': 'Album artist',
                'artists': <String>['Album artist'],
                'durationSeconds': 0,
                'thumbnailUrl': 'https://example.test/album.jpg',
              },
          ],
          'savedCollections': <Object?>[
            <String, Object?>{
              'id': 'liked_videos',
              'specialKind': 'liked_videos',
              'title': 'Liked videos',
            },
          ],
          'followedArtists': <Object?>[
            <String, Object?>{
              'id': 'UCartist-one',
              'itemType': 'artist',
              'title': 'Artist one',
              'subtitle': 'Artist',
              'artists': <String>['Artist one'],
              'durationSeconds': 0,
              'thumbnailUrl': 'https://example.test/artist.jpg',
            },
          ],
        };
      case 'library.playlist':
        if (playlistResponse != null) {
          return await playlistResponse!;
        }
        if (params['playlistId'] == 'SE') {
          return <String, Object?>{
            'playlist': <String, Object?>{
              'id': 'SE',
              'title': 'Episodes for later',
            },
            'tracks': <Object?>[
              for (final videoId in savedEpisodeVideoIds)
                <String, Object?>{
                  'videoId': videoId,
                  'title': videoId == 'saved-video'
                      ? 'Saved episode'
                      : 'New episode',
                  'artists': <String>['Podcast author'],
                  'durationSeconds': 212,
                  'itemType': 'non_music_track',
                },
            ],
            'hasMore': false,
          };
        }
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
          'hasMore': true,
        };
      case 'library.playlist.more':
        return <String, Object?>{
          'tracks': <Object?>[
            <String, Object?>{
              'videoId': 'video-2',
              'title': 'City lights',
              'artists': <String>['Artist'],
              'durationSeconds': 190,
            },
            <String, Object?>{
              'videoId': 'video-3',
              'title': 'Dawn drive',
              'artists': <String>['Artist'],
              'durationSeconds': 200,
            },
          ],
          'hasMore': false,
        };
      case 'library.special':
        return <String, Object?>{
          'playlist': <String, Object?>{
            'id': params['kind']!,
            'specialKind': params['kind']!,
            'title': 'Liked videos',
          },
          'tracks': <Object?>[],
          'hasMore': false,
        };
      case 'library.special.more':
        return const <String, Object?>{'tracks': <Object?>[], 'hasMore': false};
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
          'hasMore': true,
        };
      case 'history.more':
        return <String, Object?>{
          'tracks': <Object?>[
            <String, Object?>{
              'videoId': 'history-video',
              'title': 'History track',
              'artists': <String>['History artist'],
              'durationSeconds': 213,
            },
            <String, Object?>{
              'videoId': 'history-video-2',
              'title': 'Older history track',
              'artists': <String>['History artist'],
              'durationSeconds': 180,
            },
          ],
          'hasMore': false,
        };
      case 'feed.home':
        if (homeResponse != null) {
          return await homeResponse!;
        }
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
        if (exploreResponse != null) {
          return await exploreResponse!;
        }
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
              'libraryId': 'PLsaved-podcast-show',
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
        if (params['itemType'] == 'artist') {
          return <String, Object?>{
            'artist': <String, Object?>{
              'title': 'Fresh artist name',
              'subtitle': 'Fresh artist metadata',
              'audience': 'Monthly audience: 5.6M',
              'thumbnailUrl': 'https://example.test/fresh-artist.jpg',
              'channelId': 'UCcanonical-artist',
              'subscriberCount': '1.2M subscribers',
              'subscribed': true,
            },
            'sections': <Object?>[
              <String, Object?>{
                'title': 'Top songs',
                'items': <Object?>[
                  <String, Object?>{
                    'id': 'artist-top-song',
                    'itemType': 'song',
                    'title': 'Top song',
                    'videoId': 'artist-top-song',
                    'artists': <String>['Fresh artist name'],
                    'durationSeconds': 201,
                  },
                ],
              },
              <String, Object?>{
                'title': 'Albums',
                'items': <Object?>[
                  <String, Object?>{
                    'id': 'artist-album',
                    'itemType': 'album',
                    'title': 'Artist album',
                    'artists': <String>['Fresh artist name'],
                    'durationSeconds': 0,
                  },
                ],
              },
            ],
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
      case 'interaction.subscription':
        return <String, Object?>{
          'channelId': params['channelId']!,
          'subscribed': params['subscribed']!,
        };
      case 'podcast.episode_later.set':
        final videoId = params['videoId']! as String;
        final saved = params['saved']! as bool;
        if (saved) {
          savedEpisodeVideoIds.add(videoId);
        } else {
          savedEpisodeVideoIds.remove(videoId);
        }
        return <String, Object?>{'saved': saved};
      case 'podcast.library.set':
        final podcastId = params['podcastId']! as String;
        final browseId = podcastId == 'PLsaved-podcast-show'
            ? 'MPSP-saved-show'
            : podcastId;
        final saved = params['saved']! as bool;
        if (saved) {
          savedPodcastIds.add(browseId);
        } else {
          savedPodcastIds.remove(browseId);
        }
        return <String, Object?>{'saved': saved};
      case 'album.library.set':
        final albumId = params['albumId']! as String;
        final saved = params['saved']! as bool;
        if (saved) {
          savedAlbumIds.add(albumId);
        } else {
          savedAlbumIds.remove(albumId);
        }
        return <String, Object?>{'albumId': albumId, 'saved': saved};
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

class _DeferredSearchSidecarClient extends _FakeSidecarClient {
  _DeferredSearchSidecarClient(this.responses);

  final List<Completer<Map<String, Object?>>> responses;

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) {
    if (method != 'search.music') {
      return super.call(method, params);
    }
    methods.add(method);
    requests.add(_SidecarRequest(method, Map<String, Object?>.of(params)));
    return responses.removeAt(0).future;
  }
}

Map<String, Object?> _searchResponse(String title, String id) =>
    <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'id': id,
          'itemType': 'artist',
          'title': title,
          'artists': <String>[],
          'durationSeconds': 0,
        },
      ],
    };

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
