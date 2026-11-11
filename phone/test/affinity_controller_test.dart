import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:allo_phone/affinity/egg_demo_api.dart';
import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_incubation_test.dart' show RoundFeed, settle;
import 'session_resume_test.dart' show sessionA;

class DemoApi extends EggDemoApi {
  Completer<SpeechSentiment>? speech;
  SpeechSentiment sentiment = SpeechSentiment.positive;
  int speechCalls = 0;
  bool failPhoto = false;
  bool losePhotoResponse = false;
  bool galleryHidesPhotos = false;
  bool commitOriginalOnRetake = false;
  UploadedEggPhoto? uncommittedPhoto;
  Completer<void>? photoGate;
  final photos = <UploadedEggPhoto>[];
  final photoRequests = <String>[];
  @override
  Future<SpeechSentiment> evaluate(
      {required String eggId,
      required String requestId,
      required String text}) async {
    speechCalls++;
    return speech?.future ?? Future.value(sentiment);
  }

  @override
  Future<UploadedEggPhoto> uploadPhoto(
      {required String eggId,
      required String requestId,
      required Uint8List bytes,
      required String mimeType}) async {
    photoRequests.add(requestId);
    if (failPhoto) throw StateError('private network error');
    if (commitOriginalOnRetake && uncommittedPhoto != null) {
      photos.add(uncommittedPhoto!);
      uncommittedPhoto = null;
      throw const EggDemoApiException('http_error', 'Photo already exists');
    }
    final receipt = UploadedEggPhoto(
        eggId: eggId,
        requestId: requestId,
        photoId: 'a' * 32,
        uploadedAtMs: 10);
    if (commitOriginalOnRetake) {
      uncommittedPhoto = receipt;
      throw StateError('response lost before commit');
    }
    photos.add(receipt);
    await photoGate?.future;
    if (losePhotoResponse) throw StateError('response lost');
    return receipt;
  }

  @override
  Future<List<UploadedEggPhoto>> listPhotos() async =>
      galleryHidesPhotos ? [] : photos;
  @override
  Future<UploadedEggPhoto?> findPhotoForEgg(String eggId) async {
    for (final photo in photos) {
      if (photo.eggId == eggId) return photo;
    }
    return null;
  }

  @override
  Future<Uint8List> downloadPhoto(String photoId) async => Uint8List(0);
  @override
  void close() {}
}

