import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class BaseCampStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> value);
}

/// One durable envelope per local profile; never writes the existing dex.
class SharedPreferencesBaseCampStore implements BaseCampStore {
  SharedPreferencesBaseCampStore({String profile = 'default'})
      : _key = 'baseCamp.v1.$profile' {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(profile)) {
      throw ArgumentError.value(profile, 'profile', 'Invalid local profile');
    }
  }

  final String _key;

  @override
  Future<Map<String, dynamic>?> load() async {
    final preferences = await SharedPreferences.getInstance();
    // A rejected setString still changes the plugin's in-memory cache.
    await preferences.reload();
    final raw = preferences.getString(_key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid base camp envelope');
    }
    return decoded;
  }

  @override
  Future<void> save(Map<String, dynamic> value) async {
    final encoded = jsonEncode(value);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key, encoded)) {
      throw StateError('Could not save base camp');
    }
  }
}
