import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'game/game_controller.dart';
import 'local_affinity/demo_runtime.dart';

/// Runs the general phone screens with explicitly synthetic services and memory-only stores.
Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Local affinity demo is debug only');
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  final feed = LocalAffinityFeed();
  final api = LocalAffinityApi();
  final dex = LocalAffinityDex();
  final entry = DexEntry(
      speciesId: 'road_sprout',
      obtainedAt: DateTime.utc(2026, 11, 12),
      envTags: const [],
      regionTag: null,
      tier: 1);
  await dex.add(entry);
  final controller = GameController(
      feed: feed,
      dex: dex,
      eggApi: api,
      fishingStore: LocalAffinityFishing(),
      pairingStore: LocalAffinityPairing(),
      monotonicMs: () => feed.now);
  await controller.loadSpecies();
  await controller.pair('11111111-1111-4111-8111-111111111111',
      pairCode: '123456');
  await controller.selectCarCompanion(entry);
  runApp(AlloApp(
      feed: feed,
      eggApi: api,
      createController: () => controller,
      frameBuilder: (context, c, child) => Scaffold(
              body: SafeArea(
                  child: Column(children: [
            Material(
                color: const Color(0xffffe6a1),
                child: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                                '로컬 검증 · Firebase/실차/AI/카메라 아님 · 말은 긍정 판정 · 저장은 메모리'),
                            TextButton(
                                onPressed: () => feed.advance(10000),
                                child: const Text('시간 +10초')),
                            TextButton(
                                onPressed: () => feed.advance(60000),
                                child: const Text('시간 +60초')),
                            TextButton(
                                onPressed:
                                    c.game.affinityPhase == 'photoRequired' &&
                                            !c.photoBusy
                                        ? () => c.uploadEggPhoto(
                                            Uint8List.fromList([1, 2, 3]))
                                        : null,
                                child: const Text('모의 사진 완료')),
                          ],
                        ))),
            Expanded(child: child),
          ])))));
}
