import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/base_camp/base_camp_controller.dart';
import 'package:allo_phone/base_camp/base_camp_store.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/screens/base_camp_screen.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('좁은 화면에서 친구를 배치하고 건설하면 저장된 작업과 재료가 갱신된다', (tester) async {
    tester.view.physicalSize = const Size(420, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final dex = DexStore(namespace: 'camp-widget.');
    final store = SharedPreferencesBaseCampStore(profile: 'widget');
    var now = 1700000000000;
    late BaseCampController camp;
    late GameController game;
    await tester.runAsync(() async {
      camp = BaseCampController(store: store, dex: dex, nowMs: () => now);
      game = GameController(
          feed: FakeVehicleFeed(scenario: FakeScenario.sceneTour),
          dex: dex,
          baseCamp: camp);
      addTearDown(game.dispose);
      addTearDown(camp.dispose);
      await rootBundle.loadString('assets/data/species.json');
      await dex.add(DexEntry(
          speciesId: 'road_sprout',
          sourceEggId: 'widget-egg',
          obtainedAt: DateTime.utc(2026),
          envTags: const [],
          regionTag: null,
          tier: 1));
      expect(await camp.load(), isTrue);
      await camp.recordLookOut(eventId: 'one');
      now += 60000;
      await camp.recordLookOut(eventId: 'two');
    });
    await tester
        .pumpWidget(MaterialApp(home: BaseCampScreen(controller: game)));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('길싹이').last));
    await tester.pumpAndSettle();
    await flushCamp(tester, camp);
    expect(camp.state.assignments[CampRole.builder],
        camp.state.creatures.keys.single);
    await tester.scrollUntilVisible(find.text('작업장 건설'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('작업장 건설'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await flushCamp(tester, camp);
    expect(camp.state.jobs.containsKey(CampRole.builder), isTrue,
        reason:
            'error=${camp.error} busy=${camp.busy} materials=${camp.state.materials}');
    expect(camp.state.materials[CampMaterial.wood], 0);
    final persisted = await tester.runAsync(() => store.load());
    final saved = BaseCamp.fromJson(persisted!['core'] as Map<String, dynamic>);
    expect(saved.jobs.containsKey(CampRole.builder), isTrue);
    expect(saved.assignments, camp.state.assignments);
    expect(saved.materials, camp.state.materials);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> flushCamp(WidgetTester tester, BaseCampController camp) async {
  for (var i = 0; i < 40 && camp.busy; i++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  await tester.pumpAndSettle();
  expect(camp.busy, isFalse);
}
