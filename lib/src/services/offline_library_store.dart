import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/offline_library.dart';

@immutable
class OfflineLibrarySnapshot {
  const OfflineLibrarySnapshot({
    this.downloadDirectory,
    this.downloads = const <DownloadedTrack>[],
    this.playlists = const <OfflinePlaylist>[],
  });

  factory OfflineLibrarySnapshot.fromJson(Map<String, Object?> json) {
    return OfflineLibrarySnapshot(
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

  final String? downloadDirectory;
  final List<DownloadedTrack> downloads;
  final List<OfflinePlaylist> playlists;

  Map<String, Object?> toJson() => <String, Object?>{
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
      return OfflineLibrarySnapshot.fromJson(decoded.cast<String, Object?>());
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
    if (await musicDirectory.exists()) {
      return musicDirectory.path;
    }
    return '${home.path}${Platform.pathSeparator}otoha${Platform.pathSeparator}download_yt';
  }

  Future<File> _file() async {
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}offline-library',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}library.json');
  }

  Directory _homeDirectory() {
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
}
