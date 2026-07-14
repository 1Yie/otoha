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
- YouTube.js OAuth2 is limited to the TV client and cannot replace Cookie
  authentication for Otoha's YTMUSIC Home, Library, and History requests.
- Otoha does not embed a browser or extract HttpOnly cookies. An invalid or
  expired Cookie is rejected before persistence, and an invalid saved Cookie
  is removed so the user can sign in again.
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
- `history.get`
- `feed.home`
- `feed.home.more`
- `feed.explore`
- `feed.collection`
- `feed.track`
- `feed.browse`
- `interaction.rate`
- `comments.get`
- `comments.create`
- `search.music`
- `lyrics.get`
- `playback.resolve`
- `download.track`

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
- History uses the authenticated YTMUSIC `FEmusic_history` browse surface, not
  the generic YouTube `FEhistory` watch history. Keep results in memory only.
- Repeated continuation pages must terminate without duplicating the queue.
- Home and Explore retain one in-memory upstream continuation; append normalized sections without duplicating item IDs.
- Explore reads the continuation from its parsed `SectionList` because the current `youtubei.js` parser does not expose an `Explore.getContinuation()` helper. When no continuation is present, keep the finite response rather than repeating cards.
- Feed songs and one-track releases resolve an ephemeral audio-only URL and start native playback; multi-track playlists and albums open track lists.
- Expanded player lyrics query LRCLIB's cached exact endpoint and title/artist search in parallel, then fall back to LRCLIB's exact external lookup when neither returns timed LRC. If no synchronized result exists, YouTube Music official lyrics are shown without fabricated timing or line-level highlighting.
- LRCLIB lookup sends current track metadata to a third party. Timestamped lyrics may be cached locally by video ID; untimed YouTube Music fallback text stays in memory and is not written to the timestamped lyric cache.
- Artist and mood/genre cards retain their browse ID and parameters for `feed.browse`.
- Artist/channel cards render as circular profiles and open browse results; search excludes non-music entries.
- Explore category selections are top tabs that replace the current Explore sections; podcast episode sections are excluded.
- Horizontal feed sections use section-header arrow controls for desktop scrolling.
- Unknown metadata duration remains unknown; do not substitute a simulated duration.
- Feed-song cards without a duration resolve it through YouTube video metadata before playback.
- `playback.resolve` is user-initiated and returns only an in-memory audio-only URL. `download.track` is user-initiated and uses the existing authenticated Innertube session so it can reuse the already loaded player. It tries supported music/audio clients in order, streams directly into a temporary file, and atomically completes the local audio file without persisting a URL, Cookie, or headers. A hidden-to-tray session must not trigger downloads, background account activity, or automatic stream resolution.
- `interaction.rate` and `comments.create` are user-initiated Cookie-authenticated account writes. Flutter and the sidecar enforce one shared two-second cooldown; never submit automatically, log comment bodies, or persist interaction request data.
- Remote artwork and Home, Explore, Library, and playlist metadata may use their bounded cache; clear the metadata cache on sign-out. Local offline downloads, local offline playlist metadata, and timestamped LRC lyrics use separate non-credential stores and remain available after sign-out. Never cache Cookies, stream URLs, headers, comment bodies, or search results.
