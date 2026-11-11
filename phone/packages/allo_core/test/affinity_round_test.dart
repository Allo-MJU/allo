import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

void main() {
  test('positive speech earns twelve points over sixty seconds', () {
    final round = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    expect(
        round.speak(
            atMs: 0, requestId: 'a', sentiment: SpeechSentiment.positive),
        EggFeedback.positive);
    round.advanceTo(30000);
    expect(round.scoreMilli, 6000);
    round.advanceTo(60000);
    expect(round.scoreMilli, 12000);
  });
  test(
      'cooldowns are independent and stale or duplicate input does not reset them',
      () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    expect(r.speak(atMs: 0, requestId: 'x', sentiment: SpeechSentiment.neutral),
        EggFeedback.neutral);
    expect(r.pet(atMs: 0), EggFeedback.positive);
    expect(r.pet(atMs: 1), EggFeedback.vibration);
    expect(
        r.speak(atMs: 500, requestId: 'x', sentiment: SpeechSentiment.negative),
        EggFeedback.none);
    expect(
        r.speak(atMs: 499, requestId: 'y', sentiment: SpeechSentiment.positive),
        EggFeedback.none);
    expect(r.scoreMilli, 3000);
    expect(r.speechRemainingMs, 179501);
  });
  test('wrong and same placements preserve target and respect cooldown', () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    expect(
        r.place(atMs: 0, zone: 0, nextPreferredZone: 2), EggFeedback.vibration);
    expect(
        r.place(atMs: 0, zone: 2, nextPreferredZone: 3), EggFeedback.vibration);
    expect(r.currentZone, 2);
    expect(r.preferredZone, 1);
    expect(
        r.place(atMs: 1, zone: 1, nextPreferredZone: 3), EggFeedback.vibration);
    expect(
        r.place(atMs: 15000, zone: 1, nextPreferredZone: 1), EggFeedback.none);
    expect(r.place(atMs: 15000, zone: 1, nextPreferredZone: 3),
        EggFeedback.positive);
    expect(r.scoreMilli, 7000);
    expect(r.preferredZone, 3);
  });
  test('first milestone cancels overflow and photo is accepted once', () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    for (var i = 0; i < 16; i++) {
      r.pet(atMs: i * 10000);
    }
    expect(r.scoreMilli, 48000);
    expect(r.pet(atMs: 160000), EggFeedback.photoRequired);
    expect(r.scoreMilli, 50000);
    expect(r.pet(atMs: 170000), EggFeedback.none);
    expect(r.confirmPhoto(atMs: 170000, eggId: 'wrong', photoId: 'p'),
        EggFeedback.none);
    expect(r.confirmPhoto(atMs: 170001, eggId: 'egg', photoId: 'p'),
        EggFeedback.positive);
    expect(r.confirmPhoto(atMs: 170002, eggId: 'egg', photoId: 'p'),
        EggFeedback.none);
    expect(r.scoreMilli, 65000);
    r.speak(
        atMs: 180000, requestId: 'neg', sentiment: SpeechSentiment.negative);
    expect(r.scoreMilli, 53000);
    r.speak(
        atMs: 360000, requestId: 'neg2', sentiment: SpeechSentiment.negative);
    expect(r.scoreMilli, 41000);
    expect(r.phase, AffinityPhase.incubating);
  });
  test('mid-ramp snapshots restore exact incremental credit', () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    r.speak(atMs: 0, requestId: 'x', sentiment: SpeechSentiment.positive);
    r.advanceTo(12347);
    final restored = AffinityRound.fromJson(r.toJson());
    restored.advanceTo(60000);
    expect(restored.scoreMilli, 12000);
    expect(
        restored.speak(
            atMs: 180000, requestId: 'x', sentiment: SpeechSentiment.negative),
        EggFeedback.none);
  });
  test('long advance cannot invent more than twelve points of speech', () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    r.speak(atMs: 0, requestId: 'x', sentiment: SpeechSentiment.positive);
    r.advanceTo(500000);
    expect(r.scoreMilli, 12000);
    expect(r.phase, AffinityPhase.incubating);
  });
  test('deadline wins at equality and rejects late photo', () {
    final r =
        AffinityRound.start(eggId: 'egg', preferredZone: 1, deadlineMs: 160000);
    for (var i = 0; i < 16; i++) {
      r.pet(atMs: i * 10000);
    }
    expect(r.pet(atMs: 160000), EggFeedback.fled);
    expect(r.phase, AffinityPhase.failed);
    expect(r.confirmPhoto(atMs: 170000, eggId: 'egg', photoId: 'p'),
        EggFeedback.none);
  });
  test('late passive tick hatches before deadline but tie fails', () {
    AffinityRound setup(int deadline) {
      final r = AffinityRound.start(
          eggId: 'egg', preferredZone: 1, deadlineMs: deadline);
      for (var i = 0; i < 17; i++) {
        r.pet(atMs: i * 10000);
      }
      r.confirmPhoto(atMs: 160001, eggId: 'egg', photoId: 'p');
      for (var i = 17; i < 25; i++) {
        r.pet(atMs: i * 10000);
      }
      r.speak(
          atMs: 240000, requestId: 'x', sentiment: SpeechSentiment.positive);
      return r;
    }

    final earlier = setup(295001);
    expect(earlier.advanceTo(400000), EggFeedback.hatched);
    expect(earlier.hatchedAtMs, 295000);
    expect(earlier.pet(atMs: 500000), EggFeedback.none);
    final tie = setup(295000);
    expect(tie.advanceTo(400000), EggFeedback.fled);
    expect(tie.phase, AffinityPhase.failed);
  });
  test('malformed and inconsistent snapshots are rejected', () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    for (final mutation in <String, dynamic>{
      'version': 2,
      'scoreMilli': double.nan,
      'phase': 'hatched',
      'requestIds': [' ', 'x']
    }.entries) {
      final json = r.toJson()..[mutation.key] = mutation.value;
      expect(() => AffinityRound.fromJson(json), throwsFormatException);
    }
  });
  test('speech reaches first milestone at fifty and discards remaining ramp',
      () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    for (var i = 0; i < 16; i++) {
      r.pet(atMs: i * 10000);
    }
    r.speak(
        atMs: 150000, requestId: 'speech', sentiment: SpeechSentiment.positive);
    expect(r.advanceTo(180000), EggFeedback.photoRequired);
    expect(r.scoreMilli, 50000);
    r.confirmPhoto(atMs: 180000, eggId: 'egg', photoId: 'photo');
    r.advanceTo(210000);
    expect(r.scoreMilli, 65000);
  });
  test('distance boundary allows a prior hatch but defeats a tied hatch', () {
    AffinityRound setup() {
      final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
      for (var i = 0; i < 17; i++) {
        r.pet(atMs: i * 10000);
      }
      r.confirmPhoto(atMs: 160001, eggId: 'egg', photoId: 'photo');
      for (var i = 17; i < 25; i++) {
        r.pet(atMs: i * 10000);
      }
      r.speak(
          atMs: 240000, requestId: 'x', sentiment: SpeechSentiment.positive);
      return r;
    }

    final earlier = setup();
    expect(earlier.advanceTo(295001, distanceDeadlineReached: true),
        EggFeedback.hatched);
    expect(earlier.hatchedAtMs, 295000);
    final tied = setup();
    expect(tied.advanceTo(295000, distanceDeadlineReached: true),
        EggFeedback.fled);
  });
  test('photo quest still expires and discard is terminal', () {
    final r =
        AffinityRound.start(eggId: 'egg', preferredZone: 1, deadlineMs: 200000);
    for (var i = 0; i < 17; i++) {
      r.pet(atMs: i * 10000);
    }
    expect(r.advanceTo(200000), EggFeedback.fled);
    expect(r.confirmPhoto(atMs: 210000, eggId: 'egg', photoId: 'p'),
        EggFeedback.none);
    final discarded = AffinityRound.start(eggId: 'other', preferredZone: 1);
    discarded.discard(atMs: 0);
    expect(discarded.pet(atMs: 10000), EggFeedback.none);
    expect(discarded.phase, AffinityPhase.discarded);
    expect(AffinityRound.fromJson(discarded.toJson()).phase,
        AffinityPhase.discarded);
  });
  test('zero deadline can roundtrip before it is observed', () {
    final r =
        AffinityRound.start(eggId: 'egg', preferredZone: 1, deadlineMs: 0);
    final restored = AffinityRound.fromJson(r.toJson());
    expect(restored.advanceTo(0), EggFeedback.fled);
  });
  test('round state cannot be changed through public setters', () {
    final r = AffinityRound.start(eggId: 'egg', preferredZone: 1);
    final dynamic external = r;
    final original = r.toJson();
    expect(
        () => external.phase = AffinityPhase.hatched, throwsNoSuchMethodError);
    expect(() => external.scoreMilli = 100000, throwsNoSuchMethodError);
    expect(() => external.photoCompleted = true, throwsNoSuchMethodError);
    expect(() => external.photoId = 'photo', throwsNoSuchMethodError);
    expect(() => external.hatchedAtMs = 0, throwsNoSuchMethodError);
    expect(() => external.elapsedMs = 100, throwsNoSuchMethodError);
    expect(() => external.currentZone = 2, throwsNoSuchMethodError);
    expect(() => external.preferredZone = 2, throwsNoSuchMethodError);
    expect(r.toJson(), original);
  });
}
