import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/services/desktop_proxy_environment.dart';
import 'package:otoha/src/services/youtube_sidecar_client.dart';

void main() {
  test('locates a bundled sidecar and Node next to a Linux executable', () {
    final directory = Directory.systemTemp.createTempSync('otoha-sidecar-test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final executable = File('${directory.path}/otoha');
    executable.createSync();
    final entry = File('${directory.path}/sidecar/src/index.mjs');
    entry.createSync(recursive: true);
    final node = File('${directory.path}/node/bin/node');
    node.createSync(recursive: true);

    final locatedEntry = SidecarBundleLocator.findEntryPath(
      executablePath: executable.path,
      workingDirectoryPath: directory.path,
      environment: const <String, String>{},
    );
    expect(locatedEntry, entry.path);
    expect(
      SidecarBundleLocator.findNodeExecutable(
        entryPath: locatedEntry!,
        isWindows: false,
        environment: const <String, String>{},
      ),
      node.path,
    );
  });

  test('locates a sidecar and Node runtime in macOS resources', () {
    final directory = Directory.systemTemp.createTempSync('otoha-sidecar-test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final executable = File('${directory.path}/Otoha.app/Contents/MacOS/otoha');
    executable.createSync(recursive: true);
    final entry = File(
      '${directory.path}/Otoha.app/Contents/Resources/sidecar/src/index.mjs',
    );
    entry.createSync(recursive: true);
    final node = File(
      '${directory.path}/Otoha.app/Contents/Resources/node/bin/node',
    );
    node.createSync(recursive: true);

    final locatedEntry = SidecarBundleLocator.findEntryPath(
      executablePath: executable.path,
      workingDirectoryPath: directory.path,
      environment: const <String, String>{},
    );
    expect(locatedEntry, entry.path);
    expect(
      SidecarBundleLocator.findNodeExecutable(
        entryPath: locatedEntry!,
        isWindows: false,
        environment: const <String, String>{},
      ),
      node.path,
    );
  });

  test('imports a manual Linux desktop proxy for the sidecar', () async {
    final settings = <String, String>{
      'org.gnome.system.proxy:mode': "'manual'",
      'org.gnome.system.proxy.http:host': "'127.0.0.1'",
      'org.gnome.system.proxy.http:port': '7897',
      'org.gnome.system.proxy.https:host': "'127.0.0.1'",
      'org.gnome.system.proxy.https:port': '7897',
      'org.gnome.system.proxy:use-same-proxy': 'false',
    };

    final environment = await DesktopProxyEnvironment.resolve(
      environment: const <String, String>{},
      isLinux: true,
      readSetting: (schema, key) async => settings['$schema:$key'],
    );

    expect(environment, <String, String>{
      'NODE_USE_ENV_PROXY': '1',
      'HTTP_PROXY': 'http://127.0.0.1:7897',
      'HTTPS_PROXY': 'http://127.0.0.1:7897',
      'NO_PROXY': 'localhost,127.0.0.1,::1',
    });
  });

  test('keeps an explicit proxy ahead of Linux desktop settings', () async {
    var settingsRead = false;

    final environment = await DesktopProxyEnvironment.resolve(
      environment: const <String, String>{
        'https_proxy': 'http://explicit-proxy:8080',
      },
      isLinux: true,
      readSetting: (schema, key) async {
        settingsRead = true;
        return null;
      },
    );

    expect(environment, <String, String>{
      'NODE_USE_ENV_PROXY': '1',
      'HTTPS_PROXY': 'http://explicit-proxy:8080',
    });
    expect(settingsRead, isFalse);
  });

  test('maps ALL_PROXY for Node environment proxy support', () async {
    final environment = await DesktopProxyEnvironment.resolve(
      environment: const <String, String>{'ALL_PROXY': 'http://all-proxy:8080'},
      isLinux: false,
    );

    expect(environment, <String, String>{
      'NODE_USE_ENV_PROXY': '1',
      'HTTP_PROXY': 'http://all-proxy:8080',
      'HTTPS_PROXY': 'http://all-proxy:8080',
    });
  });

  test('routes Flutter HTTP clients through the resolved proxy', () {
    final overrides = DesktopProxyHttpOverrides(const <String, String>{
      'HTTPS_PROXY': 'http://desktop-proxy:8080',
      'NO_PROXY': 'localhost,127.0.0.1',
    });

    expect(
      overrides.findProxy(Uri.parse('https://yt3.ggpht.com/avatar')),
      'PROXY desktop-proxy:8080',
    );
    expect(
      overrides.findProxy(Uri.parse('https://localhost/artwork')),
      'DIRECT',
    );
  });

  test('selects the same proxy for native playback URLs', () {
    const environment = <String, String>{
      'HTTP_PROXY': 'http://http-proxy:8080',
      'HTTPS_PROXY': 'http://https-proxy:8443',
      'NO_PROXY': 'localhost,.internal.example',
    };

    expect(
      DesktopProxyEnvironment.proxyUrlFor(
        Uri.parse('https://rr1.googlevideo.com/videoplayback'),
        environment: environment,
      ),
      'http://https-proxy:8443',
    );
    expect(
      DesktopProxyEnvironment.proxyUrlFor(
        Uri.parse('https://media.internal.example/audio'),
        environment: environment,
      ),
      isNull,
    );
  });

  test('shares one sidecar startup between concurrent requests', () async {
    final client = YouTubeSidecarClient(
      executable: 'node',
      entryPath: File('test/fixtures/sidecar_echo.mjs').absolute.path,
    );
    addTearDown(client.dispose);

    final results = await Future.wait([
      client.call('first'),
      client.call('second'),
    ]);

    expect(results[0]['pid'], isA<int>());
    expect(results[1]['pid'], results[0]['pid']);
  });

  test('records safe sidecar failure diagnostics', () async {
    final client = YouTubeSidecarClient(
      executable: 'node',
      entryPath: File('test/fixtures/sidecar_echo.mjs').absolute.path,
    );
    addTearDown(client.dispose);
    final failure = client.failures.first;

    await expectLater(
      client.call('fail'),
      throwsA(
        isA<SidecarException>().having(
          (error) => error.code,
          'code',
          'YOUTUBE_ERROR',
        ),
      ),
    );

    expect(
      await failure,
      isA<SidecarFailure>()
          .having((error) => error.method, 'method', 'feed.home')
          .having(
            (error) => error.diagnosticStage,
            'diagnostic stage',
            'browse.request',
          )
          .having((error) => error.statusCode, 'status code', 403),
    );
    expect(client.recentFailures, hasLength(1));
  });
}
