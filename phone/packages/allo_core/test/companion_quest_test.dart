import 'package:test/test.dart';
import 'package:allo_core/allo_core.dart';

void main() {
  test('independent cooldown and accepted persistence', () {
    final c = BaseCamp.empty(nowMs: 0, creatures: [
      CampCreature(id: 'a', speciesId: 'one'),
      CampCreature(id: 'b', speciesId: 'one')
    ]);
    final q = CompanionQuest(
        creatureId: 'a',
        questId: 'q',
        kind: CompanionQuestKind.story,
        templateId: 't',
        templateVersion: 1,
        issuedAtMs: 0,
        nextEligibleAtMs: 172800000);
    expect(c.questDue('a', atMs: 0), isTrue);
    expect(c.offerQuest(q, atMs: 0), isTrue);
    expect(c.questDue('b', atMs: 0), isTrue);
    expect(c.acceptQuest('a', 'q', atMs: 1), isTrue);
    final r = BaseCamp.fromJson(c.toJson());
    expect(r.questDue('a', atMs: 172800000), isFalse);
    expect(r.completeStoryQuest('a', 'q', atMs: 172800000), isTrue);
    expect(r.questDue('a', atMs: 172800000), isTrue);
  });
  test('rollover, story confirmation and clock reversal', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'a', speciesId: 'one')]);
    CompanionQuest q(String id, int at) => CompanionQuest(
        creatureId: 'a',
        questId: id,
        kind: CompanionQuestKind.story,
        templateId: 't',
        templateVersion: 1,
        issuedAtMs: at,
        nextEligibleAtMs: at + 172800000);
    c.offerQuest(q('one', 0), atMs: 0);
    expect(c.completeStoryQuest('a', 'one', atMs: 1), isFalse);
    expect(c.offerQuest(q('two', 172800000), atMs: 172800000), isTrue);
    expect(c.acceptQuest('a', 'one', atMs: 172800000), isFalse);
    expect(() => c.questDue('a', atMs: 1), throwsA(isA<CampException>()));
  });
  test('food requires matching accepted quest and inventory', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'a', speciesId: 'one')]);
    final q = CompanionQuest(
        creatureId: 'a',
        questId: 'f',
        kind: CompanionQuestKind.food,
        templateId: 't',
        templateVersion: 1,
        issuedAtMs: 0,
        nextEligibleAtMs: 172800000,
        targetFoodId: 'berry_snack');
    c.offerQuest(q, atMs: 0);
    c.acceptQuest('a', 'f', atMs: 1);
    expect(() => c.feedFood(recipeId: 'berry_snack', creatureId: 'a', atMs: 2),
        throwsA(isA<CampException>()));
    expect(c.quests['a']!.status, CompanionQuestStatus.accepted);
    c.grantCollectionReward('trip', atMs: 2);
    c.feedFood(recipeId: 'berry_snack', creatureId: 'a', atMs: 3);
    expect(c.foodInventory['berry_snack'], 2);
    expect(c.quests['a']!.status, CompanionQuestStatus.completed);
    expect(BaseCamp.fromJson(c.toJson()).quests['a']!.status,
        CompanionQuestStatus.completed);
  });
  test('travel requires exact target, later arrival and same companion', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'a', speciesId: 'one')]);
    c.offerQuest(
        CompanionQuest(
            creatureId: 'a',
            questId: 't',
            kind: CompanionQuestKind.travel,
            templateId: 'x',
            templateVersion: 1,
            issuedAtMs: 0,
            nextEligibleAtMs: 172800000),
        atMs: 0);
    c.acceptQuest('a', 't', atMs: 1, targetPlaceId: 'p');
    bool complete(String place, int arrival, List<String> friends) =>
        c.completeTravelQuest('a', 't',
            atMs: 3,
            placeId: place,
            visitId: 'v',
            arrivedAtMs: arrival,
            companionIds: friends);
    expect(complete('wrong', 2, ['a']), isFalse);
    expect(complete('p', 1, ['a']), isFalse);
    expect(complete('p', 2, ['b']), isFalse);
    expect(complete('p', 2, ['a']), isTrue);
    expect(complete('p', 2, ['a']), isFalse);
    expect(BaseCamp.fromJson(c.toJson()).quests['a']!.completedVisitId, 'v');
    final restored = BaseCamp.fromJson(c.toJson());
    restored.offerQuest(
        CompanionQuest(
            creatureId: 'a',
            questId: 'next',
            kind: CompanionQuestKind.travel,
            templateId: 'x',
            templateVersion: 1,
            issuedAtMs: 172800000,
            nextEligibleAtMs: 345600000),
        atMs: 172800000);
    restored.acceptQuest('a', 'next', atMs: 172800001, targetPlaceId: 'p');
    expect(
        restored.completeTravelQuest('a', 'next',
            atMs: 172800003,
            placeId: 'p',
            visitId: 'v',
            arrivedAtMs: 172800002,
            companionIds: ['a']),
        isFalse);
  });
  test('old snapshots migrate and malformed quest snapshots fail', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'a', speciesId: 'one')]);
    final old = c.toJson()
      ..remove('quests')
      ..remove('questVisitIds');
    expect(BaseCamp.fromJson(old).quests, isEmpty);
    old['quests'] = {
      'a': {'bad': true}
    };
    expect(() => BaseCamp.fromJson(old), throwsA(isA<CampException>()));
  });
  test('untouched friend follows fixed invitation schedule after restart', () {
    final friend = CampCreature(id: 'a', speciesId: 'one');
    final c = BaseCamp.empty(nowMs: 100, creatures: [friend]);
    expect(c.questInvitationAtMs('a', atMs: 100), 100);
    expect(c.questInvitationAtMs('a', atMs: 172800099), 100);
    expect(c.questInvitationAtMs('a', atMs: 172800100), 172800100);
    c.syncCreatures([friend], atMs: 172800101);
    final restored = BaseCamp.fromJson(c.toJson());
    expect(restored.questInvitationAtMs('a', atMs: 345600105), 345600100);
    expect(() => restored.questInvitationAtMs('a', atMs: 100),
        throwsA(isA<CampException>()));
  });
  test('legacy invitation anchor starts at next ownership sync', () {
    final friend = CampCreature(id: 'a', speciesId: 'one');
    final old = BaseCamp.empty(nowMs: 100, creatures: [friend]).toJson()
      ..remove('questInvitationAnchors');
    final restored = BaseCamp.fromJson(old);
    restored.syncCreatures([friend], atMs: 200);
    expect(restored.questInvitationAtMs('a', atMs: 200), 200);
    expect(restored.questInvitationAtMs('a', atMs: 172800200), 172800200);
  });
  test(
      'scheduled offer rolls over at anchor boundary and accepted offer remains',
      () {
    final c = BaseCamp.empty(
        nowMs: 100, creatures: [CampCreature(id: 'a', speciesId: 'one')]);
    CompanionQuest offerAt(int actual, String id) {
      final issued = c.questInvitationAtMs('a', atMs: actual);
      return CompanionQuest(
          creatureId: 'a',
          questId: id,
          kind: CompanionQuestKind.story,
          templateId: 't',
          templateVersion: 1,
          issuedAtMs: issued,
          nextEligibleAtMs: issued + BaseCamp.questIntervalMs);
    }

    expect(c.offerQuest(offerAt(200, 'first'), atMs: 200), isTrue);
    expect(c.questDue('a', atMs: 172800099), isFalse);
    expect(c.offerQuest(offerAt(172800101, 'second'), atMs: 172800101), isTrue);
    expect(c.acceptQuest('a', 'second', atMs: 172800102), isTrue);
    expect(c.questDue('a', atMs: 345600101), isFalse);
    final resumed = BaseCamp.fromJson(c.toJson());
    expect(resumed.questInvitationAtMs('a', atMs: 345600101), 345600100);
    expect(resumed.questDue('a', atMs: 345600101), isFalse);
  });
  test('anchor snapshot rejects unknown creature and future timestamp', () {
    final c = BaseCamp.empty(
        nowMs: 100, creatures: [CampCreature(id: 'a', speciesId: 'one')]);
    final future = c.toJson()..['questInvitationAnchors'] = {'a': 101};
    expect(() => BaseCamp.fromJson(future), throwsA(isA<CampException>()));
    final wrong = c.toJson()..['questInvitationAnchors'] = {'b': 100};
    expect(() => BaseCamp.fromJson(wrong), throwsA(isA<CampException>()));
  });
  test('an expired unaccepted offer cannot be accepted', () {
    final c = BaseCamp.empty(
        nowMs: 0, creatures: [CampCreature(id: 'a', speciesId: 'one')]);
    c.offerQuest(
        CompanionQuest(
            creatureId: 'a',
            questId: 'old',
            kind: CompanionQuestKind.story,
            templateId: 't',
            templateVersion: 1,
            issuedAtMs: 0,
            nextEligibleAtMs: 172800000),
        atMs: 0);
    expect(c.acceptQuest('a', 'old', atMs: 172800000), isFalse);
    expect(c.quests['a']!.status, CompanionQuestStatus.offered);
  });
}
