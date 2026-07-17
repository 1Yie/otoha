import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/models/catalog.dart';
import 'package:otoha/src/models/offline_library.dart';
import 'package:otoha/src/services/credential_store.dart';
import 'package:otoha/src/services/offline_library_store.dart';
import 'package:otoha/src/services/youtube_sidecar_client.dart';
import 'package:otoha/src/state/offline_library_controller.dart';
import 'package:otoha/src/state/youtube_library_controller.dart';

void main() {
  test('places default downloads under Music/otoha/yt_music_download', () async {
    final home = await Directory.systemTemp.createTemp('otoha-home-');
    addTearDown(() => home.delete(recursive: true));
    var musicPath = '${home.path}${Platform.pathSeparator}Music';
    if (Platform.isLinux) {
      final config = Directory('${home.path}${Platform.pathSeparator}.config');
      await config.create(recursive: true);
      musicPath = '${home.path}${Platform.pathSeparator}My Music';
      await File(
        '${config.path}${Platform.pathSeparator}user-dirs.dirs',
      ).writeAsString('XDG_MUSIC_DIR="\$HOME/My Music"\n');
    }
    final store = FileOfflineLibraryStore(homeDirectory: home);

    expect(
      await store.defaultDownloadDirectory(),
      '$musicPath${Platform.pathSeparator}otoha${Platform.pathSeparator}yt_music_download',
    );
  });

  test(
    'migrates the persisted legacy default without losing playlists',
    () async {
      final home = await Directory.systemTemp.createTemp('otoha-legacy-home-');
      final support = Directory('${home.path}/support');
      addTearDown(() => home.delete(recursive: true));
      var musicPath = '${home.path}${Platform.pathSeparator}Music';
      if (Platform.isLinux) {
        final config = Directory(
          '${home.path}${Platform.pathSeparator}.config',
        );
        await config.create(recursive: true);
        musicPath = '${home.path}${Platform.pathSeparator}My Music';
        await Directory(musicPath).create(recursive: true);
        await File(
          '${config.path}${Platform.pathSeparator}user-dirs.dirs',
        ).writeAsString('XDG_MUSIC_DIR="\$HOME/My Music"\n');
      }
      final libraryDirectory = Directory(
        '${support.path}${Platform.pathSeparator}offline-library',
      );
      await libraryDirectory.create(recursive: true);
      final libraryFile = File(
        '${libraryDirectory.path}${Platform.pathSeparator}library.json',
      );
      await libraryFile.writeAsString(
        jsonEncode(<String, Object?>{
          'downloadDirectory': musicPath,
          'downloads': <Object?>[],
          'playlists': <Object?>[
            <String, Object?>{
              'id': 'kept-playlist',
              'name': 'Keep me',
              'trackVideoIds': <String>[],
              'createdAt': '2026-01-01T00:00:00.000Z',
              'artworkVideoId': null,
            },
          ],
        }),
      );
      final store = FileOfflineLibraryStore(
        homeDirectory: home,
        applicationSupportDirectory: support,
      );

      final snapshot = await store.read();

      final expected =
          '$musicPath${Platform.pathSeparator}otoha${Platform.pathSeparator}yt_music_download';
      expect(snapshot.downloadDirectory, expected);
      expect(snapshot.playlists.single.name, 'Keep me');
      final persisted = jsonDecode(await libraryFile.readAsString()) as Map;
      expect(persisted['version'], OfflineLibrarySnapshot.currentVersion);
      expect(persisted['downloadDirectory'], expected);
      expect((persisted['playlists'] as List).single['name'], 'Keep me');
    },
  );

  test('preserves a custom directory from a legacy snapshot', () async {
    final root = await Directory.systemTemp.createTemp('otoha-custom-home-');
    final support = Directory('${root.path}/support');
    addTearDown(() => root.delete(recursive: true));
    final libraryDirectory = Directory(
      '${support.path}${Platform.pathSeparator}offline-library',
    );
    await libraryDirectory.create(recursive: true);
    final customPath = '${root.path}${Platform.pathSeparator}custom-downloads';
    await File(
      '${libraryDirectory.path}${Platform.pathSeparator}library.json',
    ).writeAsString(
      jsonEncode(<String, Object?>{
        'downloadDirectory': customPath,
        'downloads': <Object?>[],
        'playlists': <Object?>[],
      }),
    );
    final store = FileOfflineLibraryStore(
      homeDirectory: root,
      applicationSupportDirectory: support,
    );

    final snapshot = await store.read();

    expect(snapshot.downloadDirectory, customPath);
  });

  test(
    'records a user-initiated download and removes its local file',
    () async {
      final directory = await Directory.systemTemp.createTemp('otoha-offline-');
      final client = _DownloadSidecarClient();
      final youtube = YouTubeLibraryController(
        client: client,
        credentialStore: _MemoryCredentialStore(),
      );
      final store = _MemoryOfflineLibraryStore(directory.path);
      final offline = OfflineLibraryController(
        store: store,
        youtubeLibraryController: youtube,
      );
      addTearDown(youtube.dispose);
      addTearDown(offline.dispose);
      addTearDown(() => directory.delete(recursive: true));
      await youtube.signInWithCookie('SID=test-cookie');
      await offline.initialize();
      const track = Track(
        id: 'youtube:video-id',
        title: 'Offline track',
        artist: 'Artist',
        album: 'Album',
        artworkAsset: 'assets/artwork/cover_01.png',
        durationSeconds: 180,
        lyrics: <String>[],
        youtubeVideoId: 'video-id',
      );

      await offline.download(track);

      expect(client.downloadDirectories, <String>[directory.path]);
      expect(offline.downloads.single.videoId, 'video-id');
      final download = offline.downloads.single;
      expect(await File(download.filePath).exists(), isTrue);
      expect(await File(download.artworkAsset).exists(), isTrue);
      expect(await File(download.lyricsPath!).exists(), isTrue);
      expect(await Directory(download.bundlePath!).exists(), isTrue);
      expect(download.toTrack().localLyricsPath, download.lyricsPath);
      expect(client.downloadRequests.single['title'], 'Offline track');
      expect(client.downloadRequests.single['artist'], 'Artist');
      expect(client.downloadRequests.single['album'], 'Album');
      expect(client.downloadRequests.single['durationSeconds'], 180);
      expect(store.snapshot.downloads.single.title, 'Offline track');

      await offline.remove(offline.downloads.single);

      expect(offline.downloads, isEmpty);
      expect(await Directory('${directory.path}/video-id').exists(), isFalse);
    },
  );

  test('removes a completed bundle when library persistence fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'otoha-offline-failed-persist-',
    );
    final client = _DownloadSidecarClient();
    final youtube = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    final store = _FailingOfflineLibraryStore(directory.path);
    final offline = OfflineLibraryController(
      store: store,
      youtubeLibraryController: youtube,
    );
    addTearDown(youtube.dispose);
    addTearDown(offline.dispose);
    addTearDown(() => directory.delete(recursive: true));
    await youtube.signInWithCookie('SID=test-cookie');
    await offline.initialize();

    await offline.download(
      const Track(
        id: 'youtube:video-id',
        title: 'Offline track',
        artist: 'Artist',
        album: 'Album',
        artworkAsset: 'https://example.test/cover.jpg',
        durationSeconds: 180,
        lyrics: <String>[],
        youtubeVideoId: 'video-id',
      ),
    );

    expect(offline.error, OfflineLibraryError.downloadFailed);
    expect(offline.downloads, isEmpty);
    expect(await Directory('${directory.path}/video-id').exists(), isFalse);
  });

  test('decodes legacy single-file downloads without bundle fields', () {
    final track = DownloadedTrack.fromJson(<String, Object?>{
      'videoId': 'legacy-video',
      'title': 'Legacy track',
      'artist': 'Artist',
      'album': 'Album',
      'artworkAsset': 'https://example.test/cover.jpg',
      'durationSeconds': 120,
      'filePath': '/legacy/audio.webm',
      'mimeType': 'audio/webm',
      'downloadedAt': '2026-01-01T00:00:00.000Z',
    });

    expect(track.bundlePath, isNull);
    expect(track.lyricsPath, isNull);
    expect(track.toTrack().localFilePath, '/legacy/audio.webm');
    expect(track.toTrack().localLyricsPath, isNull);
  });

  test(
    'persists playlist edits and clears artwork for deleted tracks',
    () async {
      final track = DownloadedTrack(
        videoId: 'video-id',
        title: 'Offline track',
        artist: 'Artist',
        album: 'Album',
        artworkAsset: 'assets/artwork/cover_01.png',
        durationSeconds: 180,
        filePath: '${Directory.systemTemp.path}/missing-audio.webm',
        mimeType: 'audio/webm',
        downloadedAt: DateTime(2026),
      );
      final store = _MemoryOfflineLibraryStore(
        Directory.systemTemp.path,
      )..snapshot = OfflineLibrarySnapshot(downloads: <DownloadedTrack>[track]);
      final youtube = YouTubeLibraryController(
        client: _DownloadSidecarClient(),
        credentialStore: _MemoryCredentialStore(),
      );
      final offline = OfflineLibraryController(
        store: store,
        youtubeLibraryController: youtube,
      );
      addTearDown(youtube.dispose);
      addTearDown(offline.dispose);
      await offline.initialize();

      await offline.createPlaylist('Offline favorites');
      final playlist = offline.playlists.single;
      await offline.addToPlaylist(playlist: playlist, track: track);
      await offline.renamePlaylist(
        playlist: offline.playlists.single,
        name: '  Renamed favorites  ',
      );
      await offline.setPlaylistArtwork(
        playlist: offline.playlists.single,
        videoId: track.videoId,
      );

      expect(store.snapshot.playlists.single.name, 'Renamed favorites');
      expect(store.snapshot.playlists.single.trackVideoIds, <String>[
        'video-id',
      ]);
      expect(store.snapshot.playlists.single.artworkVideoId, 'video-id');

      await offline.remove(track);

      expect(offline.playlists.single.trackVideoIds, isEmpty);
      expect(offline.playlists.single.artworkVideoId, isNull);
      expect(store.snapshot.playlists.single.trackVideoIds, isEmpty);
      expect(store.snapshot.playlists.single.artworkVideoId, isNull);
    },
  );

  test('coalesces concurrent persisted library initialization', () async {
    final readCompleter = Completer<OfflineLibrarySnapshot>();
    final store = _MemoryOfflineLibraryStore(
      Directory.systemTemp.path,
      readResult: readCompleter.future,
    );
    final youtube = YouTubeLibraryController(
      client: _DownloadSidecarClient(),
      credentialStore: _MemoryCredentialStore(),
    );
    final offline = OfflineLibraryController(
      store: store,
      youtubeLibraryController: youtube,
    );
    addTearDown(youtube.dispose);
    addTearDown(offline.dispose);

    final first = offline.initialize();
    final second = offline.initialize();
    expect(store.readCount, 1);

    readCompleter.complete(const OfflineLibrarySnapshot());
    await Future.wait(<Future<void>>[first, second]);

    expect(offline.isInitialized, isTrue);
    expect(store.readCount, 1);
  });

  test('batches playlist additions and confirmed download removals', () async {
    final directory = await Directory.systemTemp.createTemp(
      'otoha-offline-batch-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final first = _downloadedTrack('first', directory.path);
    final second = _downloadedTrack('second', directory.path);
    final third = _downloadedTrack('third', directory.path);
    await Future.wait<File>(
      <DownloadedTrack>[
        first,
        second,
        third,
      ].map((track) => File(track.filePath).writeAsBytes(<int>[1, 2, 3])),
    );
    final playlist = OfflinePlaylist(
      id: 'playlist-id',
      name: 'Offline favorites',
      trackVideoIds: <String>[first.videoId],
      artworkVideoId: first.videoId,
      createdAt: DateTime(2026),
    );
    final store = _MemoryOfflineLibraryStore(directory.path)
      ..snapshot = OfflineLibrarySnapshot(
        downloads: <DownloadedTrack>[first, second, third],
        playlists: <OfflinePlaylist>[playlist],
      );
    final youtube = YouTubeLibraryController(
      client: _DownloadSidecarClient(),
      credentialStore: _MemoryCredentialStore(),
    );
    final offline = OfflineLibraryController(
      store: store,
      youtubeLibraryController: youtube,
    );
    addTearDown(youtube.dispose);
    addTearDown(offline.dispose);
    await offline.initialize();

    await offline.addManyToPlaylist(
      playlist: offline.playlists.single,
      tracks: <DownloadedTrack>[first, second, second],
    );

    expect(offline.playlists.single.trackVideoIds, <String>['first', 'second']);
    expect(store.writeCount, 1);

    await offline.removeMany(<DownloadedTrack>[first, second]);

    expect(offline.downloads.map((track) => track.videoId), <String>['third']);
    expect(offline.playlists.single.trackVideoIds, isEmpty);
    expect(offline.playlists.single.artworkVideoId, isNull);
    expect(await File(first.filePath).exists(), isFalse);
    expect(await File(second.filePath).exists(), isFalse);
    expect(await File(third.filePath).exists(), isTrue);
    expect(store.writeCount, 2);
  });
}

