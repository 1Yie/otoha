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
      lyrics: <String>[
        'A quiet room becomes a frequency',
        'Every window holds a different blue',
        'Keep the signal soft enough to stay',
        'Keep the morning close to you',
      ],
    ),
    Track(
      id: 'after-image',
      title: 'After Image',
      artist: 'North Relay',
      album: 'Static Bloom',
      artworkAsset: 'assets/artwork/cover_02.png',
      durationSeconds: 248,
      lyrics: <String>[
        'Your shadow kept the colour of the room',
        'Long after every light had gone',
        'I held the after image still',
        'Until the city moved along',
      ],
    ),
    Track(
      id: 'room-for-light',
      title: 'Room for Light',
      artist: 'Eloise Park',
      album: 'Slow Current',
      artworkAsset: 'assets/artwork/cover_03.png',
      durationSeconds: 205,
      lyrics: <String>[
        'Leave a little room for light',
        'Between the hours and the noise',
        'A steady pulse, a softer line',
        'A place to hear your voice',
      ],
    ),
    Track(
      id: 'side-street',
      title: 'Side Street',
      artist: 'Glass Harbour',
      album: 'Night Geometry',
      artworkAsset: 'assets/artwork/cover_04.png',
      durationSeconds: 219,
      lyrics: <String>[
        'Take the side street home tonight',
        'The quiet one behind the train',
        'The signs are small, the air is clean',
        'And every turn remembers your name',
      ],
    ),
    Track(
      id: 'slow-meridian',
      title: 'Slow Meridian',
      artist: 'June Arcade',
      album: 'Night Geometry',
      artworkAsset: 'assets/artwork/cover_05.png',
      durationSeconds: 261,
      lyrics: <String>[
        'We crossed a slow meridian',
        'Where every hour breathed in time',
        'The night was wide enough for us',
        'The road was almost kind',
      ],
    ),
    Track(
      id: 'clear-weather',
      title: 'Clear Weather',
      artist: 'Pollen Club',
      album: 'Open Windows',
      artworkAsset: 'assets/artwork/cover_06.png',
      durationSeconds: 186,
      lyrics: <String>[
        'Clear weather on the avenue',
        'A little green between the grey',
        'The world is moving quietly',
        'And I can let it stay',
      ],
    ),
    Track(
      id: 'paper-constellations',
      title: 'Paper Constellations',
      artist: 'Small Hours',
      album: 'Open Windows',
      artworkAsset: 'assets/artwork/cover_07.png',
      durationSeconds: 244,
      lyrics: <String>[
        'Paper constellations drift',
        'Across the ceiling after dark',
        'A map of every place we missed',
        'A light for every spark',
      ],
    ),
    Track(
      id: 'still-moving',
      title: 'Still Moving',
      artist: 'Avery Sun',
      album: 'Soft Corners',
      artworkAsset: 'assets/artwork/cover_08.png',
      durationSeconds: 223,
      lyrics: <String>[
        'I am still moving through the day',
        'Even when the room is still',
        'A small horizon in my hands',
        'A quiet kind of will',
      ],
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
