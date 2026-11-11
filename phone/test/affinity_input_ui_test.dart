import 'dart:math';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/affinity/egg_demo_api.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/incubating_screen.dart';
import 'package:allo_phone/ui_mode.dart';
import 'package:allo_phone/widgets/affinity_input_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'affinity_controller_test.dart' show DemoApi, RecordingStore;
import 'recurring_incubation_test.dart' show RoundFeed;
import 'session_resume_test.dart' show sessionA;

void main() {
  testWidgets(
      'fullscreen preference still exposes affinity inputs and cooldowns',
      (tester) async {
    final original = fullscreenCabin;
    fullscreenCabin = true;
    addTearDown(() => fullscreenCabin = original);
    final feed = RoundFeed();
    late GameController c;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      c = GameController(
          feed: feed,
          dex: RecordingStore(),
          monotonicMs: () => 0,
          affinityRandom: Random(1));
      await c.pair(sessionA, pairCode: '123456');
      await c.startIncubating(EggTier.small, useAffinity: true);
      feed.sample();
    });
    await tester.pumpWidget(MaterialApp(home: IncubatingScreen(controller: c)));
    await tester.pump();
    expect(find.byType(AffinityInputPanel), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('pet-egg')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pet-egg')));
    await tester.pump();
    expect(c.affinityRound!.score, 3);
    expect(find.text('쓰다듬기 · 10초 후'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(find.byKey(const Key('pet-egg'))).onPressed,
        isNull);
    final zone = c.affinityRound!.preferredZone;
    await tester.ensureVisible(find.byKey(Key('egg-zone-$zone')));
    await tester.pump();
    await tester.tap(find.byKey(Key('egg-zone-$zone')));
    await tester.pump();
    expect(c.affinityRound!.currentZone, zone);
    expect(c.affinityRound!.score, 10);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('talk-egg')))
            .onPressed,
        isNull);
    expect(find.textContaining('말 확인 기능이 아직 연결되지'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('talk text dialog submits once and shows pending and cooldown',
      (tester) async {
    final feed = RoundFeed();
    final api = DemoApi();
    late GameController c;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      c = GameController(
          feed: feed, dex: RecordingStore(), eggApi: api, monotonicMs: () => 0);
      await c.pair(sessionA, pairCode: '123456');
      await c.startIncubating(EggTier.small, useAffinity: true);
      feed.sample();
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
                listenable: c,
                builder: (_, __) => SingleChildScrollView(
                    child: AffinityInputPanel(controller: c))))));
    await tester.pump();
    await tester.tap(find.byKey(const Key('talk-egg')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('이름·학교·주소'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'You can do it');
    await tester.tap(find.text('말 전하기'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    expect(api.speechCalls, 1);
    expect(find.text('말 걸기 · 글로 입력 · 180초 후'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
      'photo quest blocks regular inputs and recover uses server receipt',
      (tester) async {
    var now = 0;
    final feed = RoundFeed();
    final api = DemoApi();
    late GameController c;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      c = GameController(
          feed: feed,
          dex: RecordingStore(),
          eggApi: api,
          monotonicMs: () => now);
      await c.pair(sessionA, pairCode: '123456');
      await c.startIncubating(EggTier.small, useAffinity: true);
      feed.sample();
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
                listenable: c,
                builder: (_, __) => SingleChildScrollView(
                    child: AffinityInputPanel(controller: c))))));
    await tester.pump();
    for (var i = 0; i < 17; i++) {
      await tester.runAsync(c.petEgg);
      now += 10000;
      feed.sample();
      await tester.pump();
    }
    expect(c.affinityRound!.score, 50);
    expect(find.textContaining('사진 퀘스트 · 마음 50점'), findsOneWidget);
    expect(find.byKey(const Key('pet-egg')), findsNothing);
    expect(find.byKey(const Key('talk-egg')), findsNothing);
    expect(find.textContaining('사진 촬영·합성 화면은 아직'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recover-egg-photo')));
    await tester.pump();
    expect(c.affinityRound!.score, 50);
    expect(find.text('아직 확인된 사진이 없어요.'), findsOneWidget);
    api.photos.add(UploadedEggPhoto(
        eggId: c.eggId!,
        requestId: 'verified-photo',
        photoId: 'a' * 32,
        uploadedAtMs: 10));
    await tester.tap(find.byKey(const Key('recover-egg-photo')));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    expect(c.affinityRound!.score, 65);
    expect(find.text('사진 퀘스트 완료'), findsOneWidget);
    expect(find.byKey(const Key('pet-egg')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
