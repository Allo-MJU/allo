import 'package:allo_core/src/base_camp_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('CampCatalog roles and facilities', () {
    test('assigns each existing species to the requested role', () {
      expect(CampCatalog.roleFor('road_sprout'), CampRole.builder);
      expect(CampCatalog.roleFor('highway_comet'), CampRole.builder);
      expect(CampCatalog.roleFor('puddle_pip'), CampRole.cook);
      expect(CampCatalog.roleFor('sea_mist'), CampRole.cook);
      expect(CampCatalog.roleFor('lamp_moth'), CampRole.trainer);
      expect(CampCatalog.roleFor('storm_lantern'), CampRole.trainer);
      expect(CampCatalog.roleFor('not_a_species'), isNull);
      expect(CampCatalog.facilityFor(CampRole.builder), CampFacility.workshop);
      expect(CampCatalog.facilityFor(CampRole.cook), CampFacility.kitchen);
      expect(CampCatalog.facilityFor(CampRole.trainer), CampFacility.training);
    });
  });

  group('construction progression', () {
    test('scales construction cost, time, and speed by target facility level',
        () {
      expect(CampCatalog.buildCost(1),
          {CampMaterial.wood: 2, CampMaterial.stone: 1});
      expect(CampCatalog.buildCost(3),
          {CampMaterial.wood: 6, CampMaterial.stone: 3});
      expect(CampCatalog.buildWorkMs(1), 30000);
      expect(CampCatalog.buildWorkMs(3), 90000);
      expect(
          [0, 1, 2, 3].map(CampCatalog.speedMilli), [1000, 1000, 1250, 1500]);
    });

    test('rejects levels outside the supported construction range', () {
      for (final level in [-1, 0, 4]) {
        expect(() => CampCatalog.buildCost(level), throwsArgumentError);
        expect(() => CampCatalog.buildWorkMs(level), throwsArgumentError);
      }
      expect(() => CampCatalog.speedMilli(-1), throwsArgumentError);
      expect(() => CampCatalog.speedMilli(4), throwsArgumentError);
    });
  });

  group('recipe and lesson progression', () {
    test(
        'unlocks the matching content at each facility level with specified inputs',
        () {
      expect(CampCatalog.recipes.keys,
          containsAll(['berry_snack', 'travel_soup', 'picnic_feast']));
      expect(CampCatalog.recipes['berry_snack']!.level, 1);
      expect(CampCatalog.recipes['berry_snack']!.cost,
          {CampMaterial.ingredient: 2});
      expect(CampCatalog.recipes['travel_soup']!.level, 2);
      expect(CampCatalog.recipes['travel_soup']!.workMs, 45000);
      expect(CampCatalog.recipes['picnic_feast']!.level, 3);
      expect(CampCatalog.recipes['picnic_feast']!.cost,
          {CampMaterial.ingredient: 4});

      expect(CampCatalog.lessons.keys,
          containsAll(['greeting', 'cheer', 'look_around']));
      expect(CampCatalog.lessons['greeting']!.level, 1);
      expect(CampCatalog.lessons['greeting']!.cost,
          {CampMaterial.wood: 1, CampMaterial.ingredient: 1});
      expect(CampCatalog.lessons['cheer']!.level, 2);
      expect(CampCatalog.lessons['cheer']!.workMs, 45000);
      expect(CampCatalog.lessons['look_around']!.level, 3);
      expect(CampCatalog.lessons['look_around']!.cost, {
        CampMaterial.wood: 2,
        CampMaterial.stone: 1,
        CampMaterial.ingredient: 3
      });
    });

    test('catalog entries and their cost maps cannot be mutated', () {
      expect(() => CampCatalog.recipes.clear(), throwsUnsupportedError);
      expect(() => CampCatalog.lessons.clear(), throwsUnsupportedError);
      expect(
          () => CampCatalog.recipes['berry_snack']!.cost[CampMaterial.wood] = 5,
          throwsUnsupportedError);
    });
  });
}
