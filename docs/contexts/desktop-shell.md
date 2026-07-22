# Desktop Shell Context

## Purpose

- Persistent desktop application frame and local interaction model.

## API Surface

- `main()`
- `OtohaApp extends StatefulWidget`
- `DesktopShell extends StatelessWidget`
- `WorkspaceController`
- `PlayerController`
- `PlayerSessionStore`
- `ShellController`
- `YouTubeLibraryController`
- `DesktopTrayController`

## Permanent Layers

- `DesktopTitleBar`
- `AppSidebar`
- `WorkspaceView`
- `MusicPlayerBar`
- `RightPanelHost`
- `CommentsPanel`
- `AccountPanel`

## File Paths

- `lib/main.dart`
- `lib/src/app/otoha_app.dart`
- `lib/src/app/theme.dart`
- `lib/src/state/desktop_shell_controllers.dart`
- `lib/src/services/player_session_store.dart`
- `lib/src/services/desktop_tray_controller.dart`
- `lib/src/widgets/`
- `lib/src/workspaces/workspace_views.dart`
- `lib/src/workspaces/search_workspace.dart`
- `lib/src/workspaces/youtube_channel_workspace.dart`

## Commands

- `flutter run -d linux`
- `flutter analyze`
- `flutter test`

## Gotchas

- Pump `OtohaApp` in widget tests to avoid native window initialization.
- Workspace navigation must not dispose player state.
- Persisted playback restores queue order, current track, position, and Low/Normal/High online audio quality. A quality-only session remains valid with an empty queue. Playback never restores an expired stream URL, so a resumed YouTube track resolves a fresh stream.
- Production startup has no mock player queue. The player remains empty until a real remote or downloaded track is selected, or a persisted real queue is restored.
- Linux keeps the original secure-storage namespace across the `im.ingstar.otoha` application-ID migration so existing Cookie credentials and player sessions remain readable.
- Respect the reduced-motion setting for nonessential animation.
- Keep the sidecar and account controller alive across workspace navigation.
- On desktop, a successful tray initialization intercepts window close to hide the window while retaining the user-started player session. The tray menu is the only explicit exit path and must destroy the tray before closing the process.
- Search is a workspace history destination opened from the title bar or `Ctrl/Cmd+K`; it is not a modal overlay or permanent sidebar item.
- Search uses signed-in YouTube Music results with server-side type filters. Local mock song, album, and artist grouping remains the signed-out fallback.
- Search-owned collection and browse details return to the same in-memory query and filter.
- The title-bar avatar opens My Channel for a signed-in account and the account panel when signed out. Channel participates in normal Back and Forward workspace history.
- My Channel starts at the workspace top with a responsive profile banner/header. Its authenticated YouTube Music channel-home sections preserve private shelf labels and reuse the established feed queue, collection, artist/channel, and podcast detail interactions.
- Changing online audio quality does not reopen the current stream. `PlayerController` forwards the persisted setting only when the next remote audio or video stream is resolved; local files and downloads are unaffected.
- YouTube-track like/dislike controls are direct player actions; comments load and submit through the right-side panel without interrupting playback.
- Explore moods and genres are top tabs that replace the Explore content beneath them; they are not feed cards.
- Artwork plus discovery/library metadata use bounded caches. Cookies, audio, stream URLs, comments, lyrics, and search results stay out of persistent cache storage.
