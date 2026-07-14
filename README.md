# Otoha

Otoha is a desktop-first Flutter music player for Linux, macOS, and Windows. It uses a native-feeling persistent shell, local mock playback simulation, and a local YouTube.js sidecar for signed-in YouTube Music metadata and on-demand audio playback.

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

The signed-in YouTube.js session retrieves Home and Explore sections, library playlists, playlist or album tracks, remote artwork, lyrics, comments, and the active account avatar. Home appends real YouTube Music continuation pages while Explore remains limited to its upstream finite response. Explore moods and genres appear as top tabs that replace only the content below them. Ctrl/Cmd+K searches YouTube Music after a short debounce; signed-out use retains local catalog search. A selected YouTube track resolves an ephemeral audio-only URL through the local sidecar and plays it using the native `media_kit` engine; Mock Catalog tracks continue using simulated playback. One-track releases use their retrieved track metadata and play directly; multi-track playlists and albums open a track list. Artist and subscriber cards open browsable selections. The player exposes user-initiated like, dislike, rating removal, and comment submission for YouTube tracks. Account writes share a two-second cooldown and never run in the background. The expanded player first queries LRCLIB's cached catalog with the current title, artist, album, and duration. A matched LRC response drives line-level highlighting from actual playback position; unmatched tracks fall back to YouTube Music's plain lyrics without fabricated timing. Remote artwork and discovery/library metadata use bounded local caches; Cookies, stream URLs, audio, comments, lyrics, and search results are never cached. Podcast episodes and non-music search results are excluded. Missing durations are shown as unknown rather than invented. Restored sessions retain queue and position but never stream URLs; resuming a YouTube track resolves a fresh URL. Otoha does not expose downloads, persist media, run a local media proxy, or use a web view.
