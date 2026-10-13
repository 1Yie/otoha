import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'offline_library_store.dart';

/// Persists the diagnostic logging switch and appends to a per-run log file.
///
/// Each app launch writes to `<Music>/otoha/log/<yyyy-MM-dd_HH-mm-ss>.log`,
/// named by the time that launch first logged. Callers must pass only messages
/// that are already redacted, such as the sidecar request log.
class DiagnosticLogStore {
  DiagnosticLogStore({
    FlutterSecureStorage? storage,
    Future<String> Function()? musicDirectory,
    DateTime Function()? now,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _musicDirectory =
           musicDirectory ?? FileOfflineLibraryStore().musicDirectoryPath,
       _now = now ?? DateTime.now;

  static const _key = 'diagnostics.logEnabled';

  final FlutterSecureStorage _storage;
  final Future<String> Function() _musicDirectory;
  final DateTime Function() _now;
  File? _runFile;

  /// Returns false when the switch was never set or the secure store is
  /// unavailable, so logging stays off unless the user turned it on.
  Future<bool> readEnabled() async {
    try {
      final value = await _storage.read(key: _key);
      return value != null && jsonDecode(value) == true;
    } on Object {
      return false;
    }
  }

  Future<void> writeEnabled(bool enabled) =>
      _storage.write(key: _key, value: jsonEncode(enabled));

  /// Appends [message] as one timestamped line to this run's log file.
  ///
  /// Failures are swallowed on purpose: diagnostics must never change the
  /// outcome of the request being logged.
  Future<void> append(String message) async {
    try {
      final now = _now();
      final file = _runFile ??= await _createRunFile(now);
      await file.writeAsString(
        '${now.toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Best effort only; keep the next attempt free to retry.
      _runFile = null;
    }
  }

  Future<File> _createRunFile(DateTime now) async {
    final music = await _musicDirectory();
    final separator = Platform.pathSeparator;
    final directory = Directory('$music${separator}otoha${separator}log');
    await directory.create(recursive: true);
    return File('${directory.path}$separator${_runStamp(now)}.log');
  }

  static String _runStamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}'
        '_${two(time.hour)}-${two(time.minute)}-${two(time.second)}';
  }
}
