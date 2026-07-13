import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PlayerSessionStore {
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> value);
  Future<void> delete();
}

class SecurePlayerSessionStore implements PlayerSessionStore {
  const SecurePlayerSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'player.session';
  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, Object?>?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) {
      return null;
    }
    return (jsonDecode(value) as Map<Object?, Object?>).cast<String, Object?>();
  }

  @override
  Future<void> write(Map<String, Object?> value) =>
      _storage.write(key: _key, value: jsonEncode(value));

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
