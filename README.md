<p align="center">
  <img src="assets/icon/icon.png" alt="Otoha application icon" width="128" height="128">
</p>

<h1 align="center">Otoha</h1>

<p align="center">
  A native YouTube Music desktop player built with Flutter.
</p>

<p align="center">
  <a href="https://github.com/1Yie/otoha/actions/workflows/ci-and-release.yml"><img src="https://github.com/1Yie/otoha/actions/workflows/ci-and-release.yml/badge.svg" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/1Yie/otoha" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/Flutter-desktop-02569B?logo=flutter" alt="Flutter desktop">
  <img src="https://img.shields.io/badge/Node.js-20%2B-339933?logo=node.js&logoColor=white" alt="Node.js 20 or newer">
</p>

Otoha is a native Flutter application for Linux, macOS, and Windows. It combines an authenticated YouTube Music library with native audio playback, synchronized lyrics, persistent downloads, and local offline playlists. The application uses a local Node.js sidecar for YouTube.js integration; it is not a web wrapper and does not open a local HTTP port.

> [!IMPORTANT]
> Otoha is an unofficial client and is not affiliated with, sponsored by, or endorsed by YouTube or Google. You are responsible for complying with YouTube's terms and applicable copyright laws when streaming or downloading media.

## Features

- YouTube Music Home, Explore, Library, History, search, playlists, albums, artists, moods, and genres
- Native desktop playback through `media_kit`, including seek, queue, shuffle, repeat, volume, buffering, and output-device selection
- Persistent playback sessions that restore the queue, current track, position, volume, shuffle, and repeat state without storing transient stream URLs
- Timestamped LRCLIB lyrics with playback-following line highlighting and an untimed YouTube Music fallback
- User-initiated audio downloads with persistent local metadata and direct offline playback
- Local offline playlists with rename, cover selection, track management, and deletion confirmation
- English and Simplified Chinese interfaces, including localized remote YouTube Music requests
- Frameless desktop window, system tray background playback, native application icons, and keyboard shortcuts
- Bounded artwork and remote metadata caches, a persistent timed-lyrics cache, and OS-backed secure credential storage

Downloads depend on upstream YouTube format availability and should be considered experimental. YouTube.js or YouTube service changes can temporarily interrupt authenticated metadata, playback, lyrics, or downloads.

## Supported Platforms

| Platform | Status | Release artifact |
| --- | --- | --- |
| Linux | Supported | `.deb` and `.rpm` |
| Windows | Supported | Inno Setup `.exe` |
| macOS | Supported | `.dmg` |
| Android, iOS, Web | Not supported | Generated Flutter runners only |

