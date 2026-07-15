import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
