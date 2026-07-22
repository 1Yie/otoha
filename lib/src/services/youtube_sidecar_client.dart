import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'desktop_proxy_environment.dart';

class SidecarEvent {
  const SidecarEvent(this.name, this.data);

  final String name;
  final Map<String, Object?> data;
}

class SidecarFailure {
  const SidecarFailure({
    required this.occurredAt,
    required this.method,
    required this.code,
    required this.errorType,
    this.diagnosticStage,
    this.sourceLocation,
    this.statusCode,
    this.exitCode,
    this.upstreamCode,
  });

  final DateTime occurredAt;
  final String method;
  final String code;
  final String errorType;
  final String? diagnosticStage;
  final String? sourceLocation;
  final int? statusCode;
  final int? exitCode;
  final String? upstreamCode;
}

class SidecarException implements Exception {
  const SidecarException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => '$code: $message';
}

class SidecarBundleLocator {
  const SidecarBundleLocator._();

  static String? findEntryPath({
    required String executablePath,
    required String workingDirectoryPath,
    required Map<String, String> environment,
  }) {
    final override = environment['OTOHA_SIDECAR_ENTRY'];
    if (override != null && File(override).existsSync()) {
      return File(override).absolute.path;
    }

    final executable = File(executablePath);
    final resolvedExecutable = executable.existsSync()
        ? File(executable.resolveSymbolicLinksSync())
        : executable;
    var directory = resolvedExecutable.parent;
    for (var depth = 0; depth < 4; depth += 1) {
      final entry = _existingEntryIn(directory);
      if (entry != null) {
        return entry;
      }
      final resourcesEntry = _existingEntryIn(
        Directory('${directory.path}/Resources'),
      );
      if (resourcesEntry != null) {
        return resourcesEntry;
      }
      directory = directory.parent;
    }

    directory = Directory(workingDirectoryPath).absolute;
    for (var depth = 0; depth < 6; depth += 1) {
      final entry = _existingEntryIn(directory);
      if (entry != null) {
        return entry;
      }
      directory = directory.parent;
    }
    return null;
  }

  static String findNodeExecutable({
    required String entryPath,
    required bool isWindows,
    required Map<String, String> environment,
  }) {
    final override = environment['OTOHA_NODE_EXECUTABLE'];
    if (override != null && File(override).existsSync()) {
      return File(override).absolute.path;
    }

    final sidecarDirectory = File(entryPath).parent.parent;
    final bundleDirectory = sidecarDirectory.parent;
    final candidates = <File>[
      File(
        '${bundleDirectory.path}/node/${isWindows ? 'node.exe' : 'bin/node'}',
      ),
      File('${bundleDirectory.path}/node/bin/node'),
    ];
    for (final candidate in candidates) {
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return 'node';
  }

  static String? _existingEntryIn(Directory directory) {
    final entry = File('${directory.path}/sidecar/src/index.mjs');
    return entry.existsSync() ? entry.path : null;
  }
}

typedef SidecarDebugLogger = void Function(String message);

class YouTubeSidecarClient {
  YouTubeSidecarClient({
    String? executable,
    String? entryPath,
    Map<String, String>? processEnvironment,
    Duration requestTimeout = const Duration(minutes: 2),
    SidecarDebugLogger? debugLogger,
  }) : this._(
         executable,
         entryPath,
         processEnvironment,
         requestTimeout,
         debugLogger,
       );

  YouTubeSidecarClient._(
    this._executable,
    this._entryPath,
    this._processEnvironment,
    this._requestTimeout,
    this._debugLogger,
  );

  final String? _executable;
  final String? _entryPath;
  final Map<String, String>? _processEnvironment;
  final Duration _requestTimeout;
  final SidecarDebugLogger? _debugLogger;
  final StreamController<SidecarEvent> _events =
      StreamController<SidecarEvent>.broadcast();
  final StreamController<SidecarFailure> _failures =
      StreamController<SidecarFailure>.broadcast();
  final Map<String, Completer<Map<String, Object?>>> _pending =
      <String, Completer<Map<String, Object?>>>{};