Tagged releases bundle the production sidecar and a Node.js runtime, so end users do not need to install Node separately. Installers are published on the [GitHub Releases](https://github.com/1Yie/otoha/releases) page when a stable SemVer tag such as `1.0.1` is pushed.

## Requirements

- Flutter stable with Dart `^3.12.2`
- Node.js 20 or newer and npm for source builds
- Linux credential storage development files:
  - Debian or Ubuntu: `libsecret-1-dev`
  - Fedora: `libsecret-devel`

Platform-specific Flutter desktop build dependencies are also required. See the [Flutter desktop documentation](https://docs.flutter.dev/platform-integration/desktop) for the current toolchain requirements.

## Run from Source

```bash
git clone https://github.com/1Yie/otoha.git
cd otoha
flutter pub get
npm --prefix sidecar ci
```

Run Otoha from the repository root so the development build can locate `sidecar/src/index.mjs`:

```bash
# Linux
flutter run -d linux

# macOS
flutter run -d macos

# Windows
flutter run -d windows
```

`OTOHA_SIDECAR_ENTRY` and `OTOHA_NODE_EXECUTABLE` can override sidecar discovery for development and packaging scenarios.

## Authentication

Otoha uses Cookie-header authentication because YouTube Music does not provide a supported public API for this application. The Cookie header is a full account credential.

1. Open a new private or incognito browser window.
2. Sign in to YouTube Music.
3. Open the browser developer tools and inspect a request to `youtube.com` or `music.youtube.com`.
4. Copy the complete `Cookie` request header value.
5. Open the account panel in Otoha and paste the value into the sign-in form.
6. Close the private browser window after authentication succeeds.

Otoha stores the credential only in the operating system credential store. Cookies are never written to sidecar files, application logs, metadata caches, playlist files, or download records. Use a disposable test account when evaluating development builds.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+K` / `Cmd+K` | Open search |
| `Alt+Left` | Go back in workspace history |
| `Alt+Right` | Go forward in workspace history |
| `Space` | Play or pause |
| `Left` | Previous track |
| `Right` | Next track |
| `/` | Cycle repeat mode |
| `Escape` | Close the topmost overlay |

Playback shortcuts do not intercept text fields such as search, Cookie sign-in, or playlist-name inputs.

## Local Data and Privacy

Otoha keeps credential, transient playback, and offline data in separate storage boundaries:

- Cookies are stored by `flutter_secure_storage` in the OS credential store.
- Stream URLs and request headers remain in memory and are never persisted.
- Downloads stream into temporary `.part` files and are atomically completed.
- Download metadata and offline playlists use a dedicated non-credential application-support store.
- Timestamped lyrics use a separate persistent cache; untimed fallback lyrics remain in memory.
- Home, Explore, Library, and playlist metadata use a bounded cache that is cleared on sign-out.
- Search results, comments, Cookies, stream URLs, and headers are not placed in persistent metadata caches.

The sidecar communicates with Flutter through newline-delimited JSON over standard input and output. It does not listen on a TCP port.

## Development

Install dependencies:

```bash
flutter pub get
npm --prefix sidecar ci
```

Generate localization sources after changing either ARB file:

```bash
flutter gen-l10n
```

Format and validate the project:

```bash
dart format lib test
flutter analyze
flutter test
npm --prefix sidecar test
```

Install the sidecar dependencies, then build a release on the matching host
platform:

```bash
npm --prefix sidecar ci
flutter build linux
flutter build macos
flutter build windows
```

The Linux release bundle includes the sidecar, its pinned dependencies, and the
Node.js 20+ runtime used for the build. This keeps Cookie sign-in and playback
resolution working when the bundle is launched outside the source checkout.
The GitHub release workflow adds the same runtime files to the Windows
installer and macOS disk image during their platform-specific packaging steps.

Prepare a version commit and annotated tag from a clean `main` branch:

```bash
# Create the local release commit and tag.
./tool/release/version.sh 1.0.1

# Create and atomically push both the commit and tag.
./tool/release/version.sh 1.0.1 --push
```

The script updates `pubspec.yaml`, automatically increments its build number, creates a `chore(release)` commit, and tags that commit with the version exactly as provided. GitHub Actions runs static analysis, Flutter tests, sidecar tests, and a Linux build on pushes and pull requests. Stable SemVer tags trigger native installer builds for all three desktop platforms and publish a GitHub Release.

## Architecture

```text
lib/
  src/app/          Application root, theme, and localization wiring
  src/models/       Catalog, YouTube Music, and offline-library models
  src/services/     Sidecar, audio, credential, cache, session, and tray services
  src/state/        Workspace, player, account, locale, and offline controllers
  src/widgets/      Persistent shell, player, panels, search, and shared rows
  src/workspaces/   Home, Explore, Library, History, Downloads, and Playlists
sidecar/
  src/              YouTube.js NDJSON service
  test/             Sidecar mapping and protocol tests
test/               Flutter controller and desktop widget tests
tool/release/        Native installer packaging scripts
```

The long-lived desktop shell owns the window frame, navigation, player, queue, panels, and account state. Workspace navigation replaces only the central content region, so playback and remote sessions survive navigation. Remote playback resolves media lazily for the selected queue item, while downloaded tracks open their local files directly.

Additional subsystem notes are available under [`docs/contexts/`](docs/contexts/).

## Contributing

1. Fork the repository and create a focused branch.
2. Keep changes within the existing controller and service boundaries.
3. Add focused controller, widget, or sidecar tests for behavioral changes.
4. Run all validation commands before opening a pull request.
5. Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages.

Do not include Cookies, stream URLs, headers, comment bodies, downloaded media, credential-store exports, or disposable-account data in issues, test fixtures, commits, or logs.

## Acknowledgements

- [Flutter](https://flutter.dev/) for the cross-platform desktop UI toolkit
- [YouTube.js](https://github.com/LuanRT/YouTube.js) for Innertube integration
- [media_kit](https://github.com/media-kit/media-kit) for native audio playback
- [LRCLIB](https://lrclib.net/) for synchronized lyrics

## License

Otoha is available under the [MIT License](LICENSE).
