import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/youtube_library.dart';

abstract interface class LyricCache {
  Future<List<YouTubeLyricLine>?> read(String videoId);
  Future<void> write(String videoId, List<YouTubeLyricLine> lines);
}

class FileLyricCache implements LyricCache {
  FileLyricCache({this.maxEntries = 512});

  final int maxEntries;

  @override
  Future<List<YouTubeLyricLine>?> read(String videoId) async {
    final entries = await _readEntries();
    final entry = entries[videoId];
    if (entry is! Map<Object?, Object?>) {
      return null;
    }
    final lines = entry['lines'];
    if (lines is! List<Object?>) {
      return null;
    }
    return lines
        .whereType<Map<Object?, Object?>>()
        .map((line) => YouTubeLyricLine.fromJson(line.cast<String, Object?>()))
        .toList(growable: false);
  }

  @override
  Future<void> write(String videoId, List<YouTubeLyricLine> lines) async {
    final entries = await _readEntries();
    entries.remove(videoId);
    entries[videoId] = <String, Object?>{
      'cachedAt': DateTime.now().toIso8601String(),
      'lines': lines
          .map(
            (line) => <String, Object?>{
              'text': line.text,
              'startSeconds': line.startSeconds,
            },
          )
          .toList(growable: false),
    };
    while (entries.length > maxEntries) {
      entries.remove(entries.keys.first);
    }
    await _writeEntries(entries);
  }

  Future<Map<String, Object?>> _readEntries() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return <String, Object?>{};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<Object?, Object?>) {
        return <String, Object?>{};
      }
      return decoded.cast<String, Object?>();
    } on Object {
      return <String, Object?>{};
    }
  }

  Future<void> _writeEntries(Map<String, Object?> entries) async {
    final file = await _file();
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  Future<File> _file() async {
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}lyrics',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}cache.json');
  }
}