DownloadedTrack _downloadedTrack(String videoId, String directory) {
  return DownloadedTrack(
    videoId: videoId,
    title: 'Track $videoId',
    artist: 'Artist',
    album: 'Album',
    artworkAsset: 'assets/artwork/cover_01.png',
    durationSeconds: 180,
    filePath: '$directory${Platform.pathSeparator}$videoId.webm',
    mimeType: 'audio/webm',
    downloadedAt: DateTime(2026),
  );
}

class _MemoryOfflineLibraryStore implements OfflineLibraryStore {
  _MemoryOfflineLibraryStore(this.defaultDirectory, {this.readResult});

  final String defaultDirectory;
  final Future<OfflineLibrarySnapshot>? readResult;
  OfflineLibrarySnapshot snapshot = const OfflineLibrarySnapshot();
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<String> defaultDownloadDirectory() async => defaultDirectory;

  @override
  Future<OfflineLibrarySnapshot> read() async {
    readCount += 1;
    return await readResult ?? snapshot;
  }

  @override
  Future<void> write(OfflineLibrarySnapshot snapshot) async {
    this.snapshot = snapshot;
    writeCount += 1;
  }
}

class _FailingOfflineLibraryStore extends _MemoryOfflineLibraryStore {
  _FailingOfflineLibraryStore(super.defaultDirectory);

