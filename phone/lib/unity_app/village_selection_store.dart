import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class VillageSelectionStore {
  /// Null is a legacy profile with no choice; an empty list is an explicit choice.
  Future<List<String>?> read(String profile);
  Future<void> write(String profile, List<String> creatureIds);
}

class PreferencesVillageSelectionStore implements VillageSelectionStore {
  String _key(String profile) =>
      'villageFriends.v1.${base64Url.encode(utf8.encode(profile))}';

  static List<String> _validated(Object? value) {
    if (value is! List ||
        value.length > 4 ||
        value.any(
            (id) => id is! String || id.trim().isEmpty || id.length > 256) ||
        value.toSet().length != value.length) {
      throw const FormatException('Invalid village friends');
    }
    return List<String>.from(value);
  }

  @override
  Future<List<String>?> read(String profile) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final raw = preferences.getString(_key(profile));
    return raw == null ? null : _validated(jsonDecode(raw));
  }

  @override
  Future<void> write(String profile, List<String> creatureIds) async {
    final ids = _validated(creatureIds);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key(profile), jsonEncode(ids))) {
      throw StateError('Could not save village friends');
    }
  }
}
