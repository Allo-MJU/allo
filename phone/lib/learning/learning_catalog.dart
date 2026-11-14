class LearningCreature {
  const LearningCreature(
      {required this.id, required this.speciesId, required this.name});
  final String id, speciesId, name;
  Map<String, dynamic> toJson() =>
      {'creatureId': id, 'speciesId': speciesId, 'name': name};
}

/// Public identifiers only. Dialogue and transitions are owned by the server.
class LearningStory {
  LearningStory(Map<String, dynamic> json)
      : speciesId = json['speciesId'] as String,
        id = json['storyId'] as String,
        version = json['version'] as int,
        firstSceneId = json['firstSceneId'] as String,
        scenes = {
          for (final scene in json['scenes'] as List)
            (scene as Map<String, dynamic>)['id'] as String
        } {
    if (version < 1 ||
        scenes.isEmpty ||
        scenes.length != (json['scenes'] as List).length ||
        !scenes.contains(firstSceneId) ||
        scenes.any((id) => id.isEmpty) ||
        json.keys.any((key) => !{
              'speciesId',
              'storyId',
              'version',
              'name',
              'firstSceneId',
              'scenes'
            }.contains(key)) ||
        (json['scenes'] as List)
            .any((scene) => (scene as Map).keys.any((key) => key != 'id'))) {
      throw const FormatException('Invalid public learning manifest');
    }
  }
  final String speciesId, id, firstSceneId;
  final int version;
  final Set<String> scenes;
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
      throw const FormatException('Invalid learning manifest');
    }
  }
  final Map<String, LearningStory> stories;
}
