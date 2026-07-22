import 'package:flutter/foundation.dart';

@immutable
class SavedCredential {
  const SavedCredential({required this.kind, required this.value});

  factory SavedCredential.fromJson(Map<String, Object?> json) {
    return SavedCredential(
      kind: json['kind']! as String,
      value: json['value']!,
    );
  }

  final String kind;
  final Object value;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'value': value,
  };
}

@immutable
class YouTubePlaylist {
  const YouTubePlaylist({
    required this.id,
    required this.title,
    this.owner,
    this.itemCount,
    this.thumbnailUrl,
    this.description,
    this.specialKind,
  });

  factory YouTubePlaylist.fromJson(Map<String, Object?> json) {
    return YouTubePlaylist(
      id: json['id']! as String,
      title: json['title']! as String,
      owner: _metadataString(json['owner']),
      itemCount: _metadataString(json['itemCount']),
      thumbnailUrl: _metadataString(json['thumbnailUrl']),
      description: _metadataString(json['description']),
      specialKind: _metadataString(json['specialKind']),
    );
  }

  final String id;
  final String title;
  final String? owner;
  final String? itemCount;
  final String? thumbnailUrl;
  final String? description;
  final String? specialKind;
}

@immutable
class YouTubeTrack {
  const YouTubeTrack({
    required this.videoId,
    required this.title,
    required this.artists,
    required this.durationSeconds,
    this.itemType = 'song',
    this.album,
    this.thumbnailUrl,
  });

