class LearningCreature {
  const LearningCreature(
      {required this.id, required this.speciesId, required this.name});
  final String id, speciesId, name;
  Map<String, dynamic> toJson() =>
      {'creatureId': id, 'speciesId': speciesId, 'name': name};
}

class LearningScene {
  LearningScene(Map<String, dynamic> json)
      : id = json['id'] as String,
        title = json['title'] as String,
        text = json['text'] as String,
        nextSceneId = json['nextSceneId'] as String?;
  final String id, title, text;
  final String? nextSceneId;
}

class LearningStory {
  LearningStory(Map<String, dynamic> json)
      : speciesId = json['speciesId'] as String,
        id = json['storyId'] as String,
        version = json['version'] as int,
        firstSceneId = json['firstSceneId'] as String,
        scenes = {
          for (final scene in json['scenes'] as List)
            (scene as Map<String, dynamic>)['id'] as String:
                LearningScene(scene)
        },
        migrations =
            Map<String, String>.from(json['migrations'] as Map? ?? {}) {
    if (version < 1 ||
        scenes.isEmpty ||
        scenes.length != (json['scenes'] as List).length ||
        !scenes.containsKey(firstSceneId) ||
        scenes.values.any((s) =>
            s.text.trim().isEmpty ||
            s.text.runes.length > 600 ||
            s.nextSceneId != null && !scenes.containsKey(s.nextSceneId)) ||
        migrations.values.any((id) => !scenes.containsKey(id))) {
      throw const FormatException('Invalid authored learning story');
    }
    final visited = <String>{};
    String? cursor = firstSceneId;
    while (cursor != null) {
      if (!visited.add(cursor)) throw const FormatException('Cyclic story');
      cursor = scenes[cursor]!.nextSceneId;
    }
    if (visited.length != scenes.length) {
      throw const FormatException('Unreachable story scene');
    }
  }
  final String speciesId, id, firstSceneId;
  final int version;
  final Map<String, LearningScene> scenes;
  final Map<String, String> migrations;
}

class LearningCatalog {
  LearningCatalog.fromJson(Map<String, dynamic> json)
      : stories = {
          for (final story in json['stories'] as List)
            (story as Map<String, dynamic>)['speciesId'] as String:
                LearningStory(story)
        } {
    if (json['schemaVersion'] != 1 ||
        stories.length != (json['stories'] as List).length) {
      throw const FormatException('Invalid learning catalog');
    }
  }
  final Map<String, LearningStory> stories;
}