  final List<SidecarFailure> _recentFailures = <SidecarFailure>[];

  Process? _process;
  Future<void>? _starting;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  int _nextRequestId = 0;
  String _stderr = '';

  Stream<SidecarEvent> get events => _events.stream;
  Stream<SidecarFailure> get failures => _failures.stream;
  List<SidecarFailure> get recentFailures =>
      List<SidecarFailure>.unmodifiable(_recentFailures);

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    final id = '${++_nextRequestId}';
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'Otoha sidecar request: id=$id method=$method '
      'params=${_paramsForLog(params)}',
    );

    try {
      await _ensureStarted();
      final completer = Completer<Map<String, Object?>>();
      _pending[id] = completer;
      _process!.stdin.writeln(
        jsonEncode(<String, Object?>{
          'id': id,
          'method': method,
          'params': params,
        }),
      );
      final result = await completer.future.timeout(_requestTimeout);
      final resultKeys = result.keys.toList(growable: false)..sort();
      _logDebug(
        'Otoha sidecar response: id=$id method=$method status=success '
        'durationMs=${stopwatch.elapsedMilliseconds} '
        'resultKeys=[${resultKeys.join(',')}]',
      );
      return result;
    } on TimeoutException {
      _pending.remove(id);
      _recordFailure(<String, Object?>{
        'method': method,
        'code': 'SIDECAR_TIMEOUT',
        'errorType': 'Timeout',
      });
      _logDebug(
        'Otoha sidecar response: id=$id method=$method status=error '
        'durationMs=${stopwatch.elapsedMilliseconds} '
        'code=SIDECAR_TIMEOUT type=Timeout',
      );
      throw const SidecarException(
        'SIDECAR_TIMEOUT',
        'The YouTube service did not respond in time.',
      );
    } on SidecarException catch (error) {
      _pending.remove(id);
      _logDebug(
        'Otoha sidecar response: id=$id method=$method status=error '
        'durationMs=${stopwatch.elapsedMilliseconds} '
        'code=${error.code} type=SidecarException',
      );
      rethrow;
    } on Object catch (error) {
      _pending.remove(id);
      _logDebug(
        'Otoha sidecar response: id=$id method=$method status=error '
        'durationMs=${stopwatch.elapsedMilliseconds} '
        'code=UNEXPECTED_ERROR type=${error.runtimeType}',
      );
      rethrow;
    }
  }

  void _logDebug(String message) {
    try {
      final logger = _debugLogger;
      if (logger != null) {
        logger(message);
      } else if (kDebugMode) {
        stderr.writeln(message);
      }
    } on Object {
      // Diagnostics must not change the request outcome.
    }
  }

  String _paramsForLog(Map<String, Object?> params) {
    try {
      return jsonEncode(_redactForLog(params));
    } on Object {
      final keys = params.keys.toList(growable: false)..sort();
      return '{keys:[${keys.join(',')}]}';
    }
  }

  Object? _redactForLog(Object? value, [String? key]) {
    if (key != null && _isSensitiveLogKey(key)) {
      return '<redacted>';
    }
    if (value is Map<Object?, Object?>) {
      final redacted = <String, Object?>{};
      for (final entry in value.entries) {
        final entryKey = entry.key;
        if (entryKey is String) {
          redacted[entryKey] = _redactForLog(entry.value, entryKey);
        }
      }
      return redacted;
    }
    if (value is Iterable<Object?>) {
      return value.map((item) => _redactForLog(item)).toList(growable: false);
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return '<${value.runtimeType}>';
  }

  bool _isSensitiveLogKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    return normalized.contains('cookie') ||
        normalized.contains('credential') ||
        normalized.contains('authorization') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        normalized.contains('header') ||
        normalized.contains('url') ||
        normalized == 'text' ||
        normalized.contains('comment') ||
        normalized == 'body' ||
        normalized == 'directory';
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
    await _failures.close();
    await _events.close();
  }

  Future<void> _ensureStarted() async {
    if (_process != null) {
      return;
    }

    final starting = _starting;
    if (starting != null) {
      return starting;
    }

    final start = _start();
    _starting = start;
    try {
      await start;
    } on Object {
      _recordFailure(<String, Object?>{
        'method': 'sidecar.start',
        'code': 'SIDECAR_START_FAILED',
        'errorType': 'ProcessStart',
      });
      rethrow;
    } finally {
      if (identical(_starting, start)) {
        _starting = null;
      }
    }
  }

  Future<void> _start() async {
    final entry = _entryPath ?? _findEntryPath();
    final environment =
        _processEnvironment ??
        await DesktopProxyEnvironment.resolve(
          environment: Platform.environment,
          isLinux: Platform.isLinux,
        );
    final process = await Process.start(
      _executable ??
          SidecarBundleLocator.findNodeExecutable(
            entryPath: entry,
            isWindows: Platform.isWindows,
            environment: Platform.environment,
          ),
      <String>[entry],
      workingDirectory: File(entry).parent.parent.path,
      runInShell: Platform.isWindows,
      environment: environment,
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
        if (event == 'request.failure' ||
            event == 'sidecar.crash' ||
            event == 'sidecar.unhandled_rejection') {
          _recordFailure(data);
        }
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
    _recordFailure(<String, Object?>{
      'method': 'sidecar.process',
      'code': 'SIDECAR_EXIT',
      'errorType': 'ProcessExit',
      'exitCode': exitCode,
    });
    if (!_events.isClosed) {
      _events.add(
        SidecarEvent('sidecar.exit', <String, Object?>{'exitCode': exitCode}),
      );
    }
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

  void _recordFailure(Map<String, Object?> data) {
    final method = _diagnosticValue(data['method']) ?? 'unknown';
    final code = _diagnosticValue(data['code']) ?? 'YOUTUBE_ERROR';
    final errorType = _diagnosticValue(data['errorType']) ?? 'Error';
    final diagnosticStage = _diagnosticValue(data['diagnosticStage']);
    final sourceLocation = _sourceLocation(data['sourceLocation']);
    final upstreamCode = _diagnosticValue(data['upstreamCode']);
    final statusCode = data['statusCode'];
    final exitCode = data['exitCode'];
    final failure = SidecarFailure(
      occurredAt: DateTime.now().toUtc(),
      method: method,
      code: code,
      errorType: errorType,
      diagnosticStage: diagnosticStage,
      sourceLocation: sourceLocation,
      statusCode: statusCode is int && statusCode >= 100 && statusCode <= 599
          ? statusCode
          : null,
      exitCode: exitCode is int ? exitCode : null,
      upstreamCode: upstreamCode,
    );
    if (_recentFailures.length == 32) {
      _recentFailures.removeAt(0);
    }
    _recentFailures.add(failure);
    stderr.writeln(
      'Otoha sidecar failure: method=${failure.method} '
      'code=${failure.code} type=${failure.errorType}'
      '${failure.diagnosticStage == null ? '' : ' stage=${failure.diagnosticStage}'}'
      '${failure.sourceLocation == null ? '' : ' source=${failure.sourceLocation}'}'
      '${failure.statusCode == null ? '' : ' status=${failure.statusCode}'}'
      '${failure.exitCode == null ? '' : ' exit=${failure.exitCode}'}'
      '${failure.upstreamCode == null ? '' : ' upstream=${failure.upstreamCode}'}',
    );
    if (!_failures.isClosed) {
      _failures.add(failure);
    }
  }

  String? _diagnosticValue(Object? value) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  String? _sourceLocation(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^sidecar/src/[A-Za-z0-9_.-]+\.mjs:\d+:\d+$',
        ).hasMatch(value)) {
      return null;
    }
    return value;
  }

  String _findEntryPath() {
    final entry = SidecarBundleLocator.findEntryPath(
      executablePath: Platform.resolvedExecutable,
      workingDirectoryPath: Directory.current.path,
      environment: Platform.environment,
    );
    if (entry != null) {
      return entry;
    }
    throw const SidecarException(
      'SIDECAR_NOT_FOUND',
      'Could not find the bundled YouTube service. Run Otoha from the repository root during development.',
    );
  }
}
