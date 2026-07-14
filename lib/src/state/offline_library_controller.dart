import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/catalog.dart';
import '../models/offline_library.dart';
import '../services/offline_library_store.dart';
import 'youtube_library_controller.dart';

enum OfflineLibraryError {
  directoryUnavailable,
  downloadFailed,
  deleteFailed,
  playlistFailed,
}

class OfflineLibraryController extends ChangeNotifier {
  OfflineLibraryController({
    required this.store,
    required this.youtubeLibraryController,
  });

  final OfflineLibraryStore store;
  final YouTubeLibraryController youtubeLibraryController;

  List<DownloadedTrack> _downloads = const <DownloadedTrack>[];
  List<OfflinePlaylist> _playlists = const <OfflinePlaylist>[];
  String? _downloadDirectory;
  String? _downloadingVideoId;
  bool _isInitialized = false;
  Future<void>? _initialization;
  OfflineLibraryError? _error;

  List<DownloadedTrack> get downloads => _downloads;
  List<OfflinePlaylist> get playlists => _playlists;
  String? get downloadDirectory => _downloadDirectory;
  String? get downloadingVideoId => _downloadingVideoId;
  bool get isInitialized => _isInitialized;
  OfflineLibraryError? get error => _error;

  bool isDownloaded(String videoId) =>
      _downloads.any((track) => track.videoId == videoId);

  Future<void> initialize() {
    if (_isInitialized) {
      return Future<void>.value();
    }
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final snapshot = await store.read();
      _downloads = snapshot.downloads;
      _playlists = snapshot.playlists;
      _downloadDirectory =
          snapshot.downloadDirectory ?? await store.defaultDownloadDirectory();
    } on Object {
      _downloads = const <DownloadedTrack>[];
      _playlists = const <OfflinePlaylist>[];
      _downloadDirectory = null;
      _error = OfflineLibraryError.directoryUnavailable;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setDownloadDirectory(String value) async {
    final directory = value.trim();
    if (directory.isEmpty) {
      _error = OfflineLibraryError.directoryUnavailable;
      notifyListeners();
      return;
    }
    try {
      await Directory(directory).create(recursive: true);
      _downloadDirectory = directory;
      _error = null;
      await _persist();
    } on Object {
      _error = OfflineLibraryError.directoryUnavailable;
    }
    notifyListeners();
  }

  Future<void> download(Track track) async {
    final videoId = track.youtubeVideoId;
    if (videoId == null ||
        videoId.isEmpty ||
        _downloadingVideoId != null ||
        isDownloaded(videoId)) {
      return;
    }
    if (!_isInitialized) {
      await initialize();
    }
    final directory = _downloadDirectory;
    if (directory == null) {
      _error = OfflineLibraryError.directoryUnavailable;
      notifyListeners();
      return;
    }

    _downloadingVideoId = videoId;
    _error = null;
    notifyListeners();
    try {
      await Directory(directory).create(recursive: true);
      final result = await youtubeLibraryController.downloadAudio(
        videoId: videoId,
        directory: directory,
      );
      final path = result['path'] as String?;
      final mimeType = result['mimeType'] as String?;
      if (path == null ||
          path.isEmpty ||
          mimeType == null ||
          mimeType.isEmpty) {
        throw const FormatException('Missing downloaded audio details.');
      }
      _downloads = <DownloadedTrack>[
        DownloadedTrack(
          videoId: videoId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          artworkAsset: track.artworkAsset,
          durationSeconds: track.durationSeconds,
          filePath: path,
          mimeType: mimeType,
          downloadedAt: DateTime.now(),
        ),
        ..._downloads,
      ];
      await _persist();
    } on Object {
      _error = OfflineLibraryError.downloadFailed;
    } finally {
      _downloadingVideoId = null;
      notifyListeners();
    }
  }

  Future<void> remove(DownloadedTrack track) async {
    try {
      final file = File(track.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      _downloads = _downloads
          .where((item) => item.videoId != track.videoId)
          .toList(growable: false);
      _playlists = _playlists
          .map((playlist) {
            final trackVideoIds = playlist.trackVideoIds
                .where((videoId) => videoId != track.videoId)
                .toList(growable: false);
            return playlist.copyWith(
              trackVideoIds: trackVideoIds,
              clearArtwork: playlist.artworkVideoId == track.videoId,
            );
          })
          .toList(growable: false);
      _error = null;
      await _persist();
    } on Object {
      _error = OfflineLibraryError.deleteFailed;
    }
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return;
    }
    if (!_isInitialized) {
      await initialize();
    }
    try {
      _playlists = <OfflinePlaylist>[
        OfflinePlaylist(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          name: trimmedName,
          trackVideoIds: const <String>[],
          createdAt: DateTime.now(),
        ),
        ..._playlists,
      ];
      _error = null;
      await _persist();
    } on Object {
      _error = OfflineLibraryError.playlistFailed;
    }
    notifyListeners();
  }

  Future<void> deletePlaylist(OfflinePlaylist playlist) async {
    try {
      _playlists = _playlists
          .where((item) => item.id != playlist.id)
          .toList(growable: false);
      _error = null;
      await _persist();
    } on Object {
      _error = OfflineLibraryError.playlistFailed;
    }
    notifyListeners();
  }

  Future<void> renamePlaylist({
    required OfflinePlaylist playlist,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName == playlist.name) {
      return;
    }
    await _replacePlaylist(playlist.copyWith(name: trimmedName));
  }

  Future<void> setPlaylistArtwork({
    required OfflinePlaylist playlist,
    required String videoId,
  }) async {
    if (!playlist.trackVideoIds.contains(videoId) ||
        !_downloads.any((track) => track.videoId == videoId) ||
        playlist.artworkVideoId == videoId) {
      return;
    }
    await _replacePlaylist(playlist.copyWith(artworkVideoId: videoId));
  }

  Future<void> addToPlaylist({
    required OfflinePlaylist playlist,
    required DownloadedTrack track,
  }) async {
    if (playlist.trackVideoIds.contains(track.videoId)) {
      return;
    }
    await _replacePlaylist(
      playlist.copyWith(
        trackVideoIds: <String>[...playlist.trackVideoIds, track.videoId],
      ),
    );
  }

  Future<void> removeFromPlaylist({
    required OfflinePlaylist playlist,
    required String videoId,
  }) {
    final trackVideoIds = playlist.trackVideoIds
        .where((id) => id != videoId)
        .toList(growable: false);
    return _replacePlaylist(
      playlist.copyWith(
        trackVideoIds: trackVideoIds,
        clearArtwork: playlist.artworkVideoId == videoId,
      ),
    );
  }

  Future<void> _replacePlaylist(OfflinePlaylist playlist) async {
    try {
      _playlists = _playlists
          .map((item) => item.id == playlist.id ? playlist : item)
          .toList(growable: false);
      _error = null;
      await _persist();
    } on Object {
      _error = OfflineLibraryError.playlistFailed;
    }
    notifyListeners();
  }

  Future<void> _persist() => store.write(
    OfflineLibrarySnapshot(
      downloadDirectory: _downloadDirectory,
      downloads: _downloads,
      playlists: _playlists,
    ),
  );
}
