/// Fixed work role assigned to each species.
enum CampRole { builder, cook, trainer }

/// Facility built by builders or used by cooks and trainers.
enum CampFacility { workshop, kitchen, training }

/// Materials used by construction and camp activities.
enum CampMaterial { wood, stone, ingredient }

/// A recipe unlocked by a kitchen level.
class CampRecipe {
  final String id;
  final int level;
  final int workMs;
  final Map<CampMaterial, int> cost;

  const CampRecipe({
    required this.id,
    required this.level,
    required this.workMs,
    required this.cost,
  });
}

/// A lesson unlocked by a training facility level.
class CampLesson {
  final String id;
  final int level;
  final int workMs;
  final Map<CampMaterial, int> cost;

  const CampLesson({
    required this.id,
    required this.level,
    required this.workMs,
    required this.cost,
  });
}

/// Tunable, app-independent rules for base camp content.
class CampCatalog {
  static const int maxLevel = 3;

  static const Map<String, CampRole> _roles = {
    'road_sprout': CampRole.builder,
    'bridge_hopper': CampRole.builder,
    'mountain_sprite': CampRole.builder,
    'highway_comet': CampRole.builder,
    'puddle_pip': CampRole.cook,
    'river_glider': CampRole.cook,
    'tide_keeper': CampRole.cook,
    'sea_mist': CampRole.cook,
    'lamp_moth': CampRole.trainer,
    'tunnel_moth': CampRole.trainer,
    'star_owl': CampRole.trainer,
    'storm_lantern': CampRole.trainer,
  };

  static CampRole? roleFor(String speciesId) => _roles[speciesId];

  static CampFacility facilityFor(CampRole role) => switch (role) {
        CampRole.builder => CampFacility.workshop,
        CampRole.cook => CampFacility.kitchen,
        CampRole.trainer => CampFacility.training,
      };

  static Map<CampMaterial, int> buildCost(int targetLevel) {
    _checkBuildLevel(targetLevel);
    return Map.unmodifiable({
      CampMaterial.wood: 2 * targetLevel,
      CampMaterial.stone: targetLevel,
    });
  }

  static int buildWorkMs(int targetLevel) {
    _checkBuildLevel(targetLevel);
    return 30000 * targetLevel;
  }

  static int speedMilli(int level) {
    if (level < 0 || level > maxLevel) {
      throw ArgumentError.value(level, 'level', 'must be from 0 to $maxLevel');
    }
    return switch (level) {
      0 || 1 => 1000,
      2 => 1250,
      3 => 1500,
      _ => throw StateError('validated level was not handled'),
    };
  }

  static void _checkBuildLevel(int targetLevel) {
    if (targetLevel < 1 || targetLevel > maxLevel) {
      throw ArgumentError.value(
          targetLevel, 'targetLevel', 'must be from 1 to $maxLevel');
    }
  }

  static const Map<String, CampRecipe> recipes = {
    'berry_snack': CampRecipe(
      id: 'berry_snack',
      level: 1,
      workMs: 30000,
      cost: {CampMaterial.ingredient: 2},
    ),
    'travel_soup': CampRecipe(
      id: 'travel_soup',
      level: 2,
      workMs: 45000,
      cost: {CampMaterial.ingredient: 3},
    ),
    'picnic_feast': CampRecipe(
      id: 'picnic_feast',
      level: 3,
      workMs: 60000,
      cost: {CampMaterial.ingredient: 4},
    ),
  };

  static const Map<String, CampLesson> lessons = {
    'greeting': CampLesson(
      id: 'greeting',
      level: 1,
      workMs: 30000,
      cost: {CampMaterial.wood: 1, CampMaterial.ingredient: 1},
    ),
    'cheer': CampLesson(
      id: 'cheer',
      level: 2,
      workMs: 45000,
      cost: {CampMaterial.wood: 2, CampMaterial.ingredient: 2},
    ),
    'look_around': CampLesson(
      id: 'look_around',
      level: 3,
      workMs: 60000,
      cost: {
        CampMaterial.wood: 2,
        CampMaterial.stone: 1,
        CampMaterial.ingredient: 3,
      },
    ),
  };
}
