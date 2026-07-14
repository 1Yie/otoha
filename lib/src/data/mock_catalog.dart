import '../models/catalog.dart';

class MockCatalog {
  const MockCatalog._();

  static const tracks = <Track>[
    Track(
      id: 'soft-signal',
      title: 'Soft Signal',
      artist: 'Marin Vale',
      album: 'Static Bloom',
      artworkAsset: 'assets/artwork/cover_01.png',
      durationSeconds: 232,
      lyrics: <String>[],
    ),
    Track(
      id: 'after-image',
      title: 'After Image',
      artist: 'North Relay',
      album: 'Static Bloom',
      artworkAsset: 'assets/artwork/cover_02.png',
      durationSeconds: 248,
      lyrics: <String>[],
    ),
    Track(
      id: 'room-for-light',
      title: 'Room for Light',
      artist: 'Eloise Park',
      album: 'Slow Current',
      artworkAsset: 'assets/artwork/cover_03.png',
      durationSeconds: 205,
      lyrics: <String>[],
    ),
    Track(
      id: 'side-street',
      title: 'Side Street',
      artist: 'Glass Harbour',
      album: 'Night Geometry',
      artworkAsset: 'assets/artwork/cover_04.png',
      durationSeconds: 219,
      lyrics: <String>[],
    ),
    Track(
      id: 'slow-meridian',
      title: 'Slow Meridian',
      artist: 'June Arcade',
      album: 'Night Geometry',
      artworkAsset: 'assets/artwork/cover_05.png',
      durationSeconds: 261,
      lyrics: <String>[],
    ),
    Track(
      id: 'clear-weather',
      title: 'Clear Weather',
      artist: 'Pollen Club',
      album: 'Open Windows',
      artworkAsset: 'assets/artwork/cover_06.png',
      durationSeconds: 186,
      lyrics: <String>[],
    ),
    Track(
      id: 'paper-constellations',
      title: 'Paper Constellations',
      artist: 'Small Hours',
      album: 'Open Windows',
      artworkAsset: 'assets/artwork/cover_07.png',
      durationSeconds: 244,
      lyrics: <String>[],
    ),
    Track(
      id: 'still-moving',
      title: 'Still Moving',
      artist: 'Avery Sun',
      album: 'Soft Corners',
      artworkAsset: 'assets/artwork/cover_08.png',
      durationSeconds: 223,
      lyrics: <String>[],
    ),
  ];

  static List<Track> search(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return tracks;
    }

    return tracks
        .where((track) {
          return '${track.title} ${track.artist} ${track.album}'
              .toLowerCase()
              .contains(normalizedQuery);
        })
        .toList(growable: false);
  }
}