  @override
  Future<void> write(OfflineLibrarySnapshot snapshot) async {
    throw const FileSystemException('Unable to persist offline library.');
  }
}

class _MemoryCredentialStore implements CredentialStore {
  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _DownloadSidecarClient extends YouTubeSidecarClient {
  final List<String> downloadDirectories = <String>[];
  final List<Map<String, Object?>> downloadRequests = <Map<String, Object?>>[];

  @override
  Stream<SidecarEvent> get events => const Stream<SidecarEvent>.empty();

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    if (method == 'download.track') {
      final directory = params['directory']! as String;
      downloadDirectories.add(directory);
      downloadRequests.add(Map<String, Object?>.of(params));
      final bundle = Directory('$directory${Platform.pathSeparator}video-id');
      await bundle.create(recursive: true);
      final file = File('${bundle.path}${Platform.pathSeparator}audio.webm');
      final artwork = File('${bundle.path}${Platform.pathSeparator}cover.jpg');
      final lyrics = File('${bundle.path}${Platform.pathSeparator}lyrics.lrc');
      await file.writeAsBytes(<int>[1, 2, 3]);
      await artwork.writeAsBytes(<int>[4, 5, 6]);
      await lyrics.writeAsString('[00:01.00]First line\n');
      return <String, Object?>{
        'bundlePath': bundle.path,
        'path': file.path,
        'artworkPath': artwork.path,
        'lyricsPath': lyrics.path,
        'mimeType': 'audio/webm; codecs="opus"',
      };
    }
    return switch (method) {
      'auth.cookie.signIn' => <String, Object?>{'authenticated': true},
      'library.media' => <String, Object?>{
        'playlists': <Object?>[],
        'savedCollections': <Object?>[],
        'followedArtists': <Object?>[],
      },
      'feed.home' ||
      'feed.explore' => <String, Object?>{'sections': <Object?>[]},
      _ => <String, Object?>{},
    };
  }

  @override
  Future<void> dispose() async {}
}
