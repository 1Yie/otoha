# Repository Guidelines

## Project Overview

`otoha` is a dark-first Flutter desktop music player for Linux, macOS, and Windows. It combines a bundled fictional catalog with simulated playback and signed-in YouTube Music metadata plus on-demand native audio playback. It is not a web wrapper.

## Architecture & Data Flow

- `lib/main.dart` initializes the frameless desktop window through `window_manager` and starts `OtohaApp`.
- `OtohaApp` creates the long-lived workspace, player, shell, and YouTube library controllers. They outlive workspace navigation.
- `DesktopShell` permanently owns the custom title bar, sidebar, workspace region, slide-out panel host, and integrated player.
- `WorkspaceController` stores Home, Explore, Library, and Settings history. Only the workspace switches.
- `PlayerController` owns catalog selection, queue order, shuffle, repeat, volume, and player UI state. Mock tracks use a local simulation; YouTube tracks use `AudioPlaybackEngine` events for position, buffering, completion, and errors. Persisted sessions restore queue, track, and position but never a transient media URL.
- `ShellController` owns search, the active right panel, reduced-motion preference, and mock output-device selection.
- `YouTubeLibraryController` owns authentication state, secure credential persistence, account profile metadata, bounded discovery/library metadata caching, playlist synchronization, selected playlist/feed details, debounced YouTube Music search, lyric state, Home continuation state, and user-initiated rating/comment state.
- `YouTubeSidecarClient` launches `sidecar/src/index.mjs` and exchanges newline-delimited JSON over stdin/stdout; it does not open a local network port. `playback.resolve` returns an ephemeral audio-only URL directly to the native engine.
- The sidecar uses `youtubei.js` Cookie authentication for Home/Explore discovery, library playlist retrieval, Home continuation paging, lyric retrieval, and explicit rating/comment operations.
- Mock `Track` records and local PNG artwork feed all workspace rows, search results, panels, and the player display.

## Key Directories

- `lib/src/app/`: application root and theme tokens.
- `lib/src/data/`, `lib/src/models/`: local catalog and typed music metadata.
- `lib/src/services/`: credential/session storage, bounded artwork/metadata caches, and the local sidecar process client.
- `lib/src/services/audio_playback_engine.dart`: native `media_kit` audio engine and transient stream resolver boundary.
- `lib/src/state/`: focused Flutter `ChangeNotifier` controllers.
- `lib/src/widgets/`: permanent shell layers, title bar, player, and panels.
- `lib/src/workspaces/`: replaceable Home, Search, Explore, Library, and Settings views, including YouTube feed carousels and collection details.
- `assets/artwork/`: eight bundled local album-art PNGs.
- `test/`: controller and desktop-shell widget tests.
- `docs/contexts/`: concise subsystem reference cards.
- `sidecar/`: pinned Node ESM service and Node tests for YouTube.js integration.

## Development Commands

Run commands from the repository root:

- `flutter pub get`: resolve manifest and lockfile dependencies.
- `npm --prefix sidecar ci`: install the pinned YouTube.js sidecar dependencies.
- `dart format lib test`: format Dart source and tests.
- `flutter analyze`: run Dart and Flutter static analysis.
- `flutter test`: run controller and widget tests.
- `npm --prefix sidecar test`: run sidecar mapping and continuation tests.
- `flutter run -d linux`: run the desktop shell on the current Linux host.
- `flutter build linux`, `flutter build macos`, `flutter build windows`: create supported desktop builds on their respective hosts.

## Code Conventions & Common Patterns

- Follow `flutter_lints`, use `const` widgets where possible, private `_` implementation names, and typed immutable model fields.
- Keep shell state in the existing focused controllers. Do not add Provider, BLoC, routing, or dependency-injection packages for this local prototype.
- Keep YouTube.js and account credentials behind the sidecar/service boundary. Never log or put Cookie values in widget state beyond the login input lifetime; persistence belongs only in the OS credential store.
- Do not dispose or recreate player state when changing workspaces. Scope `AnimatedBuilder` and `AnimatedSwitcher` rebuilds to the layer that changed.
- Use `AppMetrics` spacing values and the graphite theme tokens. UI spacing is in 8 px increments; card corners stay at 8 px or below.
- Use Material icons only, add tooltips to icon controls, and respect `ShellController.reduceMotion` for nonessential animation.
- Follow `CLAUDE.md`: make minimal, surgical changes; name assumptions; avoid speculative abstractions; and verify the intended behavior.
- Do not manually edit generated Flutter platform files, plugin registrants, `.metadata`, or ephemeral build configuration.

## Important Files

