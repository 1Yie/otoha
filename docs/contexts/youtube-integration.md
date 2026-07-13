# YouTube Integration Context

## Purpose

- Signed-in YouTube Music playlist and track metadata.
- Local Node sidecar boundary for `youtubei.js`.

## API Surface

- `YouTubeLibraryController`
- `YouTubeSidecarClient`
- `CredentialStore`
- `SavedCredential`
- `YouTubePlaylist`
- `YouTubeTrack`
- `YouTubeFeedSection`
- `YouTubeFeedItem`
- `YouTubeService`

## Authentication

- Cookie-header authentication through `Innertube.create({ cookie })`.
- Cookie value stored by `flutter_secure_storage`.
- Active account name and avatar come from `account.getInfo()`.
- Legacy OAuth credentials cleared during restore.
- No credential files in `sidecar/`.

## Process Protocol

- Newline-delimited JSON over stdin/stdout.
- Request fields: `id`, `method`, `params`.
- Response fields: `id`, `ok`, `result` or `error`.
- Event: `auth.credentials`.
- No listening TCP port.

## Methods

- `session.restore`
- `session.status`
- `auth.cookie.signIn`
- `auth.signOut`
- `library.playlists`
- `library.playlist`
- `feed.home`
- `feed.explore`
- `feed.collection`
- `feed.track`
- `feed.browse`
- `search.music`

## File Paths

- `lib/src/models/youtube_library.dart`
- `lib/src/services/credential_store.dart`
- `lib/src/services/youtube_sidecar_client.dart`
- `lib/src/state/youtube_library_controller.dart`
- `lib/src/widgets/account_panel.dart`
- `lib/src/workspaces/youtube_library_workspace.dart`
- `sidecar/src/index.mjs`
- `sidecar/src/youtube_service.mjs`

## Commands

- `npm --prefix sidecar ci`
- `npm --prefix sidecar test`
- `flutter test test/youtube_library_controller_test.dart`

## Gotchas

- Run Otoha from the repository root during development.
- Node.js 20 or newer is required.
- Linux builds require the `libsecret` development package.
- Use a new private browser window when copying the YouTube Cookie header.
- Cookie values are full account credentials and must never be logged or committed.
- Library page tokens must be exhausted.
- Repeated continuation pages must terminate without duplicating the queue.
- Feed songs and one-track releases start simulated playback; multi-track playlists and albums open track lists.
- Artist and mood/genre cards retain their browse ID and parameters for `feed.browse`.
- Artist/channel cards render as circular profiles and open browse results; search excludes non-music entries.
- Explore category selections replace the current Explore sections; podcast episode sections are excluded.
- Horizontal feed sections use section-header arrow controls for desktop scrolling.
- Unknown metadata duration remains unknown; do not substitute a simulated duration.
- Feed-song cards without a duration resolve it through YouTube video metadata before playback.
- Playback remains simulated and performs no stream extraction.
