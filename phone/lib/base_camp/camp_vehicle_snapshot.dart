import 'package:allo_core/allo_core.dart';

/// Read-only display projection of a successfully stored camp snapshot.
/// This neither advances time nor grants rewards. Callers publish only state
/// exposed after BaseCampController has completed its save.
Map<String, dynamic> campVehicleSnapshot(BaseCamp state,
    {List<String>? villageCreatureIds}) {
  // Null means no loaded choice. Count preserves an explicitly empty choice
  // when Realtime Database removes empty arrays from the wire snapshot.
  final villageSpecies = villageCreatureIds
      ?.take(4)
      .map((id) => state.creatures[id]?.speciesId)
      .whereType<String>()
      .toSet()
      .toList();
  final speciesIds = state.creatures.values
      .map((creature) => creature.speciesId)
      .toSet()
      .toList()
    ..sort();
  String? assignedSpecies(CampRole role) =>
      state.creatures[state.assignments[role]]?.speciesId;
  final tasks = [
    for (final role in CampRole.values)
      if (state.jobs.containsKey(role))
        switch (role) {
          CampRole.builder => 'building',
          CampRole.cook => 'cooking',
          CampRole.trainer => 'training',
        },
  ];
  return {
    'collectionSummary': {
      'version': 1,
      'wood': state.materials[CampMaterial.wood]!,
      'stone': state.materials[CampMaterial.stone]!,
      'ingredient': state.materials[CampMaterial.ingredient]!,
      'speciesIds': speciesIds,
      'speciesCount': speciesIds.length,
      if (villageSpecies != null) ...{
        'villageSpeciesIds': villageSpecies,
        'villageSpeciesCount': villageSpecies.length,
      },
    },
    'baseSummary': {
      'builderSpeciesId': assignedSpecies(CampRole.builder),
      'cookSpeciesId': assignedSpecies(CampRole.cook),
      'trainerSpeciesId': assignedSpecies(CampRole.trainer),
      'structureIds': [
        for (final facility in CampFacility.values)
          if (state.facilities[facility]! > 0) facility.name,
      ],
      'facilityLevels': {
        for (final facility in CampFacility.values)
          facility.name: state.facilities[facility]!,
      },
      'activeTaskKinds': tasks,
      // Old displays may use the singular field; never hide parallel jobs there.
      'activeTaskKind': tasks.length == 1 ? tasks.single : null,
      'foodInventory': Map<String, int>.from(state.foodInventory),
      'recipeBook': Map<String, int>.from(state.recipeBook),
    },
  };
}
