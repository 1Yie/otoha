# Otoha Architecture

```text
lib/
├── main.dart                         desktop window bootstrap
└── src/
    ├── app/                          Material app root and theme tokens
    ├── data/                         offline mock catalog
    ├── models/                       catalog and YouTube metadata contracts
    ├── services/                     secure credential/session storage, native audio engine, and sidecar client
    ├── state/                        workspace, player, shell, and YouTube controllers
    ├── widgets/                      permanent shell, player, panels, and search palette
    └── workspaces/                   Home, Explore, Library, and Settings content

sidecar/
├── src/index.mjs                     newline-delimited JSON process protocol
└── src/youtube_service.mjs           Cookie-authenticated youtubei.js adapter
```

`OtohaApp` owns long-lived controllers. `DesktopShell` keeps the title bar,
sidebar, player, right panel host, and search palette mounted while only the
workspace region changes. The player persists its queue, selected
track, and position locally; it never persists a transient media URL.

The Node sidecar is a child process, not a network server. Flutter persists
the Cookie header in operating-system secure storage and sends it only through
the local NDJSON process boundary. The sidecar provides Library, Home, Explore,
browse, collection, metadata, lyrics, search, Home continuation, and explicit
rating/comment requests backed by `youtubei.js`. The native `media_kit` engine
decodes the ephemeral audio-only URL directly without a local proxy. For timed
lyrics, it queries LRCLIB's cached catalog with the
current track metadata and falls back to YouTube Music text when no LRC match
exists. Account mutations occur only after a direct player or comment-panel
action, share a two-second cooldown, and never run in the background.

Remote artwork uses a bounded disk-backed image cache. `RemoteMetadataCache`
stores bounded timestamped JSON for Home, Explore, Library, and playlist views:
fresh data is used immediately and stale data remains visible while the sidecar
refreshes it. Sign-out clears that metadata cache. It never stores Cookie
values, stream URLs, audio bytes, lyrics, comment bodies, or search results.