- `lib/main.dart`: desktop-window bootstrap and application entry point.
- `lib/src/app/otoha_app.dart`: long-lived controller ownership.
- `lib/src/state/desktop_shell_controllers.dart`: navigation, queue/player state, and overlay state.
- `lib/src/widgets/desktop_shell.dart`: permanent four-layer layout and shortcuts.
- `lib/src/widgets/player_bar.dart`: integrated playback controls and buffering/error state.
- `lib/src/state/youtube_library_controller.dart`: account, remote library, and feed-detail state.
- `lib/src/services/youtube_sidecar_client.dart`: NDJSON child-process client.
- `lib/src/services/player_session_store.dart`: persisted queue and player UI session without transient URLs.
- `lib/src/services/remote_metadata_cache.dart`: bounded local JSON cache for Home, Explore, Library, and playlist metadata.
- `lib/src/widgets/account_panel.dart`: Cookie login UI.
- `lib/src/workspaces/youtube_library_workspace.dart`: playlist and track views.
- `sidecar/src/youtube_service.mjs`: YouTube.js authentication and metadata adapter.
- `lib/src/data/mock_catalog.dart`: local music content source.
- `pubspec.yaml`: Dart constraint, desktop plugins, and artwork asset declaration.
- `test/controllers_test.dart`, `test/youtube_library_controller_test.dart`, `test/desktop_shell_test.dart`: focused behavior coverage.

## Runtime/Tooling Preferences

- Dart `^3.12.2`, Flutter stable, Node.js 24 or newer, Pub, and npm are required.
- Run the app from the repository root so the development sidecar can resolve `sidecar/src/index.mjs`. `OTOHA_SIDECAR_ENTRY` can override that path.
- `flutter_secure_storage` uses the OS credential store. Linux builds require `libsecret-1-dev` on Debian/Ubuntu or `libsecret-devel` on Fedora.
- The Flutter process enables Node's environment-proxy support for the sidecar. Standard `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY` variables are inherited; Linux desktop launches otherwise import a manual `gsettings` proxy for sidecar, Flutter image, and native `media_kit` playback requests.
- `window_manager` provides the Linux/macOS/Windows title-bar and window-control integration. Keep window calls outside ordinary widget tests by pumping `OtohaApp`, not `main()`.
- The first milestone is desktop-only. Android, iOS, and web runners remain generated but have no mobile or web layout work.
- YouTube integration uses Cookie login, discovery feeds, playlist metadata, approved on-demand audio-only stream resolution, user-initiated downloads, and user-initiated rating/comment operations. Cookie values, stream URLs, headers, and comment bodies must not be logged, committed, or persisted. Local downloads, offline playlist metadata, and timestamped LRC lyric caches use separate non-credential stores and remain available after sign-out; discovery/library metadata is cleared on sign-out. Do not add a local media proxy, uploads, automated mutations, or background account activity.
- `media_kit` and `media_kit_libs_audio` provide native desktop playback. Keep media URL resolution lazy per selected queue item; retry a playback failure once, then surface an error without advancing simulated progress.
- Android identifiers and release signing remain generated placeholders and are out of scope for the desktop shell.
- Pi has `pi-subagents` available. Use fresh-context `scout` or `context-builder` agents for broad read-only research; the parent agent owns synthesis and project writes.

## Testing & QA

- Run `dart format lib test`, `flutter analyze`, `flutter test`, and `npm --prefix sidecar test` before completion.
- Controller tests cover workspace history, mock simulation, native-engine state transitions, retry behavior, and session restoration.
- Widget tests cover persistent player state during navigation, the command palette, right panels, and user-triggered interaction controls.
- Sidecar tests cover Cookie session mapping, parser shapes, browse/search/lyrics navigation, Home continuation, and account-write throttling without requiring a real account.
- A manual account smoke test must confirm Cookie sign-in, secure restore, playlists, Home continuation, Explore browse cards, collection track lists, ratings, comments, and sign-out against a disposable test account.
- Manually smoke-test each desktop host for frameless-window dragging, minimize/maximize/close controls, keyboard focus, and the `1120 x 720` minimum layout.
- No CI, coverage threshold, or integration framework exists yet. Manually validate authenticated playback, buffering, pause, seek, output-device selection, and expiry retry on Linux, macOS, and Windows before release.

## Module Contexts

- `docs/contexts/desktop-shell.md`: shell layers, controllers, layout, and validation.
- `docs/contexts/mock-catalog.md`: local track contract, artwork assets, and playback boundaries.
- `docs/contexts/youtube-integration.md`: sidecar protocol, authentication, secure storage, and remote library boundaries.
