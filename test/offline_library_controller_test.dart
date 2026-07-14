import 'dart:async';
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
      expect(await File(offline.downloads.single.filePath).exists(), isTrue);
      expect(store.snapshot.downloads.single.title, 'Offline track');

      await offline.remove(offline.downloads.single);

      expect(offline.downloads, isEmpty);
      expect(await File('${directory.path}/video-id.webm').exists(), isFalse);
    },
  );

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
}

class _MemoryOfflineLibraryStore implements OfflineLibraryStore {
  _MemoryOfflineLibraryStore(this.defaultDirectory, {this.readResult});

  final String defaultDirectory;
  final Future<OfflineLibrarySnapshot>? readResult;
  OfflineLibrarySnapshot snapshot = const OfflineLibrarySnapshot();
  int readCount = 0;

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
      final file = File('$directory${Platform.pathSeparator}video-id.webm');
      await file.writeAsBytes(<int>[1, 2, 3]);
      return <String, Object?>{
        'path': file.path,
        'mimeType': 'audio/webm; codecs="opus"',
      };
    }
    return switch (method) {
      'auth.cookie.signIn' => <String, Object?>{'authenticated': true},
      'library.playlists' => <String, Object?>{'playlists': <Object?>[]},
      'feed.home' ||
      'feed.explore' => <String, Object?>{'sections': <Object?>[]},
      _ => <String, Object?>{},
    };
  }

  @override
  Future<void> dispose() async {}
}
