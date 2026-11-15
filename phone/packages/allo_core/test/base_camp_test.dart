import 'package:test/test.dart';
import 'package:allo_core/src/base_camp.dart';
import 'package:allo_core/src/base_camp_catalog.dart';

void main() {
  test('drive awards only observed kilometers and carries remainder', () {
    final camp = BaseCamp.empty(nowMs: 0);
    expect(camp.recordDrive(sessionId: 's', ts: 1, distanceM: 500, atMs: 0),
        isTrue);
    expect(camp.recordDrive(sessionId: 's', ts: 2, distanceM: 1500, atMs: 0),
        isTrue);
    expect(camp.materials[CampMaterial.wood], 1);
    expect(camp.recordDrive(sessionId: 's', ts: 2, distanceM: 2500, atMs: 0),
        isFalse);
    expect(camp.materials[CampMaterial.wood], 1);
  });
  test('fractional samples accrue equally to a single observed kilometer', () {
    var frequent = BaseCamp.empty(nowMs: 0);
    final single = BaseCamp.empty(nowMs: 0);
    frequent.recordDrive(sessionId: 's', ts: 0, distanceM: 0, atMs: 0);
    single.recordDrive(sessionId: 's', ts: 0, distanceM: 0, atMs: 0);
    for (var i = 1; i <= 2000; i++) {
      frequent.recordDrive(sessionId: 's', ts: i, distanceM: i / 2, atMs: 0);
      if (i == 1001) frequent = BaseCamp.fromJson(frequent.toJson());
    }
    single.recordDrive(sessionId: 's', ts: 1, distanceM: 1000, atMs: 0);
    expect(frequent.materials, single.materials);
    expect(frequent.materials[CampMaterial.wood], 1);
  });
  test('fractional carry survives sessions and baseline excludes gaps', () {
    var c = BaseCamp.empty(nowMs: 0);
    c.recordDrive(sessionId: 'one', ts: 1, distanceM: 0, atMs: 0);
    c.recordDrive(sessionId: 'one', ts: 2, distanceM: 499.5, atMs: 0);
    c = BaseCamp.fromJson(c.toJson());
    c.recordDrive(sessionId: 'two', ts: 1, distanceM: 25.25, atMs: 0);
    c.recordDrive(
        sessionId: 'two',
        ts: 2,
        distanceM: 100.75,
        atMs: 0,
        baselineOnly: true);
    c.recordDrive(sessionId: 'two', ts: 3, distanceM: 601.25, atMs: 0);
    expect(c.materials[CampMaterial.wood], 1);
    c.recordDrive(
        sessionId: 'two',
        ts: 4,
        distanceM: 1200.75,
        atMs: 0,
        baselineOnly: true);
    c.recordDrive(sessionId: 'two', ts: 5, distanceM: 1700.25, atMs: 0);
    expect(c.materials[CampMaterial.wood], 1);
    c.recordDrive(sessionId: 'two', ts: 6, distanceM: 2200.75, atMs: 0);
    expect(c.materials[CampMaterial.wood], 2);
  });
  test('restore validates fixed-unit distance ledger bounds', () {
    final c = BaseCamp.empty(nowMs: 0);
    c.recordDrive(sessionId: 's', ts: 1, distanceM: 0, atMs: 0);
    final badCarry = c.toJson()..['driveCarryMm'] = 1000000;
    expect(() => BaseCamp.fromJson(badCarry), throwsA(isA<CampException>()));
    final badDistance = c.toJson();
    ((badDistance['drives'] as Map)['s'] as Map)['distanceMm'] =
        1000000000000001;
    expect(() => BaseCamp.fromJson(badDistance), throwsA(isA<CampException>()));
  });
  test('activity cooldown and persistent deduplication', () {
    final c = BaseCamp.empty(nowMs: 0);
    expect(c.recordLookOut(eventId: 'a', atMs: 0), isTrue);
    expect(c.recordLookOut(eventId: 'b', atMs: 59999), isFalse);
    expect(c.recordLookOut(eventId: 'b', atMs: 60000), isTrue);
    final restored = BaseCamp.fromJson(c.toJson());
    expect(restored.recordLookOut(eventId: 'a', atMs: 120000), isFalse);
    expect(restored.materials[CampMaterial.stone], 2);
  });
  test('build cost, idempotency, completion and cancellation', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'b', speciesId: 'road_sprout')]);
    c.assign(CampRole.builder, 'b', atMs: 0);
    expect(
        () =>
            c.startBuild(taskId: 'a', facility: CampFacility.workshop, atMs: 0),
        throwsA(isA<CampException>()));
    earn(c, 5);
    c.startBuild(taskId: 'a', facility: CampFacility.workshop, atMs: 0);
    c.startBuild(taskId: 'a', facility: CampFacility.workshop, atMs: 0);
    expect(c.materials[CampMaterial.wood], 3);
    c.cancel(CampRole.builder, atMs: 1000);
    c.cancel(CampRole.builder, atMs: 1000);
    expect(c.materials[CampMaterial.wood], 5);
    expect(
        () => c.startBuild(
            taskId: 'a', facility: CampFacility.workshop, atMs: 1000),
        throwsA(isA<CampException>()));
    c.startBuild(taskId: 'b', facility: CampFacility.workshop, atMs: 1000);
    c.advanceTo(31000);
    expect(c.facilities[CampFacility.workshop], 1);
    expect(c.jobs, isEmpty);
    c.cancel(CampRole.builder, atMs: 31000);
    expect(c.materials[CampMaterial.wood], 3);
  });
  test('parallel jobs reserve workers and persist progression', () {
    final c = readyCamp();
    c.startBuild(
        taskId: 'upgrade', facility: CampFacility.workshop, atMs: 90000);
    c.startCooking(taskId: 'cook', recipeId: 'berry_snack', atMs: 90000);
    c.startTraining(
        taskId: 'train',
        actionId: 'greeting',
        targetId: 'learner',
        atMs: 90000);
    expect(c.jobs.length, 3);
    expect(c.isBusy('learner'), isTrue);
    expect(c.canUseAction('learner', 'greeting'), isFalse);
    expect(() => c.assign(CampRole.builder, null, atMs: 90000),
        throwsA(isA<CampException>()));
    final r = BaseCamp.fromJson(c.toJson());
    c.advanceTo(120000);
    r.advanceTo(120000);
    expect(r.toJson(), c.toJson());
    expect(c.foodInventory['berry_snack'], 1);
    expect(c.recipeBook['berry_snack'], 1);
    expect(c.canUseAction('learner', 'greeting'), isTrue);
    expect(c.jobs.length, 1);
    c.advanceTo(150000);
    expect(c.facilities[CampFacility.workshop], 2);
  });
  test('food buff expiry and refresh survive restore and tick splitting', () {
    final c = readyCamp();
    for (var i = 0; i < 2; i++) {
      c.startCooking(
          taskId: 'food$i', recipeId: 'berry_snack', atMs: 90000 + i * 30000);
      c.advanceTo(120000 + i * 30000);
    }
    c.startBuild(taskId: 'long', facility: CampFacility.workshop, atMs: 150000);
    c.feedFood(recipeId: 'berry_snack', creatureId: 'b', atMs: 150000);
    final r = BaseCamp.fromJson(c.toJson());
    r.advanceTo(160000);
    r.feedFood(recipeId: 'berry_snack', creatureId: 'b', atMs: 160000);
    c.feedFood(recipeId: 'berry_snack', creatureId: 'b', atMs: 160000);
    c.advanceTo(190000);
    r.advanceTo(175000);
    r.advanceTo(190000);
    expect(r.toJson(), c.toJson());
    expect(c.facilities[CampFacility.workshop], 2);
    expect(c.recipeBook['berry_snack'], 2);
    expect(c.foodInventory['berry_snack'], 0);
  });
  test('missing worker cancels and refunds once', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'b', speciesId: 'road_sprout')]);
    earn(c, 5);
    c.assign(CampRole.builder, 'b', atMs: 0);
    c.startBuild(taskId: 'a', facility: CampFacility.workshop, atMs: 0);
    c.syncCreatures([], atMs: 1000);
    expect(c.materials[CampMaterial.wood], 5);
    expect(c.jobs, isEmpty);
    expect(c.assignments, isEmpty);
    c.syncCreatures([], atMs: 1000);
    expect(c.materials[CampMaterial.wood], 5);
  });
  test('resource cap reserves room for an in-flight refund', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'b', speciesId: 'road_sprout')]);
    earn(c, 3);
    c.assign(CampRole.builder, 'b', atMs: 0);
    c.startBuild(taskId: 'a', facility: CampFacility.workshop, atMs: 0);
    final snap = c.toJson();
    (snap['materials'] as Map<String, dynamic>)['wood'] = 999999998;
    (snap['materials'] as Map<String, dynamic>)['stone'] = 999999999;
    (snap['materials'] as Map<String, dynamic>)['ingredient'] = 999999999;
    final restored = BaseCamp.fromJson(snap);
    expect(() => restored.recordLookOut(eventId: 'over', atMs: 0),
        throwsA(isA<CampException>()));
    restored.cancel(CampRole.builder, atMs: 0);
    expect(restored.materials[CampMaterial.wood], 1000000000);
  });
  test('buff expires during work regardless of restart or tick size', () {
    final c = readyCamp();
    c.startCooking(taskId: 'food', recipeId: 'berry_snack', atMs: 90000);
    c.advanceTo(120000);
    c.feedFood(recipeId: 'berry_snack', creatureId: 'b', atMs: 120000);
    c.startBuild(
        taskId: 'upgrade', facility: CampFacility.workshop, atMs: 410000);
    final r = BaseCamp.fromJson(c.toJson());
    c.advanceTo(450000);
    r.advanceTo(420000);
    r.advanceTo(450000);
    expect(c.jobs[CampRole.builder]!.remainingWorkUnits, 15000000);
    expect(r.toJson(), c.toJson());
    c.advanceTo(465000);
    expect(c.facilities[CampFacility.workshop], 2);
  });
  test('drive high water, baseline and carry persist across sessions', () {
    var c = BaseCamp.empty(nowMs: 0);
    expect(c.recordDrive(sessionId: 'one', ts: 1, distanceM: 100, atMs: 0),
        isTrue);
    c.recordDrive(sessionId: 'one', ts: 2, distanceM: 700, atMs: 0);
    expect(c.recordDrive(sessionId: 'one', ts: 2, distanceM: 2000, atMs: 0),
        isFalse);
    c.recordDrive(sessionId: 'one', ts: 3, distanceM: 500, atMs: 0);
    c.recordDrive(
        sessionId: 'one', ts: 4, distanceM: 1200, atMs: 0, baselineOnly: true);
    c = BaseCamp.fromJson(c.toJson());
    c.recordDrive(sessionId: 'two', ts: 1, distanceM: 50, atMs: 0);
    c.recordDrive(sessionId: 'two', ts: 2, distanceM: 450, atMs: 0);
    expect(c.materials[CampMaterial.wood], 1);
    c.recordDrive(sessionId: 'one', ts: 5, distanceM: 1300, atMs: 0);
    expect(c.materials[CampMaterial.wood], 1);
  });
  test('upgrades unlock level three content', () {
    final c = readyCamp();
    c.startBuild(taskId: 'w2', facility: CampFacility.workshop, atMs: 90000);
    c.advanceTo(150000);
    c.startBuild(taskId: 'k2', facility: CampFacility.kitchen, atMs: 150000);
    c.advanceTo(198000);
    c.startBuild(taskId: 'k3', facility: CampFacility.kitchen, atMs: 198000);
    c.advanceTo(270000);
    expect(c.facilities[CampFacility.kitchen], 3);
    c.startCooking(taskId: 'feast', recipeId: 'picnic_feast', atMs: 270000);
    c.advanceTo(309999);
    expect(c.foodInventory['picnic_feast'], isNull);
    c.advanceTo(310000);
    expect(c.foodInventory['picnic_feast'], 1);
    expect(c.recipeBook['picnic_feast'], 1);
    expect(
        () => c.startBuild(
            taskId: 'k4', facility: CampFacility.kitchen, atMs: 310000),
        throwsA(isA<CampException>()));
  });
  test('facility upgrade does not change an in-flight cooking rate', () {
    final c = readyCamp();
    c.startBuild(taskId: 'k2', facility: CampFacility.kitchen, atMs: 90000);
    c.startCooking(taskId: 'cook', recipeId: 'berry_snack', atMs: 130000);
    c.advanceTo(150000);
    expect(c.facilities[CampFacility.kitchen], 2);
    expect(c.jobs[CampRole.cook]!.remainingWorkUnits, 10000000);
    c.advanceTo(160000);
    expect(c.foodInventory['berry_snack'], 1);
  });
  test('training rejects reserved target and preserves resources', () {
    final c = readyCamp();
    c.startCooking(taskId: 'cook', recipeId: 'berry_snack', atMs: 90000);
    final before = Map<CampMaterial, int>.of(c.materials);
    expect(
        () => c.startTraining(
            taskId: 'bad', actionId: 'greeting', targetId: 'c', atMs: 90000),
        throwsA(isA<CampException>()));
    expect(c.materials, before);
    expect(c.jobs.length, 1);
  });
  test('restore rejects invalid nested references and conflicting reservations',
      () {
    final c = readyCamp();
    c.startCooking(taskId: 'cook', recipeId: 'berry_snack', atMs: 90000);
    c.startTraining(
        taskId: 'train',
        actionId: 'greeting',
        targetId: 'learner',
        atMs: 90000);
    final snapshot = c.toJson();
    final jobs = snapshot['jobs'] as List;
    (jobs[1] as Map<String, dynamic>)['targetId'] = 'c';
    expect(() => BaseCamp.fromJson(snapshot), throwsA(isA<CampException>()));
    final bad = c.toJson();
    (bad['materials'] as Map<String, dynamic>)['wood'] = -1;
    expect(() => BaseCamp.fromJson(bad), throwsA(isA<CampException>()));
  });
  test('restore rejects impossible food counts and job speeds', () {
    final c = readyCamp();
    c.startCooking(taskId: 'cook', recipeId: 'berry_snack', atMs: 90000);
    final snapshot = c.toJson();
    (snapshot['jobs'] as List).first['speedMilli'] = 1500;
    expect(() => BaseCamp.fromJson(snapshot), throwsA(isA<CampException>()));
    final bad = c.toJson();
    (bad['foodInventory'] as Map<String, int>)['berry_snack'] = 2;
    expect(() => BaseCamp.fromJson(bad), throwsA(isA<CampException>()));
  });
  test('clock rollback, malformed snapshots and read only views', () {
    final c = BaseCamp.empty(
        nowMs: 10,
        creatures: [CampCreature(id: 'b', speciesId: 'road_sprout')]);
    c.advanceTo(0);
    expect(c.nowMs, 10);
    expect(() => c.assign(CampRole.builder, 'b', atMs: 9),
        throwsA(isA<CampException>()));
    expect(() => c.materials[CampMaterial.wood] = 999, throwsUnsupportedError);
    final snapshot = c.toJson();
    snapshot['version'] = 2;
    expect(() => BaseCamp.fromJson(snapshot), throwsA(isA<CampException>()));
  });
  test('collection reward persists and is idempotent per trip', () {
    final camp = BaseCamp.empty(nowMs: 0);
    expect(camp.grantCollectionReward('trip-a', atMs: 0), isTrue);
    final restored = BaseCamp.fromJson(camp.toJson());
    expect(restored.grantCollectionReward('trip-a', atMs: 0), isFalse);
    expect(restored.grantCollectionReward('trip-b', atMs: 0), isTrue);
    expect(restored.foodInventory['berry_snack'], 6);
  });
}

