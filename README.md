# Otoha

Otoha is a desktop-first Flutter music player for Linux, macOS, and Windows. It uses a native-feeling persistent shell, simulated playback, and a local YouTube.js sidecar for signed-in YouTube Music metadata.

## Prerequisites

- Flutter stable with Dart `^3.12.2`
- Node.js 20 or newer with npm
- Linux: `libsecret-1-dev` on Debian/Ubuntu or `libsecret-devel` on Fedora

## Setup

```bash
flutter pub get
npm --prefix sidecar ci
```

Run the app from the repository root so it can locate the development sidecar:

```bash
flutter run -d linux
```

Use the profile control in the title bar to provide a complete YouTube `Cookie` request header. YouTube.js recommends Cookie authentication for most web client types. To obtain the header, use a new private browser window, sign in to YouTube, copy the `Cookie` header from a `youtube.com` network request, then close that private window. Otoha stores the value in the operating system credential store and never writes it to sidecar files or logs.

## Validation

```bash
dart format lib test
flutter analyze
flutter test
npm --prefix sidecar test
```

The signed-in YouTube.js session retrieves Home and Explore sections, library playlists, playlist or album tracks, remote artwork, and the active account avatar. Ctrl/Cmd+K searches YouTube Music after a short debounce; signed-out use retains local catalog search. Songs start the local simulated queue immediately. One-track releases use their retrieved track metadata and play directly; multi-track playlists and albums open a track list. Artist and subscriber cards open browsable selections. Explore mood/genre cards replace the current Explore sections in place. Podcast episodes and non-music search results are excluded. Missing durations are shown as unknown rather than invented. The local simulated queue, selected track, and position resume after restart. There is no audio streaming, download, web view, or media decoding implementation.
