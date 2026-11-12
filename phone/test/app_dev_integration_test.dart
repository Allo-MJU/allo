import 'package:allo_phone/app.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:allo_phone/game/game_controller.dart';
import 'package:allo_phone/local_affinity/demo_runtime.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountingApi extends LocalAffinityApi {
  int closeCount = 0;
  @override
  void close() {
    closeCount++;
    super.close();
  }
}

void main() {
  testWidgets(
      'latest debug controller, frame and API lifetime survive Unity integration',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final feed = FakeVehicleFeed(scenario: FakeScenario.clear);
    final api = CountingApi();
    final controller = GameController(feed: feed, dex: DexStore(), eggApi: api);
    var created = 0;
    GameController? framedController;
    await tester.pumpWidget(AlloApp(
      feed: feed,
      useUnityApp: false,
      eggApi: api,
      createController: () {
        created++;
        return controller;
      },
      frameBuilder: (context, actual, child) {
        framedController = actual;
        return Column(children: [
          const Text('병합 검증 프레임'),
          Expanded(child: child),
        ]);
      },
    ));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(framedController, same(controller));
    expect(find.text('병합 검증 프레임'), findsOneWidget);
    expect(api.closed, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(api.closed, isTrue);
    expect(api.closeCount, 1);
  });
}
