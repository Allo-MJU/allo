import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One local value for selection, fishing checkpoints, rewards and receipts.
/// SharedPreferences durability is platform dependent; this is not an fs transaction.
class FishingStore {
  FishingStore({this.profile = 'default'}) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(profile)) {
      throw ArgumentError.value(profile, 'profile', 'Invalid local profile');
    }
  }
  final String profile;
  String get _key => profile == 'default' ? key : 'profile.$profile.$key';

  static const key = 'companion.fishing.profile.v1';

  Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    // A failed setter can update the plugin's memory cache. Read persisted state.
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid fishing profile');
    }
    return decoded;
  }

  Future<void> write(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(profile))) {
      throw StateError('Could not save fishing profile');
    }
  }
}
