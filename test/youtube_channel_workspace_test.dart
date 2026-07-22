import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:otoha/src/app/theme.dart';
import 'package:otoha/src/services/credential_store.dart';
import 'package:otoha/src/services/youtube_sidecar_client.dart';
import 'package:otoha/src/state/desktop_shell_controllers.dart';
import 'package:otoha/src/state/youtube_library_controller.dart';
import 'package:otoha/src/workspaces/youtube_channel_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('channel renders official Recap and runs channel actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _ChannelSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');
    final playerController = PlayerController(const []);
    addTearDown(playerController.dispose);
    Uri? launchedUri;
    String? copiedText;

    await tester.pumpWidget(
      _ChannelTestApp(
        controller: controller,
        playerController: playerController,
        launchExternalUrl: (uri) async {
          launchedUri = uri;
          return true;
        },
        copyText: (text) async => copiedText = text,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-channel-workspace')), findsOneWidget);
    expect(find.text('Test listener'), findsOneWidget);
    expect(find.text('@test-listener'), findsOneWidget);
    expect(find.text('Listen again'), findsOneWidget);
    expect(find.text('Channel song'), findsOneWidget);
    expect(
      find.byKey(const Key('youtube-channel-recap-highlights')),
      findsOneWidget,
    );
    expect(find.text('Your top artist'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('youtube-feed-song-channel-song')));
    await tester.pump();
    expect(playerController.currentTrack?.title, 'Channel song');
    playerController.togglePlaying();
    await tester.pump();

    await tester.tap(find.byKey(const Key('youtube-channel-edit')));
    await tester.pump();
    expect(
      launchedUri,
      Uri.parse('https://studio.youtube.com/channel/UC_TEST/editing'),
    );

    await tester.tap(find.byKey(const Key('youtube-channel-share')));
    await tester.pump();
    expect(copiedText, 'https://www.youtube.com/channel/UC_TEST');
    expect(find.text('Channel link copied.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('youtube-channel-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(controller.isSignedIn, isFalse);
  });

  testWidgets('channel shows the truthful unavailable Recap state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _ChannelSidecarClient(recapAvailable: false);
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(_ChannelTestApp(controller: controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('youtube-channel-recap-unavailable')),
      findsOneWidget,
    );
    expect(
      find.text('YouTube Music has not provided Recap data for this account.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel actions keep a dark surface over banner artwork', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = YouTubeLibraryController(
      client: _ChannelSidecarClient(),
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(_ChannelTestApp(controller: controller));
    await tester.pumpAndSettle();

    final expectedBackground = OtohaColors.canvas.withValues(alpha: 0.88);
    for (final key in <Key>[
      const Key('youtube-channel-edit'),
      const Key('youtube-channel-share'),
    ]) {
      final button = tester.widget<OutlinedButton>(find.byKey(key));
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        expectedBackground,
      );
      expect(
        button.style?.foregroundColor?.resolve(<WidgetState>{}),
        OtohaColors.text,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel scrollbar shares its desktop scroll controller', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(1120, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = YouTubeLibraryController(
      client: _ChannelSidecarClient(),
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(_ChannelTestApp(controller: controller));
    await tester.pumpAndSettle();

    final scrollbar = tester.widget<Scrollbar>(
      find.byKey(const Key('youtube-channel-scrollbar')),
    );
    final scrollView = tester.widget<CustomScrollView>(
      find.byKey(const Key('youtube-channel-workspace')),
    );
    expect(scrollbar.controller, isNotNull);
    expect(scrollbar.controller, same(scrollView.controller));
    expect(scrollbar.controller!.hasClients, isTrue);

    await tester.drag(
      find.byKey(const Key('youtube-channel-workspace')),
      const Offset(0, -320),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('channel failure can retry without affecting account state', (
    tester,
  ) async {
    final client = _ChannelSidecarClient(failFirstChannelRequest: true);
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(_ChannelTestApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-channel-error')), findsOneWidget);
    expect(controller.isSignedIn, isTrue);

    await tester.tap(find.byKey(const Key('youtube-channel-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('youtube-channel-workspace')), findsOneWidget);
    expect(client.channelRequestCount, 2);
  });

  testWidgets('channel opens official collection and browse details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _ChannelSidecarClient();
    final controller = YouTubeLibraryController(
      client: client,
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(_ChannelTestApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('youtube-feed-playlist-channel-playlist')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('youtube-feed-collection-detail')),
      findsOneWidget,
    );
    expect(find.text('Collection track one'), findsOneWidget);

    await tester.tap(find.byKey(const Key('youtube-feed-collection-back')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('youtube-feed-artist-channel-artist')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-feed-browse-detail')), findsOneWidget);
    expect(find.text('Artist essentials'), findsOneWidget);
    expect(
      client.methods,
      containsAll(<String>['feed.collection', 'feed.browse']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel header is top aligned and collapses without a banner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = YouTubeLibraryController(
      client: _ChannelSidecarClient(includeBanner: false),
      credentialStore: _MemoryCredentialStore(),
    );
    addTearDown(controller.dispose);
    await controller.signInWithCookie('SID=test-cookie');

    await tester.pumpWidget(_ChannelTestApp(controller: controller));
    await tester.pumpAndSettle();

    final workspace = tester.getRect(
      find.byKey(const Key('youtube-channel-workspace')),
    );
    final header = tester.getRect(
      find.byKey(const Key('youtube-channel-banner')),
    );
    expect(header.top, workspace.top);
    expect(header.height, 256);
    expect(find.byKey(const Key('youtube-channel-edit')), findsOneWidget);
    expect(find.byKey(const Key('youtube-channel-share')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'channel shows a truthful state when official sections are empty',
    (tester) async {
      final controller = YouTubeLibraryController(
        client: _ChannelSidecarClient(includeContent: false),
        credentialStore: _MemoryCredentialStore(),
      );
      addTearDown(controller.dispose);
      await controller.signInWithCookie('SID=test-cookie');

      await tester.pumpWidget(_ChannelTestApp(controller: controller));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('youtube-channel-content-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Listen again'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ChannelTestApp extends StatefulWidget {
  const _ChannelTestApp({
    required this.controller,
    this.playerController,
    this.launchExternalUrl,
    this.copyText,
  });

  final YouTubeLibraryController controller;
  final PlayerController? playerController;
  final ChannelUrlLauncher? launchExternalUrl;
  final ChannelTextCopier? copyText;

  @override
  State<_ChannelTestApp> createState() => _ChannelTestAppState();
}

class _ChannelTestAppState extends State<_ChannelTestApp> {
  late final PlayerController _playerController =
      widget.playerController ?? PlayerController(const []);
  late final ShellController _shellController = ShellController();

  @override
  void dispose() {
    if (widget.playerController == null) {
      _playerController.dispose();
    }
    _shellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: YouTubeChannelWorkspace(
          controller: widget.controller,
          playerController: _playerController,
          shellController: _shellController,
          launchExternalUrl: widget.launchExternalUrl,
          copyText: widget.copyText,
        ),
      ),
    );
  }
}

class _ChannelSidecarClient extends YouTubeSidecarClient {
  _ChannelSidecarClient({
    this.recapAvailable = true,
    this.failFirstChannelRequest = false,
    this.includeBanner = true,
    this.includeContent = true,
  }) : super(entryPath: 'unused');

  final bool recapAvailable;
  final bool failFirstChannelRequest;
  final bool includeBanner;
  final bool includeContent;
  int channelRequestCount = 0;
  final List<String> methods = <String>[];

  @override
  Stream<SidecarEvent> get events => const Stream<SidecarEvent>.empty();

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    methods.add(method);
    switch (method) {
      case 'auth.cookie.signIn':
        return <String, Object?>{
          'authenticated': true,
          'profile': <String, Object?>{'displayName': 'Test listener'},
        };
      case 'auth.signOut':
        return const <String, Object?>{};
      case 'library.media':
        return const <String, Object?>{
          'playlists': <Object?>[],
          'savedCollections': <Object?>[],
          'podcasts': <Object?>[],
          'albums': <Object?>[],
          'followedArtists': <Object?>[],
        };
      case 'feed.home':
        return const <String, Object?>{
          'filters': <Object?>[],
          'sections': <Object?>[],
          'hasMore': false,
        };
      case 'feed.explore':
        return const <String, Object?>{
          'categories': <Object?>[],
          'sections': <Object?>[],
          'hasMore': false,
        };
      case 'account.channel':
        channelRequestCount += 1;
        if (failFirstChannelRequest && channelRequestCount == 1) {
          throw const SidecarException(
            'CHANNEL_FAILED',
            'Channel loading failed.',
          );
        }
        return _channelResponse(
          recapAvailable: recapAvailable,
          includeBanner: includeBanner,
          includeContent: includeContent,
        );
      case 'feed.collection':
        return const <String, Object?>{
          'tracks': <Object?>[
            <String, Object?>{
              'id': 'collection-track-1',
              'videoId': 'collection-track-1',
              'title': 'Collection track one',
              'artists': <String>['Channel artist'],
              'album': 'Official collection',
              'durationSeconds': 201,
            },
            <String, Object?>{
              'id': 'collection-track-2',
              'videoId': 'collection-track-2',
              'title': 'Collection track two',
              'artists': <String>['Channel artist'],
              'album': 'Official collection',
              'durationSeconds': 202,
            },
          ],
        };
      case 'feed.browse':
        return const <String, Object?>{
          'artist': <String, Object?>{
            'title': 'Channel artist',
            'channelId': 'channel-artist',
          },
          'sections': <Object?>[
            <String, Object?>{
              'title': 'Artist essentials',
              'items': <Object?>[
                <String, Object?>{
                  'id': 'artist-song',
                  'itemType': 'song',
                  'title': 'Artist song',
                  'videoId': 'artist-song',
                  'artists': <String>['Channel artist'],
                  'durationSeconds': 198,
                },
              ],
            },
          ],
        };
      default:
        return const <String, Object?>{};
    }
  }
}

class _MemoryCredentialStore implements CredentialStore {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

Map<String, Object?> _channelResponse({
  required bool recapAvailable,
  required bool includeBanner,
  required bool includeContent,
}) => <String, Object?>{
  'profile': <String, Object?>{
    'displayName': 'Test listener',
    'avatarUrl': 'assets/artwork/cover_01.png',
    'handle': '@test-listener',
    'channelId': 'UC_TEST',
    'subscriberText': '12 subscribers',
    if (includeBanner) 'bannerUrl': 'assets/artwork/cover_02.png',
    'channelUrl': 'https://www.youtube.com/channel/UC_TEST',
    'studioUrl': 'https://studio.youtube.com/channel/UC_TEST/editing',
  },
  'content': <String, Object?>{
    'sections': <Object?>[
      if (includeContent)
        <String, Object?>{
          'title': 'Listen again',
          'subtitle': 'From your official channel home',
          'items': <Object?>[
            <String, Object?>{
              'id': 'channel-song',
              'itemType': 'song',
              'title': 'Channel song',
              'videoId': 'channel-song',
              'artists': <String>['Channel artist'],
              'album': 'Channel album',
              'durationSeconds': 213,
              'thumbnailUrl': 'assets/artwork/cover_04.png',
            },
            <String, Object?>{
              'id': 'channel-playlist',
              'itemType': 'playlist',
              'title': 'Official collection',
              'artists': <String>['Channel artist'],
              'durationSeconds': 0,
              'thumbnailUrl': 'assets/artwork/cover_05.png',
            },
            <String, Object?>{
              'id': 'channel-artist',
              'itemType': 'artist',
              'title': 'Channel artist',
              'artists': <String>[],
              'durationSeconds': 0,
              'thumbnailUrl': 'assets/artwork/cover_06.png',
            },
          ],
        },
    ],
  },
  'recap': <String, Object?>{
    'available': recapAvailable,
    'highlights': recapAvailable
        ? <Object?>[
            <String, Object?>{
              'title': 'Your top artist',
              'strapline': 'This year',
              'description': 'Official YouTube Music Recap data',
              'thumbnailUrl': 'assets/artwork/cover_03.png',
            },
          ]
        : <Object?>[],
    'sections': <Object?>[],
  },
};