void earn(BaseCamp c, int count) {
  c.recordDrive(sessionId: 'earn', ts: 0, distanceM: 0, atMs: c.nowMs);
  c.recordDrive(
      sessionId: 'earn', ts: 1, distanceM: count * 1000.0, atMs: c.nowMs);
}

BaseCamp readyCamp() {
  final c = BaseCamp.empty(nowMs: 0, creatures: [
    CampCreature(id: 'b', speciesId: 'road_sprout'),
    CampCreature(id: 'c', speciesId: 'puddle_pip'),
    CampCreature(id: 't', speciesId: 'lamp_moth'),
    CampCreature(id: 'learner', speciesId: 'unknown')
  ]);
  earn(c, 30);
  c.assign(CampRole.builder, 'b', atMs: 0);
  c.assign(CampRole.cook, 'c', atMs: 0);
  c.assign(CampRole.trainer, 't', atMs: 0);
  c.startBuild(taskId: 'ws', facility: CampFacility.workshop, atMs: 0);
  c.advanceTo(30000);
  c.startBuild(taskId: 'k', facility: CampFacility.kitchen, atMs: 30000);
  c.advanceTo(60000);
  c.startBuild(taskId: 't', facility: CampFacility.training, atMs: 60000);
  c.advanceTo(90000);
  return c;
}
