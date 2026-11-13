import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StoryStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesStoryStore implements StoryStore {
  SharedPreferencesStoryStore({this.prefix = 'unityApp.story.v1'});
  final String prefix;
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(prefix);
  @override
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(prefix, value)) {
      throw StateError('Story save failed');
    }
  }
}
