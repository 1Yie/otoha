# Otoha Architecture

```text
lib/
├── main.dart                         desktop window bootstrap
└── src/
    ├── app/                          Material app root and theme tokens
    ├── data/                         offline mock catalog
    ├── models/                       catalog and YouTube metadata contracts
    ├── services/                     secure credential/session storage and sidecar client
    ├── state/                        workspace, player, shell, and YouTube controllers
    ├── widgets/                      permanent shell, player, panels, and search palette
    └── workspaces/                   Home, Explore, Library, and Settings content

sidecar/
├── src/index.mjs                     newline-delimited JSON process protocol
└── src/youtube_service.mjs           Cookie-authenticated youtubei.js adapter
```

`OtohaApp` owns long-lived controllers. `DesktopShell` keeps the title bar,
sidebar, player, right panel host, and search palette mounted while only the
workspace region changes. The player persists its simulated queue, selected
track, and position locally; it does not decode or stream media.

The Node sidecar is a child process, not a network server. Flutter persists
the Cookie header in operating-system secure storage and sends it only through
the local NDJSON process boundary. The sidecar provides Library, Home, Explore,
browse, collection, metadata, and search requests backed by `youtubei.js`.
