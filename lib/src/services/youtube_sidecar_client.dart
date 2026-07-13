import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SidecarEvent {
  const SidecarEvent(this.name, this.data);

  final String name;
  final Map<String, Object?> data;
}

class SidecarException implements Exception {
  const SidecarException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => '$code: $message';
}

class YouTubeSidecarClient {
  YouTubeSidecarClient({
    String executable = 'node',
    String? entryPath,
    Duration requestTimeout = const Duration(minutes: 2),
  }) : this._(executable, entryPath, requestTimeout);

  YouTubeSidecarClient._(
    this._executable,
    this._entryPath,
    this._requestTimeout,
  );

  final String _executable;
  final String? _entryPath;
  final Duration _requestTimeout;
  final StreamController<SidecarEvent> _events =
      StreamController<SidecarEvent>.broadcast();
  final Map<String, Completer<Map<String, Object?>>> _pending =
      <String, Completer<Map<String, Object?>>>{};

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  int _nextRequestId = 0;
  String _stderr = '';

  Stream<SidecarEvent> get events => _events.stream;

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    await _ensureStarted();
    final id = '${++_nextRequestId}';
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _process!.stdin.writeln(
      jsonEncode(<String, Object?>{
        'id': id,
        'method': method,
        'params': params,
      }),
    );

    try {
      return await completer.future.timeout(_requestTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw const SidecarException(
        'SIDECAR_TIMEOUT',
        'The YouTube service did not respond in time.',
      );
    }
  }

  Future<void> dispose() async {
    final process = _process;
    _process = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const SidecarException(
            'SIDECAR_CLOSED',
            'The YouTube service was closed.',
          ),
        );
      }
    }
    _pending.clear();
    if (process != null) {
      await process.stdin.close();
      process.kill(ProcessSignal.sigterm);
    }
    await _events.close();
  }

  Future<void> _ensureStarted() async {
    if (_process != null) {
      return;
    }

    final entry = _entryPath ?? _findEntryPath();
    final process = await Process.start(
      _executable,
      <String>[entry],
      workingDirectory: File(entry).parent.parent.path,
      runInShell: Platform.isWindows,
      environment: const <String, String>{'NODE_USE_ENV_PROXY': '1'},
    );
    _process = process;
    _stderr = '';
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _stderrSubscription = process.stderr.transform(utf8.decoder).listen((text) {
      _stderr = '$_stderr$text';
      if (_stderr.length > 4000) {
        _stderr = _stderr.substring(_stderr.length - 4000);
      }
    });
    unawaited(process.exitCode.then(_handleExit));
  }

  void _handleLine(String line) {
    try {
      final message = (jsonDecode(line)! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final event = message['event'];
      if (event is String) {
        final data =
            (message['data'] as Map<Object?, Object?>?)
                ?.cast<String, Object?>() ??
            const <String, Object?>{};
        _events.add(SidecarEvent(event, data));
        return;
      }

      final id = message['id'] as String?;
      final completer = id == null ? null : _pending.remove(id);
      if (completer == null) {
        return;
      }
      if (message['ok'] == true) {
        completer.complete(
          (message['result'] as Map<Object?, Object?>?)
                  ?.cast<String, Object?>() ??
              const <String, Object?>{},
        );
      } else {
        final error = (message['error']! as Map<Object?, Object?>)
            .cast<String, Object?>();
        completer.completeError(
          SidecarException(
            error['code']! as String,
            error['message']! as String,
            error['details'],
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  void _handleExit(int exitCode) {
    if (_process == null) {
      return;
    }
    _process = null;
    final message = _stderr.trim().isEmpty
        ? 'The YouTube service exited with code $exitCode.'
        : _stderr.trim();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(SidecarException('SIDECAR_EXIT', message));
      }
    }
    _pending.clear();
  }

  String _findEntryPath() {
    final override = Platform.environment['OTOHA_SIDECAR_ENTRY'];
    if (override != null && File(override).existsSync()) {
      return File(override).absolute.path;
    }

    Directory cursor = Directory.current.absolute;
    for (var depth = 0; depth < 6; depth += 1) {
      final candidate = File('${cursor.path}/sidecar/src/index.mjs');
      if (candidate.existsSync()) {
        return candidate.path;
      }
      cursor = cursor.parent;
    }
    throw const SidecarException(
      'SIDECAR_NOT_FOUND',
      'Could not find sidecar/src/index.mjs. Run Otoha from the repository root.',
    );
  }
}
