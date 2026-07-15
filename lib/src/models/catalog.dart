import 'package:flutter/material.dart';

@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkAsset,
    required this.durationSeconds,
    required this.lyrics,
    this.youtubeVideoId,
    this.localFilePath,
    this.localLyricsPath,
    this.isVideo = false,
    this.videoAvailable = false,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String artworkAsset;
  final int durationSeconds;
  final List<String> lyrics;
  final String? youtubeVideoId;
  final String? localFilePath;
  final String? localLyricsPath;
  final bool isVideo;
  final bool videoAvailable;

  bool get canPlayVideo => videoAvailable || isVideo;

  Track withVideoMode(bool enabled) {
    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      artworkAsset: artworkAsset,
      durationSeconds: durationSeconds,
      lyrics: lyrics,
      youtubeVideoId: youtubeVideoId,
      localFilePath: localFilePath,
      localLyricsPath: localLyricsPath,
      isVideo: enabled && canPlayVideo,
      videoAvailable: canPlayVideo,
    );
  }

  factory Track.fromJson(Map<String, Object?> json) {
    return Track(
      id: json['id']! as String,
      title: json['title']! as String,
      artist: json['artist']! as String,
      album: json['album']! as String,
      artworkAsset: json['artworkAsset']! as String,
      durationSeconds: json['durationSeconds']! as int,
      lyrics: (json['lyrics']! as List<Object?>).cast<String>(),
      youtubeVideoId: json['youtubeVideoId'] as String?,
      localFilePath: json['localFilePath'] as String?,
      localLyricsPath: json['localLyricsPath'] as String?,
      isVideo: json['isVideo'] as bool? ?? false,
      videoAvailable:
          json['videoAvailable'] as bool? ??
          (json['isVideo'] as bool? ?? false),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'artworkAsset': artworkAsset,
    'durationSeconds': durationSeconds,
    'lyrics': lyrics,
    'youtubeVideoId': youtubeVideoId,
    'localFilePath': localFilePath,
    'localLyricsPath': localLyricsPath,
    'isVideo': isVideo,
    'videoAvailable': videoAvailable,
  };
}
