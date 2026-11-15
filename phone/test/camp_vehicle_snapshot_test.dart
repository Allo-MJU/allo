import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/camp_vehicle_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

BaseCamp restored(BaseCamp camp) => BaseCamp.fromJson(
      jsonDecode(jsonEncode(camp.toJson())) as Map<String, dynamic>,
    );

void main() {
  test(
    'persisted observed kilometre publishes real material and unique species',
    () {
      final camp = BaseCamp.empty(
        nowMs: 0,
        creatures: [
          CampCreature(id: 'b', speciesId: 'road_sprout'),
          CampCreature(id: 'b2', speciesId: 'road_sprout'),
          CampCreature(id: 'c', speciesId: 'puddle_pip'),
        ],
      );
      camp.recordDrive(sessionId: 'trip', ts: 1, distanceM: 500, atMs: 0);
      camp.recordDrive(sessionId: 'trip', ts: 2, distanceM: 1500, atMs: 0);
      final saved = restored(camp);
      final before = jsonEncode(saved.toJson());
      final fields = campVehicleSnapshot(saved);
      expect(fields['collectionSummary'], {
        'version': 1,
        'wood': 1,
        'stone': 1,
        'ingredient': 1,
        'speciesIds': ['puddle_pip', 'road_sprout'],
        'speciesCount': 2,
      });
      expect(jsonEncode(saved.toJson()), before);
      expect(fields.containsKey('fishing'), isFalse);
      // The returned wire data cannot mutate saved state.
      (fields['collectionSummary'] as Map)['wood'] = 999;
      expect(saved.materials[CampMaterial.wood], 1);
    },
  );

  test(
      'village projection excludes unknown ownership and preserves choice order',
      () {
    final camp = BaseCamp.empty(nowMs: 0, creatures: [
      CampCreature(id: 'a', speciesId: 'road_sprout'),
      CampCreature(id: 'a2', speciesId: 'road_sprout'),
      CampCreature(id: 'b', speciesId: 'tide_keeper'),
    ]);
    final summary = campVehicleSnapshot(camp, villageCreatureIds: [
      'b',
      'missing',
      'a2',
      'a'
    ])['collectionSummary'] as Map;
    expect(summary['villageSpeciesIds'], ['tide_keeper', 'road_sprout']);
    expect(summary['villageSpeciesCount'], 2);
    expect(campVehicleSnapshot(camp)['collectionSummary'],
        isNot(contains('villageSpeciesCount')));
    final empty =
        campVehicleSnapshot(camp, villageCreatureIds: [])['collectionSummary']
            as Map;
    expect(empty['villageSpeciesCount'], 0);
    expect(empty['villageSpeciesIds'], isEmpty);
  });

  test(
    'saved assignments facilities and all concurrent jobs survive projection',
    () {
      final camp = BaseCamp.empty(
        nowMs: 0,
        creatures: [
          CampCreature(id: 'b', speciesId: 'road_sprout'),
          CampCreature(id: 'c', speciesId: 'puddle_pip'),
          CampCreature(id: 't', speciesId: 'lamp_moth'),
          CampCreature(id: 'target', speciesId: 'sea_mist'),
        ],
      );
      camp.assign(CampRole.builder, 'b', atMs: 0);
      camp.assign(CampRole.cook, 'c', atMs: 0);
      camp.assign(CampRole.trainer, 't', atMs: 0);
      camp.recordDrive(sessionId: 'trip', ts: 1, distanceM: 0, atMs: 0);
      camp.recordDrive(sessionId: 'trip', ts: 2, distanceM: 30000, atMs: 0);
      camp.startBuild(
        taskId: 'workshop',
        facility: CampFacility.workshop,
        atMs: 0,
      );
      camp.advanceTo(30000);
      camp.startBuild(
        taskId: 'kitchen',
        facility: CampFacility.kitchen,
        atMs: 30000,
      );
      camp.advanceTo(60000);
      camp.startBuild(
        taskId: 'training',
        facility: CampFacility.training,
        atMs: 60000,
      );
      camp.advanceTo(90000);
      camp.startCooking(taskId: 'meal', recipeId: 'berry_snack', atMs: 90000);
      camp.advanceTo(120000);
      camp.startBuild(
        taskId: 'expand',
        facility: CampFacility.workshop,
        atMs: 120000,
      );
      camp.startCooking(taskId: 'meal2', recipeId: 'berry_snack', atMs: 120000);
      camp.startTraining(
        taskId: 'lesson',
        actionId: 'greeting',
        targetId: 'target',
        atMs: 120000,
      );
      final saved = restored(camp);
      final summary = campVehicleSnapshot(saved)['baseSummary'] as Map;
      expect(summary['builderSpeciesId'], 'road_sprout');
      expect(summary['cookSpeciesId'], 'puddle_pip');
      expect(summary['trainerSpeciesId'], 'lamp_moth');
      expect(summary['structureIds'], ['workshop', 'kitchen', 'training']);
      expect(summary['facilityLevels'], {
        'workshop': 1,
        'kitchen': 1,
        'training': 1,
      });
      expect(summary['activeTaskKinds'], ['building', 'cooking', 'training']);
      expect(summary['activeTaskKind'], isNull);
      expect(summary['foodInventory'], {'berry_snack': 1});
      expect(summary['recipeBook'], {'berry_snack': 1});
      expect(summary.containsKey('lastMealId'), isFalse);
      (summary['foodInventory'] as Map)['berry_snack'] = 99;
      expect(saved.foodInventory['berry_snack'], 1);
    },
  );

  test(
    'empty saved camp exposes real zero rather than invented facilities',
    () {
      final summary = campVehicleSnapshot(restored(BaseCamp.empty(nowMs: 0)));
      expect((summary['collectionSummary'] as Map)['wood'], 0);
      expect((summary['collectionSummary'] as Map)['speciesIds'], isEmpty);
      final base = summary['baseSummary'] as Map;
      expect(base['builderSpeciesId'], isNull);
      expect(base['structureIds'], isEmpty);
      expect(base['activeTaskKinds'], isEmpty);
      expect(base['facilityLevels'], {
        'workshop': 0,
        'kitchen': 0,
        'training': 0,
      });
    },
  );
}
