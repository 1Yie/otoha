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
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String artworkAsset;
  final int durationSeconds;
  final List<String> lyrics;

  factory Track.fromJson(Map<String, Object?> json) {
    return Track(
      id: json['id']! as String,
      title: json['title']! as String,
      artist: json['artist']! as String,
      album: json['album']! as String,
      artworkAsset: json['artworkAsset']! as String,
      durationSeconds: json['durationSeconds']! as int,
      lyrics: (json['lyrics']! as List<Object?>).cast<String>(),
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
  };
}
