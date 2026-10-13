import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otoha/src/services/diagnostic_log_store.dart';

void main() {
  late Directory music;

  setUp(() {
    music = Directory.systemTemp.createTempSync('otoha-log-test-');
  });

  tearDown(() {
    if (music.existsSync()) {
      music.deleteSync(recursive: true);
    }
  });

  DiagnosticLogStore storeAt(DateTime time) => DiagnosticLogStore(
    musicDirectory: () async => music.path,
    now: () => time,
  );

  test('writes each message to one per-run file under otoha/log', () async {
    final store = storeAt(DateTime(2026, 5, 3, 9, 4, 5));

    await store.append('request: id=1 method=first');
    await store.append('response: id=1 status=success');

    final file = File(
      '${music.path}${Platform.pathSeparator}otoha'
      '${Platform.pathSeparator}log${Platform.pathSeparator}'
      '2026-05-03_09-04-05.log',
    );
    expect(file.existsSync(), isTrue);
    final lines = file.readAsLinesSync();
    expect(lines, hasLength(2));
    expect(lines[0], startsWith('2026-05-03T09:04:05'));
    expect(lines[0], endsWith('request: id=1 method=first'));
    expect(lines[1], endsWith('response: id=1 status=success'));
  });

  test('keeps one file for the whole run, even across midnight', () async {
    var now = DateTime(2026, 5, 3, 23, 59);
    final store = DiagnosticLogStore(
      musicDirectory: () async => music.path,
      now: () => now,
    );

    await store.append('late');
    now = DateTime(2026, 5, 4, 0, 1);
    await store.append('after midnight');

    final directory = Directory(
      '${music.path}${Platform.pathSeparator}otoha'
      '${Platform.pathSeparator}log',
    );
    final files = directory.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.readAsLinesSync(), hasLength(2));
  });

  test('swallows write failures so the logged request is unaffected', () async {
    final store = DiagnosticLogStore(
      musicDirectory: () async => '${music.path}/blocked/\u0000invalid',
      now: () => DateTime(2026, 5, 3),
    );

    await expectLater(store.append('still fine'), completes);
  });
}
