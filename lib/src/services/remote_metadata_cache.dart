import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RemoteMetadataCacheEntry {
  const RemoteMetadataCacheEntry({required this.cachedAt, required this.data});

  final DateTime cachedAt;
  final Map<String, Object?> data;

  bool isFresh(Duration maxAge) =>
      DateTime.now().difference(cachedAt) <= maxAge;
}

abstract class RemoteMetadataCache {
  Future<RemoteMetadataCacheEntry?> read(String key);
  Future<void> write(String key, Map<String, Object?> data);
  Future<void> clear();
}

class FileRemoteMetadataCache implements RemoteMetadataCache {
  FileRemoteMetadataCache({
    this.maxEntries = 64,
    this.maxBytes = 8 * 1024 * 1024,
  });

  final int maxEntries;
  final int maxBytes;

  Future<Directory>? _directory;

  @override
  Future<RemoteMetadataCacheEntry?> read(String key) async {
    try {
      final file = await _fileFor(key);
      if (!await file.exists()) {
        return null;
      }
      final json =
          (jsonDecode(await file.readAsString()) as Map<Object?, Object?>)
              .cast<String, Object?>();
      final cachedAt = DateTime.tryParse(json['cachedAt'] as String? ?? '');
      final data = json['data'];
      if (cachedAt == null || data is! Map<Object?, Object?>) {
        await file.delete();
        return null;
      }
      return RemoteMetadataCacheEntry(
        cachedAt: cachedAt,
        data: data.cast<String, Object?>(),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    try {
      final file = await _fileFor(key);
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'cachedAt': DateTime.now().toUtc().toIso8601String(),
          'data': data,
        }),
        flush: true,
      );
      await _prune();
    } on Object {
      // A cache miss must never interrupt remote playback or discovery.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final directory = await _cacheDirectory();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      _directory = null;
    } on Object {
      // Sign-out remains successful even when cache cleanup is unavailable.
    }
  }

  Future<File> _fileFor(String key) async {
    final directory = await _cacheDirectory();
    final name = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('${directory.path}/$name.json');
  }

  Future<Directory> _cacheDirectory() async {
    return _directory ??= _createCacheDirectory();
  }

  Future<Directory> _createCacheDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(
      '${supportDirectory.path}/remote-metadata-cache',
    ).create(recursive: true);
  }

  Future<void> _prune() async {
    final directory = await _cacheDirectory();
    final files = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File) {
        files.add(entity);
      }
    }
    files.sort((a, b) {
      final aTime = a.statSync().modified;
      final bTime = b.statSync().modified;
      return aTime.compareTo(bTime);
    });

    var totalBytes = 0;
    for (final file in files) {
      totalBytes += await file.length();
    }
    while (files.length > maxEntries || totalBytes > maxBytes) {
      final oldest = files.removeAt(0);
      totalBytes -= await oldest.length();
      await oldest.delete();
    }
  }
}
