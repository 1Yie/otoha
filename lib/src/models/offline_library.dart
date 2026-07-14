import 'package:flutter/foundation.dart';

import 'catalog.dart';

@immutable
class DownloadedTrack {
  const DownloadedTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkAsset,
    required this.durationSeconds,
    required this.filePath,
    required this.mimeType,
    required this.downloadedAt,
  });

  factory DownloadedTrack.fromJson(Map<String, Object?> json) {
    return DownloadedTrack(
      videoId: json['videoId']! as String,
      title: json['title']! as String,
      artist: json['artist']! as String,
      album: json['album']! as String,
      artworkAsset: json['artworkAsset']! as String,
      durationSeconds: json['durationSeconds']! as int,
      filePath: json['filePath']! as String,
      mimeType: json['mimeType']! as String,
      downloadedAt: DateTime.parse(json['downloadedAt']! as String),
    );
  }

  final String videoId;
  final String title;
  final String artist;
  final String album;
  final String artworkAsset;
  final int durationSeconds;
  final String filePath;
  final String mimeType;
  final DateTime downloadedAt;

  Track toTrack() => Track(
    id: 'offline:$videoId',
    title: title,
    artist: artist,
    album: album,
    artworkAsset: artworkAsset,
    durationSeconds: durationSeconds,
    lyrics: const <String>[],
    youtubeVideoId: videoId,
    localFilePath: filePath,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'album': album,
    'artworkAsset': artworkAsset,
    'durationSeconds': durationSeconds,
    'filePath': filePath,
    'mimeType': mimeType,
    'downloadedAt': downloadedAt.toIso8601String(),
  };
}

@immutable
class OfflinePlaylist {
  const OfflinePlaylist({
    required this.id,
    required this.name,
    required this.trackVideoIds,
    required this.createdAt,
    this.artworkVideoId,
  });

  factory OfflinePlaylist.fromJson(Map<String, Object?> json) {
    return OfflinePlaylist(
      id: json['id']! as String,
      name: json['name']! as String,
      trackVideoIds:
          (json['trackVideoIds'] as List<Object?>? ?? const <Object?>[])
              .whereType<String>()
              .toList(growable: false),
      createdAt: DateTime.parse(json['createdAt']! as String),
      artworkVideoId: json['artworkVideoId'] as String?,
    );
  }

  final String id;
  final String name;
  final List<String> trackVideoIds;
  final DateTime createdAt;
  final String? artworkVideoId;

  OfflinePlaylist copyWith({
    String? name,
    List<String>? trackVideoIds,
    String? artworkVideoId,
    bool clearArtwork = false,
  }) => OfflinePlaylist(
    id: id,
    name: name ?? this.name,
    trackVideoIds: trackVideoIds ?? this.trackVideoIds,
    createdAt: createdAt,
    artworkVideoId: clearArtwork ? null : artworkVideoId ?? this.artworkVideoId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'trackVideoIds': trackVideoIds,
    'createdAt': createdAt.toIso8601String(),
    'artworkVideoId': artworkVideoId,
  };
}
