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
- `feed.home.filter`
- `feed.home.more`
- `feed.explore`
- `feed.collection`
- `feed.track`
- `feed.browse`
- `feed.browse.more`
- `interaction.rate`
- `comments.get`
- `comments.create`
- `search.music`
- `lyrics.get`
- `playback.resolve`
- `download.track`

`search.music` accepts `query` plus a required filter value: `all`, `song`,
`album`, `artist`, `playlist`, or `video`. `all` uses the unfiltered
YouTube Music search surface; the other values are forwarded to
`Music.search(query, filter)`. Unsupported values fail with
`INVALID_SEARCH_FILTER`.

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
- Node.js 24 or newer is required so bundled releases support environment proxies.
- Explicit proxy environment variables take precedence. Linux desktop launches
  otherwise import a manual `gsettings` proxy for sidecar, Flutter image, and
  native `media_kit` playback requests.
- Linux builds require the `libsecret` development package.
- Use a new private browser window when copying the YouTube Cookie header.
- Cookie values are full account credentials and must never be logged or committed.
- Library page tokens must be exhausted.
- History uses the authenticated YTMUSIC `FEmusic_history` browse surface, not
  the generic YouTube `FEhistory` watch history. Keep results in memory only.
- Repeated continuation pages must terminate without duplicating the queue.
- Home and Explore retain one in-memory upstream continuation; append normalized sections without duplicating item IDs.
- Home filter labels come from the current localized `HomeFeed.filters`; applying
  one uses `HomeFeed.applyFilter()` and replaces the visible sections while
  retaining the unfiltered feed as the source for subsequent filter changes.
- Explore reads the continuation from its parsed `SectionList` because the current `youtubei.js` parser does not expose an `Explore.getContinuation()` helper. When no continuation is present, keep the finite response rather than repeating cards.
- Feed songs, podcast episodes, and video-capable music entries start in audio
  mode and resolve an ephemeral audio-only URL. The explicit video-mode control
  reopens the same queue item and position with separate adaptive video and
  audio URLs; multi-track playlists and albums open track lists.
- Expanded player lyrics query LRCLIB's cached exact endpoint and title/artist search in parallel, then fall back to LRCLIB's exact external lookup when neither returns timed LRC. If no synchronized result exists, YouTube Music official lyrics are shown without fabricated timing or line-level highlighting.
- LRCLIB lookup sends current track metadata to a third party. Timestamped lyrics may be cached locally by video ID; untimed YouTube Music fallback text stays in memory and is not written to the timestamped lyric cache.
- Artist and mood/genre cards retain their browse ID and parameters for `feed.browse`.
- Artist/channel cards render as circular profiles and open browse results.
- Search retains playable podcast episodes and video-capable music entries.
  Query, active filter, results, and stale-request protection remain in the
  long-lived Flutter controller, while credentials and search results remain
  memory-only.
- Explore category selections are top tabs that replace the current Explore
  sections. Podcast-show cards retain their `MPSP` browse ID and open a
  dedicated show header plus vertical episode list through the authenticated
  YTMUSIC browse surface. `feed.browse.more` appends only episode continuation
  rows and does not reuse recommendation shelves as show content.
- `MusicCarouselShelf.num_items_per_column` is preserved as
  `itemsPerColumn`; values above one render native multi-row compact media
  columns instead of square cover cards.
- Horizontal feed sections use boundary-aware section-header arrow controls,
  aligned final-page offsets, and item-boundary snapping so the first visible
  card is not clipped.
- Unknown metadata duration remains unknown; do not substitute a simulated duration.
- Feed-song cards without a duration resolve it through YouTube video metadata before playback.
- `playback.resolve` is user-initiated. Audio mode returns one in-memory audio
  URL. Explicit video mode returns separately deciphered audio and video URLs;
  selection prefers the highest AVC representation up to 1080p plus the
  original non-DRC audio representation, and libmpv synchronizes both without
  persisting either URL. Live video uses its HLS manifest when available.
- `download.track` is user-initiated and uses the existing authenticated
  Innertube session so it can reuse the already loaded player. It tries
  supported music/audio clients in order and stages a per-track bundle
  containing `audio.<ext>`, `cover.<ext>`, `lyrics.lrc`, and `metadata.json`
  before atomically renaming the directory into place. The bundle never
  persists a URL, Cookie, or request headers. A hidden-to-tray session must not
  trigger downloads, background account activity, or automatic stream
  resolution.
- New default downloads use `Music/otoha/yt_music_download/<videoId>/`.
  Version-1 libraries that still point at the former default Music root migrate
  to this directory; user-selected custom roots and legacy single-file
  downloads remain valid.
- `interaction.rate` and `comments.create` are user-initiated Cookie-authenticated account writes. Flutter and the sidecar enforce one shared two-second cooldown; never submit automatically, log comment bodies, or persist interaction request data.
- Remote artwork and Home, Explore, Library, and playlist metadata may use their bounded cache; clear the metadata cache on sign-out. Local offline downloads, local offline playlist metadata, and timestamped LRC lyrics use separate non-credential stores and remain available after sign-out. Never cache Cookies, stream URLs, headers, comment bodies, or search results.
