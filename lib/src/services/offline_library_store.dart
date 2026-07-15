import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/offline_library.dart';

@immutable
class OfflineLibrarySnapshot {
  const OfflineLibrarySnapshot({
    this.version = currentVersion,
    this.downloadDirectory,
    this.downloads = const <DownloadedTrack>[],
    this.playlists = const <OfflinePlaylist>[],
  });

  static const int currentVersion = 2;

  factory OfflineLibrarySnapshot.fromJson(Map<String, Object?> json) {
    return OfflineLibrarySnapshot(
      version: json['version'] as int? ?? 1,
      downloadDirectory: json['downloadDirectory'] as String?,
      downloads: (json['downloads'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map((item) => DownloadedTrack.fromJson(item.cast<String, Object?>()))
          .toList(growable: false),
      playlists: (json['playlists'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map((item) => OfflinePlaylist.fromJson(item.cast<String, Object?>()))
          .toList(growable: false),
    );
  }

  final int version;
  final String? downloadDirectory;
  final List<DownloadedTrack> downloads;
  final List<OfflinePlaylist> playlists;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentVersion,
    'downloadDirectory': downloadDirectory,
    'downloads': downloads.map((track) => track.toJson()).toList(),
    'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
  };
}

abstract interface class OfflineLibraryStore {
  Future<OfflineLibrarySnapshot> read();
  Future<void> write(OfflineLibrarySnapshot snapshot);
  Future<String> defaultDownloadDirectory();
}

class FileOfflineLibraryStore implements OfflineLibraryStore {
  FileOfflineLibraryStore({
    Directory? homeDirectory,
    Directory? applicationSupportDirectory,
  }) : _homeDirectoryOverride = homeDirectory,
       _applicationSupportDirectoryOverride = applicationSupportDirectory;

  final Directory? _homeDirectoryOverride;
  final Directory? _applicationSupportDirectoryOverride;

  @override
  Future<OfflineLibrarySnapshot> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return const OfflineLibrarySnapshot();
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<Object?, Object?>) {
        return const OfflineLibrarySnapshot();
      }
      final snapshot = OfflineLibrarySnapshot.fromJson(
        decoded.cast<String, Object?>(),
      );
      return await _migrateLegacyDefaultDirectory(snapshot);
    } on Object {
      return const OfflineLibrarySnapshot();
    }
  }

  @override
  Future<void> write(OfflineLibrarySnapshot snapshot) async {
    final file = await _file();
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  @override
  Future<String> defaultDownloadDirectory() async {
    final home = _homeDirectory();
    final musicDirectory = await _musicDirectory(home);
    return '${musicDirectory.path}${Platform.pathSeparator}otoha${Platform.pathSeparator}yt_music_download';
  }

  Future<File> _file() async {
    final applicationSupportDirectory =
        _applicationSupportDirectoryOverride ??
        await getApplicationSupportDirectory();
    final directory = Directory(
      '${applicationSupportDirectory.path}${Platform.pathSeparator}offline-library',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}library.json');
  }

  Directory _homeDirectory() {
    if (_homeDirectoryOverride != null) {
      return _homeDirectoryOverride;
    }
    final path =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return Directory(path);
  }

  Future<Directory> _musicDirectory(Directory home) async {
    if (Platform.isLinux) {
      final userDirs = File(
        '${home.path}${Platform.pathSeparator}.config${Platform.pathSeparator}user-dirs.dirs',
      );
      if (await userDirs.exists()) {
        final match = RegExp(
          r'^XDG_MUSIC_DIR="([^"]+)"',
          multiLine: true,
        ).firstMatch(await userDirs.readAsString());
        final configuredPath = match?.group(1);
        if (configuredPath != null && configuredPath.isNotEmpty) {
          return Directory(configuredPath.replaceFirst(r'$HOME', home.path));
        }
      }
    }
    return Directory('${home.path}${Platform.pathSeparator}Music');
  }

  Future<OfflineLibrarySnapshot> _migrateLegacyDefaultDirectory(
    OfflineLibrarySnapshot snapshot,
  ) async {
    final savedDirectory = snapshot.downloadDirectory;
    if (snapshot.version >= OfflineLibrarySnapshot.currentVersion ||
        savedDirectory == null ||
        savedDirectory.isEmpty) {
      return snapshot;
    }
    final home = _homeDirectory();
    final musicDirectory = await _musicDirectory(home);
    final oldFallback =
        '${home.path}${Platform.pathSeparator}otoha${Platform.pathSeparator}download_yt';
    if (!_samePath(savedDirectory, musicDirectory.path) &&
        !_samePath(savedDirectory, oldFallback)) {
      return snapshot;
    }
    final migrated = OfflineLibrarySnapshot(
      downloadDirectory: await defaultDownloadDirectory(),
      downloads: snapshot.downloads,
      playlists: snapshot.playlists,
    );
    try {
      await write(migrated);
    } on Object {
      // Keep the migrated in-memory value even if persistence is unavailable.
    }
    return migrated;
  }

  bool _samePath(String left, String right) {
    String normalize(String value) {
      final normalized = value.replaceAll(RegExp(r'[\\/]+$'), '');
      return Platform.isWindows ? normalized.toLowerCase() : normalized;
    }

    return normalize(left) == normalize(right);
  }
}