  factory YouTubeTrack.fromJson(Map<String, Object?> json) {
    return YouTubeTrack(
      videoId: json['videoId']! as String,
      title: json['title']! as String,
      artists: (json['artists']! as List<Object?>).cast<String>(),
      durationSeconds: json['durationSeconds']! as int,
      itemType: json['itemType'] as String? ?? 'song',
      album: json['album'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }

  final String videoId;
  final String title;
  final List<String> artists;
  final int durationSeconds;
  final String itemType;
  final String? album;
  final String? thumbnailUrl;

  bool get isVideo => itemType == 'video';
}

@immutable
class YouTubeLyricLine {
  const YouTubeLyricLine({required this.text, this.startSeconds});

  factory YouTubeLyricLine.fromJson(Map<String, Object?> json) {
    return YouTubeLyricLine(
      text: json['text']! as String,
      startSeconds: (json['startSeconds'] as num?)?.toDouble(),
    );
  }

  final String text;
  final double? startSeconds;
}

enum YouTubeRating {
  none('none'),
  liked('like'),
  disliked('dislike');

  const YouTubeRating(this.protocolValue);

  final String protocolValue;
}

@immutable
class YouTubeComment {
  const YouTubeComment({
    required this.id,
    required this.author,
    required this.text,
    this.publishedTime,
    this.avatarUrl,
    this.likeCount,
  });

  factory YouTubeComment.fromJson(Map<String, Object?> json) {
    return YouTubeComment(
      id: json['id']! as String,
      author: json['author']! as String,
      text: json['text']! as String,
      publishedTime: json['publishedTime'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      likeCount: json['likeCount'] as String?,
    );
  }

  final String id;
  final String author;
  final String text;
  final String? publishedTime;
  final String? avatarUrl;
  final String? likeCount;
}

@immutable
class YouTubePlaylistDetail {
  const YouTubePlaylistDetail({
    required this.playlist,
    required this.tracks,
    this.hasMore = false,
  });

  factory YouTubePlaylistDetail.fromJson(Map<String, Object?> json) {
    return YouTubePlaylistDetail(
      playlist: YouTubePlaylist.fromJson(
        (json['playlist']! as Map<Object?, Object?>).cast<String, Object?>(),
      ),
      tracks: (json['tracks']! as List<Object?>)
          .map(
            (item) => YouTubeTrack.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  final YouTubePlaylist playlist;
  final List<YouTubeTrack> tracks;
  final bool hasMore;

  YouTubePlaylistDetail copyWith({List<YouTubeTrack>? tracks, bool? hasMore}) {
    return YouTubePlaylistDetail(
      playlist: playlist,
      tracks: tracks ?? this.tracks,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

String? _metadataString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.toLowerCase() == 'n/a') {
    return null;
  }
  return normalized;
}

@immutable
class YouTubeFeedSection {
  const YouTubeFeedSection({
    required this.title,
    required this.items,
    this.subtitle,
    this.itemsPerColumn = 1,
  });

  factory YouTubeFeedSection.fromJson(Map<String, Object?> json) {
    return YouTubeFeedSection(
      title: json['title']! as String,
      subtitle: _metadataString(json['subtitle']),
      itemsPerColumn: json['itemsPerColumn'] as int? ?? 1,
      items: (json['items']! as List<Object?>)
          .map(
            (item) => YouTubeFeedItem.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  final String title;
  final String? subtitle;
  final List<YouTubeFeedItem> items;
  final int itemsPerColumn;
}

@immutable
class YouTubeChannelProfile {
  const YouTubeChannelProfile({
    required this.channelSections,
    this.displayName,
    this.avatarUrl,
    this.handle,
    this.channelId,
    this.subscriberText,
    this.bannerUrl,
    this.channelUrl,
    this.studioUrl,
  });

  factory YouTubeChannelProfile.fromJson(Map<String, Object?> json) {
    final profileValue = json['profile'];
    final profile = profileValue is Map<Object?, Object?>
        ? profileValue.cast<String, Object?>()
        : const <String, Object?>{};
    final contentValue = json['content'];
    final content = contentValue is Map<Object?, Object?>
        ? contentValue.cast<String, Object?>()
        : const <String, Object?>{};
    final channelSections = content['sections'];
    return YouTubeChannelProfile(
      displayName: _metadataString(profile['displayName']),
      avatarUrl: _metadataString(profile['avatarUrl']),
      handle: _metadataString(profile['handle']),
      channelId: _metadataString(profile['channelId']),
      subscriberText: _metadataString(profile['subscriberText']),
      bannerUrl: _metadataString(profile['bannerUrl']),
      channelUrl: _metadataString(profile['channelUrl']),
      studioUrl: _metadataString(profile['studioUrl']),
      channelSections: channelSections is List<Object?>
          ? channelSections
                .whereType<Map<Object?, Object?>>()
                .map(
                  (item) =>
                      YouTubeFeedSection.fromJson(item.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const <YouTubeFeedSection>[],
    );
  }

  final String? displayName;
  final String? avatarUrl;
  final String? handle;
  final String? channelId;
  final String? subscriberText;
  final String? bannerUrl;
  final String? channelUrl;
  final String? studioUrl;
  final List<YouTubeFeedSection> channelSections;
}

@immutable
class YouTubeFeedBrowseDetail {
  const YouTubeFeedBrowseDetail({
    required this.source,
    required this.id,
    required this.itemType,
    required this.title,
    required this.sections,
    this.subtitle,
    this.audience,
    this.thumbnailUrl,
    this.channelId,
    this.subscriberCount,
  });

  final String source;
  final String id;
  final String itemType;
  final String title;
  final String? subtitle;
  final String? audience;
  final String? thumbnailUrl;
  final String? channelId;
  final String? subscriberCount;
  final List<YouTubeFeedSection> sections;
}

@immutable
class YouTubePodcastShowDetail {
  const YouTubePodcastShowDetail({
    required this.source,
    required this.id,
    required this.libraryId,
    required this.title,
    required this.episodes,
    required this.hasMore,
    this.subtitle,
    this.description,
    this.thumbnailUrl,
  });

  factory YouTubePodcastShowDetail.fromJson(
    Map<String, Object?> json, {
    required String source,
  }) {
    return YouTubePodcastShowDetail(
      source: source,
      id: json['id']! as String,
      libraryId: json['libraryId'] as String? ?? json['id']! as String,
      title: json['title']! as String,
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      episodes: (json['episodes']! as List<Object?>)
          .map(
            (item) => YouTubeFeedItem.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  final String source;
  final String id;
  final String libraryId;
  final String title;
  final String? subtitle;
  final String? description;
  final String? thumbnailUrl;
  final List<YouTubeFeedItem> episodes;
  final bool hasMore;

  YouTubePodcastShowDetail copyWith({
    List<YouTubeFeedItem>? episodes,
    bool? hasMore,
  }) {
    return YouTubePodcastShowDetail(
      source: source,
      id: id,
      libraryId: libraryId,
      title: title,
      subtitle: subtitle,
      description: description,
      thumbnailUrl: thumbnailUrl,
      episodes: episodes ?? this.episodes,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

@immutable
class YouTubeFeedCollectionDetail {
  const YouTubeFeedCollectionDetail({
    required this.source,
    required this.id,
    required this.title,
    required this.itemType,
    required this.tracks,
    this.artists = const <String>[],
    this.thumbnailUrl,
  });

  final String source;
  final String id;
  final String title;
  final String itemType;
  final List<YouTubeTrack> tracks;
  final List<String> artists;
  final String? thumbnailUrl;
}

enum YouTubeChartTrend {
  up,
  down,
  neutral;

  static YouTubeChartTrend? fromProtocol(String? value) {
    return switch (value) {
      'up' => YouTubeChartTrend.up,
      'down' => YouTubeChartTrend.down,
      'neutral' => YouTubeChartTrend.neutral,
      _ => null,
    };
  }
}

enum YouTubeMusicSearchFilter {
  all,
  song,
  album,
  artist,
  playlist,
  video;

  String get protocolValue => name;
}

@immutable
class YouTubeFeedItem {
  const YouTubeFeedItem({
    required this.id,
    required this.itemType,
    required this.title,
    required this.artists,
    required this.durationSeconds,
    this.subtitle,
    this.description,
    this.videoId,
    this.browseParams,
    this.album,
    this.thumbnailUrl,
    this.rank,
    this.trend,
  });

  factory YouTubeFeedItem.fromJson(Map<String, Object?> json) {
    return YouTubeFeedItem(
      id: json['id']! as String,
      itemType: json['itemType']! as String,
      title: json['title']! as String,
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      videoId: json['videoId'] as String?,
      browseParams: json['browseParams'] as String?,
      artists: (json['artists']! as List<Object?>).cast<String>(),
      album: json['album'] as String?,
      durationSeconds: json['durationSeconds']! as int,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      rank: json['rank'] as int?,
      trend: YouTubeChartTrend.fromProtocol(json['trend'] as String?),
    );
  }

  final String id;
  final String itemType;
  final String title;
  final String? subtitle;
  final String? description;
  final String? videoId;
  final String? browseParams;
  final List<String> artists;
  final String? album;
  final int durationSeconds;
  final String? thumbnailUrl;
  final int? rank;
  final YouTubeChartTrend? trend;

  String get browseIdentity => browseParams == null ? id : '$id:$browseParams';

  bool get isPlayable =>
      const <String>{
        'episode',
        'song',
        'video',
        'non_music_track',
      }.contains(itemType) &&
      videoId != null;
  bool get isVideo => itemType == 'video';
  bool get isPlaylist => itemType == 'playlist';
  bool get isCollection => isPlaylist || itemType == 'album';
  bool get isBrowsable => const <String>{
    'artist',
    'category',
    'channel',
    'podcast',
    'subscriber',
  }.contains(itemType);
  bool get isProfile =>
      const <String>{'artist', 'channel', 'subscriber'}.contains(itemType);
}
