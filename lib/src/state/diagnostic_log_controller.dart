import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/diagnostic_log_store.dart';

/// Owns the Settings switch that records sidecar requests to daily log files.
class DiagnosticLogController extends ChangeNotifier {
  DiagnosticLogController({DiagnosticLogStore? store})
    : _store = store ?? DiagnosticLogStore();

  final DiagnosticLogStore _store;
  bool _enabled = false;

  bool get enabled => _enabled;

  Future<void> restore() async {
    _enabled = await _store.readEnabled();
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) {
      return;
    }
    _enabled = value;
    notifyListeners();
    await _store.writeEnabled(value);
  }

  /// Records [message] only while logging is enabled.
  void record(String message) {
    if (!_enabled) {
      return;
    }
    unawaited(_store.append(message));
  }
}
