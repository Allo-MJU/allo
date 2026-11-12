import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'game/game_controller.dart';
import 'screens/dex_screen.dart';
import 'local_fishing/demo_feed.dart';
import 'local_fishing/demo_stores.dart';

/// Explicit debug entrypoint; never selected by the production main.dart.
Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Local fishing demo is debug only');
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  final dex = LocalDemoDexStore();
  await dex.seed();
  final feed = LocalFishingFeed();
  final controller = GameController(
      feed: feed,
      dex: dex,
      fishingStore: LocalDemoFishingStore(),
      pairingStore: LocalDemoPairingStore());
  await controller.loadSpecies();
  runApp(LocalFishingDemo(controller: controller, feed: feed));
}

class LocalFishingDemo extends StatefulWidget {
  const LocalFishingDemo(
      {super.key, required this.controller, required this.feed});
  final GameController controller;
  final LocalFishingFeed feed;
  @override
  State<LocalFishingDemo> createState() => _LocalFishingDemoState();
}

class _LocalFishingDemoState extends State<LocalFishingDemo>
    with WidgetsBindingObserver {
  late final router = GoRouter(initialLocation: '/dex', routes: [
    GoRoute(
        path: '/dex',
        builder: (_, __) => DexScreen(controller: widget.controller)),
    GoRoute(path: '/pairing', redirect: (_, __) => '/dex'),
  ]);
  Future<void> _connect() => widget.controller
      .pair('11111111-1111-4111-8111-111111111111', pairCode: '123456');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_connect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
        widget.controller.setAppActive(state == AppLifecycleState.resumed));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: '알로 · 로컬 낚시 연동',
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFF4FB3A9), useMaterial3: true),
        routerConfig: router,
        builder: (context, child) => Scaffold(
            body: SafeArea(
                child: Column(children: [
          Container(
              color: const Color(0xFFFFE6A1),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: const Text(
                  '로컬 모의 연동 · 샘플 친구 6종 · 실제 폰 계산/별도 로컬 저장 · Firebase/실차 아님',
                  textAlign: TextAlign.center)),
          ListenableBuilder(
              listenable: Listenable.merge(
                  [widget.controller, widget.feed.status, widget.feed.game]),
              builder: (context, _) {
                final fishing = widget.feed.game.value['fishing'] as Map?;
                return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              '${widget.feed.status.value} | ${widget.controller.fishing.selectedSpeciesId ?? '친구를 선택하세요'} | ${fishing?['state'] ?? '대기'} · ${((fishing?['elapsedMs'] as num? ?? 0) / 1000).floor()}/60초 · 저장된 관찰 ${widget.controller.fishing.totalRecords}건${widget.controller.error == null ? '' : '\n${widget.controller.error}'}')),
                      if (!widget.controller.paired)
                        TextButton(
                            onPressed: widget.controller.busy ? null : _connect,
                            child: const Text('연결 재시도')),
                    ]));
              }),
          Expanded(child: child ?? const SizedBox()),
        ]))),
      );
}
