# Mock Catalog Context

## Purpose

- Offline fictional music metadata and bundled artwork for the desktop-shell prototype.

## API Surface

- `Track`
- `MockCatalog.tracks`
- `MockCatalog.search(String)`

## Playback Boundaries

- Simulated time progression only.
- No audio decoding, streaming, downloads, or account state.
- Real YouTube Music metadata is isolated in the YouTube integration subsystem.

## File Paths

- `lib/src/models/catalog.dart`
- `lib/src/data/mock_catalog.dart`
- `assets/artwork/cover_01.png` through `assets/artwork/cover_08.png`
- `lib/src/widgets/artwork_image.dart`

## Commands

- `flutter test test/controllers_test.dart`

## Gotchas

- Keep bundled artwork declared under `flutter.assets` in `pubspec.yaml`.
- Catalog changes must remain compatible with search, queue, lyrics, workspace rows, and player selection.