class RecordingStore extends DexStore {
  bool failAdd = false;
  bool failFinal = false;
  Completer<void>? finalGate;
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    if ((progress.round?['game'] as Map?)?['stage'] == 'hatched' &&
        progress.round?['pendingEntry'] == null) {
      await finalGate?.future;
      if (failFinal) throw StateError('final checkpoint failed');
    }
    await super.saveIncubationProgress(tier, progress);
  }

  final attempts = <DexEntry>[];
  final pendingAtAdd = <bool>[];
  @override
  Future<void> add(DexEntry entry) async {
    attempts.add(entry);
    pendingAtAdd.add(
        (await incubationProgress(EggTier.small)).round?['pendingEntry'] !=
            null);
    if (failAdd) throw StateError('disk full');
    await super.add(entry);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'restored affinity checkpoint exposes score instead of legacy timer hatch',
      () async {
    final store = DexStore();
    final firstFeed = RoundFeed();
    final first =
        GameController(feed: firstFeed, dex: store, monotonicMs: () => 0);
    await first.pair(sessionA, pairCode: '123456');
    await first.startIncubating(EggTier.small);
    firstFeed.sample();
    await first.endSession();
    first.dispose();
    final saved = await store.incubationProgress(EggTier.small);
    final round = Map<String, dynamic>.from(saved.round!);
    final affinity = AffinityRound.start(
        eggId: round['eggId'], preferredZone: 1, deadlineMs: 2400000);
    affinity.pet(atMs: 0);
    round['affinity'] = affinity.toJson();
    await store.saveIncubationProgress(
        EggTier.small, IncubationProgress(round: round));
    final feed = RoundFeed();
    final c = GameController(feed: feed, dex: store, monotonicMs: () => 0);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    expect(c.game.toJson()['affinity'], isNotNull);
    expect(c.game.toJson()['affinity'], containsPair('score', 3.0));
    expect(jsonEncode(c.game.toJson()), isNot(contains('photoId')));
    await settle();
  });

  test('source egg id prevents conflicting duplicate collection result',
      () async {
    final store = DexStore();
    Map<String, dynamic> entry(String species) => {
          'speciesId': species,
          'obtainedAt': '2026-11-11T00:00:00.000Z',
          'envTags': <String>[],
          'regionTag': null,
          'tier': 1,
          'sourceEggId': 'egg-a'
        };
    await store.add(DexEntry.fromJson(entry('pebble_pup')));
    await expectLater(
        store.add(DexEntry.fromJson(entry('other'))), throwsStateError);
    expect(await store.all(), hasLength(1));
  });
  var now = 0;
  late RoundFeed feed;
  late GameController c;
  late DemoApi api;
  late DexStore store;
  Future<void> start(
      {DexStore? storage,
      int? eta = 5400,
      bool affinity = true,
      List<String> tags = const []}) async {
    now = 0;
    store = storage ?? DexStore();
    feed = RoundFeed();
    api = DemoApi();
    c = GameController(
        feed: feed,
        dex: store,
        eggApi: api,
        affinityRandom: Random(1),
        monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(
        await c.startIncubating(EggTier.small, useAffinity: affinity), isTrue);
    feed.sample(eta: eta, tags: tags);
  }

  Future<void> advance(int ms, {int? eta = 5400, double distance = 0}) async {
    now += ms;
    feed.sample(eta: eta, distance: distance);
    await settle();
  }

  Future<void> photoGate() async {
    for (var i = 0; i < 17; i++) {
      await c.petEgg();
      if (i < 16) await advance(10000);
    }
    expect(c.affinityRound?.score, 50);
  }

  Future<void> hatch() async {
    await photoGate();
    await c.uploadEggPhoto(Uint8List.fromList([1, 2, 3]));
    for (var i = 0; i < 12; i++) {
      await advance(10000);
      await c.petEgg();
    }
    await settle();
  }

  test('opt in pet cooldown gives vibration and care cannot bypass it',
      () async {
    await start();
    expect(await c.petEgg(), EggFeedback.positive);
    expect(c.affinityRound?.score, 3);
    c.care();
    await settle();
    expect(c.affinityRound?.score, 3);
    expect(await c.petEgg(), EggFeedback.vibration);
    await advance(9999);
    expect(await c.petEgg(), EggFeedback.vibration);
    await advance(1);
    expect(await c.petEgg(), EggFeedback.positive);
    expect(c.affinityRound?.score, 6);
  });
  test(
      'placement changes preferred zone on success only with 15 second cooldown',
      () async {
    await start();
    final r = c.affinityRound!;
    if (r.preferredZone == r.currentZone) {
      await c.placeEgg((r.currentZone + 1) % 4);
      await advance(15000);
    }
    final target = r.preferredZone;
    expect(await c.placeEgg(target), EggFeedback.positive);
    expect(r.score, 7);
    expect(r.preferredZone, isNot(target));
    final next = r.preferredZone;
    expect(await c.placeEgg(next), EggFeedback.vibration);
    expect(r.preferredZone, next);
    await advance(15000);
    final wrong =
        [0, 1, 2, 3].firstWhere((z) => z != r.currentZone && z != next);
    expect(await c.placeEgg(wrong), EggFeedback.vibration);
    expect(r.preferredZone, next);
    expect(r.score, 7);
  });
  test(
      'speech serializes calls, ramps over active 60s and never stores transcript',
      () async {
    await start();
    api.speech = Completer();
    final pending = c.submitEggSpeech('private transcript');
    expect(c.speechBusy, isTrue);
    await c.submitEggSpeech('another');
    expect(api.speechCalls, 1);
    api.speech!.complete(SpeechSentiment.positive);
    expect(await pending, EggFeedback.positive);
    await advance(30000);
    expect(c.affinityRound?.score, 6);
    await c.setAppActive(false);
    now += 100000;
    await c.setAppActive(true);
    await advance(30000);
    expect(c.affinityRound?.score, 12);
    await c.submitEggSpeech('cooldown');
    expect(api.speechCalls, 1);
    await c.setAppActive(false);
    expect(jsonEncode((await store.incubationProgress(EggTier.small)).round),
        isNot(contains('private transcript')));
  });
  test(
      'neutral and negative verdicts consume valid cooldown without fabricated credit',
      () async {
    await start();
    api.sentiment = SpeechSentiment.neutral;
    expect(await c.submitEggSpeech('hello'), EggFeedback.neutral);
    await c.petEgg();
    await advance(180000);
    api.sentiment = SpeechSentiment.negative;
    expect(await c.submitEggSpeech('hello'), EggFeedback.negative);
    expect(c.affinityRound?.score, 0);
  });
  test(
      'photo is mandatory; failed upload retries stable request then grants exactly 15',
      () async {
    await start();
    await photoGate();
    final bytes = Uint8List.fromList([1, 2, 3]);
    await c.petEgg();
    await c.submitEggSpeech('blocked');
    expect(api.speechCalls, 0);
    api.failPhoto = true;
    await c.uploadEggPhoto(bytes);
    expect(c.affinityRound?.score, 50);
    expect(c.error, isNot(contains('private network')));
    api.failPhoto = false;
    await c.uploadEggPhoto(bytes);
    expect(api.photoRequests[0], api.photoRequests[1]);
    expect(c.affinityRound?.score, 65);
    await c.uploadEggPhoto(bytes);
    await c.recoverEggPhoto();
    expect(c.affinityRound?.score, 65);
    expect(api.photoRequests, hasLength(2));
    final remote = jsonEncode(c.game.toJson());
    expect(remote, isNot(contains('photoId')));
    expect(remote, isNot(contains('requestId')));
  });
  test(
      '100 hatches immediately and next egg starts 30 active minutes from actual hatch',
      () async {
    await start(eta: 4800);
    await hatch();
    final id = c.eggId;
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    expect((await store.all()).single.sourceEggId, id);
    await advance(1799999, eta: 600);
    expect(c.eggId, id);
    await advance(1, eta: 600);
    expect(c.eggId, isNot(id));
    expect(c.affinityRound?.score, 0);
    expect(c.game.stage, Stage.incubating);
  });
  test(
      'pending hatch is durable before dex and failed save retries same result once',
      () async {
    final recording = RecordingStore()..failAdd = true;
    await start(storage: recording);
    await hatch();
    expect(c.game.stage, Stage.incubating);
    expect(c.game.affinityPhase, 'resultPending');
    expect(feed.hatchEvents, 0);
    expect(recording.pendingAtAdd, [true]);
    await advance(10000);
    expect(recording.attempts, hasLength(1));
    recording.failAdd = false;
    expect(await c.endSession(), isTrue);
    expect(recording.attempts, hasLength(2));
    expect(recording.attempts.first.toJson(), recording.attempts.last.toJson());
    expect(c.game.stage, Stage.hatched);
    expect(feed.hatchEvents, 1);
    expect(await recording.all(), hasLength(1));
  });
  test(
      'deadline and discard terminate without hatching or accepting late speech',
      () async {
    await start(eta: 120);
    api.speech = Completer();
    final pending = c.submitEggSpeech('waiting');
    await advance(60000);
    expect(c.game.stage, Stage.failed);
    api.speech!.complete(SpeechSentiment.positive);
    await pending;
    expect(c.affinityRound?.score, 0);
    expect(feed.hatchEvents, 0);
    expect(await c.startIncubating(EggTier.small, useAffinity: true), isTrue);
    feed.sample();
    expect(c.affinityRound?.phase, AffinityPhase.incubating);
    await c.discardEgg();
    await advance(5000000);
    expect(c.game.stage, Stage.failed);
    expect(feed.hatchEvents, 0);
  });
  test('pause and session close invalidate in flight callbacks', () async {
    await start();
    api.speech = Completer();
    final pending = c.submitEggSpeech('waiting');
    await c.setAppActive(false);
    await c.setAppActive(true);
    api.speech!.complete(SpeechSentiment.positive);
    await pending;
    expect(c.affinityRound?.score, 0);
    expect(c.affinityRound?.speechRemainingMs, 0);
    api.speech = Completer();
    final next = c.submitEggSpeech('waiting');
    await c.endSession();
    api.speech!.complete(SpeechSentiment.positive);
    await next;
    expect(c.affinityRound?.speechRemainingMs, 0);
  });
  test('distance deadline fails affinity while default legacy still hatches',
      () async {
    await start(eta: null);
    await advance(1000, eta: null, distance: 5000);
    expect(c.game.stage, Stage.failed);
    expect(await store.all(), isEmpty);
  });
  Future<void> restart({bool useAffinity = false}) async {
    await c.setAppActive(false);
    feed = RoundFeed();
    c = GameController(
        feed: feed,
        dex: store,
        eggApi: api,
        monotonicMs: () => now,
        affinityRandom: Random(2));
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small, useAffinity: useAffinity),
        isTrue);
    feed.sample();
  }

  test(
      'restart preserves ramp and cooldown and photo response loss recovers once',
      () async {
    await start();
    await c.submitEggSpeech('good');
    await advance(30000);
    await restart();
    await advance(30000);
    expect(c.affinityRound?.score, 12);
    expect(c.affinityRound?.speechRemainingMs, 120000);
    for (var i = 0; i < 13; i++) {
      await c.petEgg();
      await advance(10000);
    }
    expect(c.affinityRound?.score, 50);
    api.losePhotoResponse = true;
    await c.uploadEggPhoto(Uint8List.fromList([1, 2, 3]));
    expect(c.affinityRound?.score, 50);
    await restart();
    expect(await c.recoverEggPhoto(), EggFeedback.positive);
    expect(c.affinityRound?.score, 65);
    expect(api.photoRequests, hasLength(1));
    await c.recoverEggPhoto();
    expect(c.affinityRound?.score, 65);
  });
  test('late photo after discard cannot resurrect egg', () async {
    await start();
    await photoGate();
    api.photoGate = Completer<void>();
    final upload = c.uploadEggPhoto(Uint8List.fromList([1]));
    await settle();
    expect(c.photoBusy, isTrue);
    await c.discardEgg();
    api.photoGate!.complete();
    await upload;
    expect(c.game.stage, Stage.failed);
    expect(c.affinityRound?.photoCompleted, isFalse);
    expect(c.affinityRound?.score, 50);
  });
  test(
      'remote session end invalidates verdict and does not generate another egg',
      () async {
    await start();
    api.speech = Completer();
    final pending = c.submitEggSpeech('waiting');
    feed.carEvents.add({'by': 'car', 'type': 'sessionEnd'});
    await settle();
    api.speech!.complete(SpeechSentiment.positive);
    await pending;
    expect(c.sessionSaved, isTrue);
    expect(c.affinityRound?.score, 0);
    expect(await c.petEgg(), EggFeedback.none);
  });
  test(
      'distance terminal start has no carried failure and persisted preference survives restart',
      () async {
    await start(eta: null);
    await advance(1000, eta: null, distance: 5000);
    expect(c.game.stage, Stage.failed);
    expect(await c.startIncubating(EggTier.small, useAffinity: true), isTrue);
    feed.sample(eta: null, distance: 5000);
    expect(c.game.stage, Stage.incubating);
    expect(c.affinityRound?.score, 0);
  });
  test(
      'final save failure after dex add survives restart without reroll or duplicate',
      () async {
    final recording = RecordingStore()..failFinal = true;
    await start(storage: recording);
    await hatch();
    expect(c.game.stage, Stage.incubating);
    expect(await store.all(), hasLength(1));
    final original = (await store.all()).single.toJson();
    expect(
        (await store.incubationProgress(EggTier.small)).round?['pendingEntry'],
        isNotNull);
    recording.failFinal = false;
    await restart();
    await settle();
    expect(c.game.stage, Stage.hatched);
    expect(await store.all(), hasLength(1));
    expect((await store.all()).single.toJson(), original);
    expect(feed.hatchEvents, 1);
    expect(
        (await store.incubationProgress(EggTier.small)).round?['pendingEntry'],
        isNull);
  });
  test('independent tick advances speech with no fresh vehicle snapshots',
      () async {
    await start();
    await c.submitEggSpeech('good');
    now = 30000;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(c.affinityRound?.score, 6);
    now = 60000;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(c.affinityRound?.score, 12);
    await c.setAppActive(false);
  });
  test('queued timer checkpoints never overwrite completed hatch checkpoint',
      () async {
    final recording = RecordingStore()..finalGate = Completer();
    await start(storage: recording);
    await photoGate();
    await c.uploadEggPhoto(Uint8List.fromList([1]));
    for (var i = 0; i < 11; i++) {
      await advance(10000);
      await c.petEgg();
    }
    now += 10000;
    final lastPet = c.petEgg();
    await settle();
    expect(c.game.affinityPhase, 'resultPending');
    now += 5000;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    recording.finalGate!.complete();
    await settle();
    await lastPet;
    await settle();
    expect(c.game.stage, Stage.hatched);
    final saved = (await store.incubationProgress(EggTier.small)).round!;
    expect(saved['pendingEntry'], isNull);
    expect((saved['game'] as Map)['stage'], 'hatched');
    await c.setAppActive(false);
  });
  test(
      'restored opt in preference also applies to next egg and explicit failed restart',
      () async {
    await start();
    await hatch();
    await restart();
    await advance(1800000, eta: 600);
    expect(c.affinityRound, isNotNull);
    expect(c.affinityRound?.score, 0);
    await c.discardEgg();
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.sample();
    expect(c.affinityRound, isNotNull);
  });
  test('pending speech remains single flight across pause and resume',
      () async {
    await start();
    api.speech = Completer();
    final pending = c.submitEggSpeech('one');
    await c.setAppActive(false);
    await c.setAppActive(true);
    final duplicate = c.submitEggSpeech('two');
    expect(api.speechCalls, 1);
    api.speech!.complete(SpeechSentiment.positive);
    await pending;
    await duplicate;
    expect(c.affinityRound?.score, 0);
  });
  test('legacy checkpoint remains legacy for current egg when opt in requested',
      () async {
    await start(affinity: false);
    c.care();
    await restart(useAffinity: true);
    expect(c.affinityRound, isNull);
    await advance(2400000);
    expect(c.game.stage, Stage.hatched);
    await advance(1800000, eta: 600);
    expect(c.affinityRound, isNotNull);
    expect(c.affinityRound?.score, 0);
  });
  test('30 minute clock alone cannot grant next egg without fresh vehicle ETA',
      () async {
    await start();
    await hatch();
    final id = c.eggId;
    now += 1800000;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(c.eggId, id);
    feed.sample(eta: 119);
    expect(c.eggId, id);
    feed.sample(eta: 600);
    expect(c.eggId, isNot(id));
  });
  test('affinity distance mode rejects duplicate vehicle timestamps', () async {
    await start(eta: null);
    now += 1000;
    feed.sample(eta: null, distance: 5000, duplicate: true);
    expect(c.game.stage, Stage.incubating);
    feed.sample(eta: null, distance: 5000);
    expect(c.game.stage, Stage.failed);
  });
  test(
      'same source egg deduplicates equivalent persisted JSON regardless of key order',
      () async {
    final entry = DexEntry(
        speciesId: 'pebble_pup',
        obtainedAt: DateTime.utc(2026, 11, 11),
        envTags: const [],
        regionTag: null,
        tier: 1,
        sourceEggId: 'stable-id');
    final reordered = Map.fromEntries(entry.toJson().entries.toList().reversed);
    SharedPreferences.setMockInitialValues({
      'dex.entries.v1': <String>[jsonEncode(reordered)]
    });
    final store = DexStore();
    await store.add(entry);
    expect(await store.all(), hasLength(1));
  });
  test(
      'delayed ramp hatch preserves exact millisecond actual hatch for companion deadline',
      () async {
    await start();
    await photoGate();
    await c.uploadEggPhoto(Uint8List.fromList([1]));
    for (var i = 0; i < 11; i++) {
      await advance(10000);
      await c.petEgg();
    }
    expect(c.affinityRound?.score, 98);
    now += 123;
    await c.submitEggSpeech('good');
    final actualHatch = now + 10000;
    await advance(15000);
    expect(c.game.stage, Stage.hatched);
    expect(c.affinityRound?.hatchedAtMs, actualHatch);
    final id = c.eggId;
    await advance(1794999, eta: 600);
    expect(c.eggId, id);
    await advance(1, eta: 600);
    expect(c.eggId, isNot(id));
  });
  test(
      'retaken bytes reconcile server success after lost photo response before changing request',
      () async {
    await start();
    await photoGate();
    api.losePhotoResponse = true;
    await c.uploadEggPhoto(Uint8List.fromList([1]));
    expect(c.affinityRound?.score, 50);
    expect(api.photos, hasLength(1));
    expect(
        await c.uploadEggPhoto(Uint8List.fromList([2]), mimeType: 'image/png'),
        EggFeedback.positive);
    expect(c.affinityRound?.score, 65);
    expect(api.photoRequests, hasLength(1));
    await c.recoverEggPhoto();
    expect(c.affinityRound?.score, 65);
  });
  test('retake conflict recovers original upload committed after empty lookup',
      () async {
    await start();
    await photoGate();
    api.commitOriginalOnRetake = true;
    await c.uploadEggPhoto(Uint8List.fromList([1]));
    expect(api.photos, isEmpty);
    expect(c.affinityRound?.score, 50);
    expect(
        await c.uploadEggPhoto(Uint8List.fromList([2])), EggFeedback.positive);
    expect(c.affinityRound?.score, 65);
    expect(api.photoRequests, hasLength(2));
    expect(api.photoRequests.first, isNot(api.photoRequests.last));
    expect(api.photos.single.requestId, api.photoRequests.first);
    await c.recoverEggPhoto();
    expect(c.affinityRound?.score, 65);
  });
  test(
      'recovery finds authoritative current egg receipt outside recent gallery',
      () async {
    await start();
    await photoGate();
    api.losePhotoResponse = true;
    await c.uploadEggPhoto(Uint8List.fromList([1]));
    api.galleryHidesPhotos = true;
    await restart();
    expect(await api.listPhotos(), isEmpty);
    expect(await c.recoverEggPhoto(), EggFeedback.positive);
    expect(c.affinityRound?.score, 65);
    expect(api.photoRequests, hasLength(1));
  });
  test(
      'ordinary affinity action checkpoint preserves four seconds of coast evidence',
      () async {
    await start(tags: ['coast']);
    await c.petEgg();
    now = 4000;
    await c.endSession();
    final region =
        (await store.incubationProgress(EggTier.small)).round!['region'] as Map;
    expect((region['durations'] as Map)['coast'], 4000);
    expect(region['unknownMs'], 0);
  });
  Future<void> restoreNearPassiveHatch() async {
    await start();
    await c.setAppActive(false);
    final saved = await store.incubationProgress(EggTier.small);
    final fixture = Map<String, dynamic>.from(saved.round!);
    final affinity = Map<String, dynamic>.from(fixture['affinity'] as Map)
      ..['scoreMilli'] = 99200
      ..['photoCompleted'] = true
      ..['photoId'] = 'a' * 32;
    final engine = AffinityRound.fromJson(affinity);
    engine.speak(
        atMs: 0,
        requestId: 'pending-ramp',
        sentiment: SpeechSentiment.positive);
    fixture['affinity'] = engine.toJson();
    await store.saveIncubationProgress(
        EggTier.small, IncubationProgress(round: fixture));
    feed = RoundFeed();
    c = GameController(
        feed: feed, dex: store, eggApi: api, monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    feed.stamp = 1;
    feed.sample(tags: ['coast'], harsh: 0);
  }

  test(
      'late vehicle sample cannot contaminate passive hatch evidence at four seconds',
      () async {
    await restoreNearPassiveHatch();
    now = 15000;
    feed.sample(tags: ['mountain'], harsh: 100);
    await settle();
    expect(c.affinityRound?.hatchedAtMs, 4000);
    final entry = (await store.all()).single;
    expect(entry.regionTag, 'coast');
    expect(entry.envTags, ['coast']);
    expect(entry.tier, 3);
    final region =
        (await store.incubationProgress(EggTier.small)).round!['region'] as Map;
    expect((region['durations'] as Map)['coast'], 4000);
    expect(region['unknownMs'], 0);
  });
  test(
      'same time passive hatch settles before incoming mountain and harsh evidence',
      () async {
    await restoreNearPassiveHatch();
    now = 4000;
    feed.sample(tags: ['mountain'], harsh: 100);
    await settle();
    final entry = (await store.all()).single;
    expect(entry.regionTag, 'coast');
    expect(entry.envTags, ['coast']);
    expect(entry.tier, 3);
  });
  test(
      'restart before passive hatch preserves prior accumulated counters without live vehicle',
      () async {
    await restoreNearPassiveHatch();
    now = 1000;
    feed.sample(tags: ['coast'], harsh: 5);
    await c.setAppActive(false);
    now += 100000;
    feed = RoundFeed();
    c = GameController(
        feed: feed, dex: store, eggApi: api, monotonicMs: () => now);
    addTearDown(c.dispose);
    await c.pair(sessionA, pairCode: '123456');
    expect(await c.startIncubating(EggTier.small), isTrue);
    expect(c.vehicle, isNull);
    now += 14000;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(c.affinityRound?.hatchedAtMs, 4000);
    final entry = (await store.all()).single;
    expect(entry.tier, 2);
    expect(entry.envTags, ['coast']);
    final region =
        (await store.incubationProgress(EggTier.small)).round!['region'] as Map;
    expect((region['durations'] as Map)['coast'], 1000);
    expect(region['unknownMs'], 3000);
    expect(entry.regionTag, isNull);
  });
  test(
      'resumed late sample cannot replace pre pause accumulated hatch evidence',
      () async {
    await restoreNearPassiveHatch();
    now = 1000;
    feed.sample(tags: ['coast'], harsh: 5);
    await c.setAppActive(false);
    now += 100000;
    await c.setAppActive(true);
    now += 14000;
    feed.sample(tags: ['mountain'], harsh: 100);
    await settle();
    final entry = (await store.all()).single;
    expect(c.affinityRound?.hatchedAtMs, 4000);
    expect(entry.tier, 2);
    expect(entry.envTags, ['coast']);
  });
}
