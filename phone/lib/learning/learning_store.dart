import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class LearningStore {
  Future<Map<String, dynamic>?> read(String profile, String creatureId);
  Future<void> write(
      String profile, String creatureId, Map<String, dynamic> value);
}

/// Only authored progress and frequency counters cross this storage boundary.
class PreferencesLearningStore implements LearningStore {
  String _key(String profile, String creatureId) =>
      'companionLearning.v1.${base64Url.encode(utf8.encode(profile))}.${base64Url.encode(utf8.encode(creatureId))}';
  @override
  Future<Map<String, dynamic>?> read(String profile, String creatureId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final raw = preferences.getString(_key(profile, creatureId));
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid learning progress');
    }
    return value;
  }

  @override
  Future<void> write(
      String profile, String creatureId, Map<String, dynamic> value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(
        _key(profile, creatureId), jsonEncode(value))) {
      throw StateError('Could not save learning progress');
    }
  }
}
