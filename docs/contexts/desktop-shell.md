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

## Permanent Layers

- `DesktopTitleBar`
- `AppSidebar`
- `WorkspaceView`
- `MusicPlayerBar`
- `RightPanelHost`
- `SearchPalette`
- `AccountPanel`

## File Paths

- `lib/main.dart`
- `lib/src/app/otoha_app.dart`
- `lib/src/app/theme.dart`
- `lib/src/state/desktop_shell_controllers.dart`
- `lib/src/services/player_session_store.dart`
- `lib/src/widgets/`
- `lib/src/workspaces/workspace_views.dart`

## Commands

- `flutter run -d linux`
- `flutter analyze`
- `flutter test`

## Gotchas

- Pump `OtohaApp` in widget tests to avoid native window initialization.
- Workspace navigation must not dispose player state.
- Persisted playback restores queue order, current track, and position; it does not restore audio output.
- Respect the reduced-motion setting for nonessential animation.
- Keep the sidecar and account controller alive across workspace navigation.
- Search uses signed-in YouTube Music results; local mock search remains the signed-out fallback.
