import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/widgets/cabin_geometry.dart';
import 'package:allo_phone/widgets/character_stage.dart';
import 'package:allo_phone/widgets/window_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(320, 240),
    const Size(540, 300),
    const Size(780, 520)
  ]) {
    testWidgets('차 안 $size에서 캐릭터가 실제 창문과 좌석을 붙잡는다', (t) async {
      final c = GameController(
          feed: FakeVehicleFeed(scenario: FakeScenario.clear), dex: DexStore())
        ..game = const GameState(
            ts: 1, eggTier: EggTier.small, stage: Stage.hatched, progress: 1)
        ..vehicle =
            VehicleState.fromJson({'ts': 1, 'gear': 'D', 'speedKph': 30});
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(
                      size: size,
                      child: CharacterStage(
                          controller: c,
                          sceneSize: size,
                          nowMs: () =>
                              t.binding.clock.now().millisecondsSinceEpoch,
                          layoutBuilder: (scene, message) => scene))))));
      await t.pumpAndSettle();
      final window = t.getRect(find.byType(WindowView));
      final layout = CabinLayout(size);
      final target = find.byKey(const ValueKey('character-touch-target'));
      c.vehicle = c.vehicle!.copyWith(ts: 2, wiperLevel: 2);
      c.notifyListeners();
      await t.pumpAndSettle();
      final atWindow = t.getRect(target);
      expect(atWindow.center.dx - window.left,
          closeTo(layout.leftWindowContact.dx, 1));
      expect(atWindow.top + atWindow.height * .32 - window.top,
          closeTo(layout.leftWindowContact.dy, 1));
      c.vehicle = c.vehicle!.copyWith(ts: 3, harshBrake: 1);
      c.notifyListeners();
      await t.pumpAndSettle();
      final atSeat = t.getRect(target);
      expect(atSeat.center.dx - window.left,
          closeTo(layout.passengerSeatGrip.dx, 1));
      expect(atSeat.top + atSeat.height * .18 - window.top,
          closeTo(layout.passengerSeatGrip.dy, 1));
      expect(window.contains(atSeat.topLeft), isTrue);
      expect(window.contains(atSeat.bottomRight), isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
