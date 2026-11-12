import 'dart:async';
import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'dart:io' show Platform;

import 'explore/explore_screen.dart';
import 'explore/unity_channel.dart';
import 'feed/vehicle_feed.dart';
import 'game/game_controller.dart';
import 'screens/companion_screen.dart';
import 'screens/dex_screen.dart';
import 'screens/hatching_screen.dart';
import 'screens/home_screen.dart';
import 'screens/incubating_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_end_screen.dart';
import 'storage/dex_store.dart';
import 'ui_mode.dart';
import 'affinity/egg_demo_api.dart';

class AlloApp extends StatefulWidget {
  const AlloApp(
      {super.key,
      required this.feed,
      this.monotonicMs,
      this.eggApi,
      this.createController,
      this.frameBuilder,
      this.demoSpeciesId});

  /// App owns and closes this API. Absent configuration leaves server inputs unavailable.
  final EggDemoApi? eggApi;
  final GameController Function()? createController;
  final Widget Function(BuildContext, GameController, Widget)? frameBuilder;
  final VehicleFeed feed;
  final int Function()? monotonicMs;

  /// 체험 주행에서 깨어날 종을 고정 (시연용). [GameController.demoSpeciesId]
  final String? demoSpeciesId;

  @override
  State<AlloApp> createState() => _AlloAppState();
}

class _AlloAppState extends State<AlloApp> with WidgetsBindingObserver {
  late final GameController controller = widget.createController?.call() ??
      GameController(
          feed: widget.feed,
          dex: DexStore(),
          monotonicMs: widget.monotonicMs,
          eggApi: widget.eggApi,
          demoSpeciesId: widget.demoSpeciesId);

  late final _redirectSignal = _RedirectSignal(controller);

  late final _router = GoRouter(
    initialLocation: '/pairing',
    refreshListenable: _redirectSignal,
    redirect: (_, state) {
      final path = state.uri.path;
      if (!controller.sessionEnded) {
        if (path == '/session-end') return '/pairing';
        // 광장 흐름: 주행 중 Flutter 차 안 화면(알 품기·동행) 대신 광장. 차 안은 Unity 탐험에서만
        final plaza = plazaFlow(usesAffinity: controller.usesAffinity);
        if (const {'/hatching', '/companion'}.contains(path) &&
            controller.game.stage != Stage.hatched) {
          return plaza ? '/home' : '/incubating';
        }
        if (plaza && const {'/incubating', '/companion'}.contains(path)) {
          return '/home';
        }
        if (!plaza && path == '/home') {
          return controller.game.stage == Stage.hatched
              ? '/companion'
              : '/incubating';
        }
        return null;
      }
      if (!controller.sessionSaved ||
          !const {'/session-end', '/pairing', '/dex'}.contains(path)) {
        return path == '/session-end' ? null : '/session-end';
      }
      return null;
    },
    routes: [
      GoRoute(
          path: '/session-end',
          builder: (_, __) => SessionEndScreen(controller: controller)),
      GoRoute(
          path: '/pairing',
          builder: (_, __) => PairingScreen(controller: controller)),
      GoRoute(
          path: '/home',
          builder: (_, __) => HomeScreen(controller: controller)),
      GoRoute(
          path: '/incubating',
          builder: (_, __) => IncubatingScreen(controller: controller)),
      GoRoute(
          path: '/hatching',
          builder: (_, __) => HatchingScreen(controller: controller)),
      GoRoute(
          path: '/companion',
          builder: (_, __) => CompanionScreen(controller: controller)),
      GoRoute(
          path: '/dex', builder: (_, __) => DexScreen(controller: controller)),
      GoRoute(
          path: '/explore',
          builder: (_, __) => ExploreScreen(
              controller: controller,
              unityView: Platform.isAndroid ? androidUnityView : null,
              closeUnity: Platform.isAndroid ? closeUnityExplore : null)),
    ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unityExploreOpen.addListener(_syncActive);
    unawaited(controller.restorePairing());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycle = state;
    _syncActive();
  }

  AppLifecycleState _lastLifecycle = AppLifecycleState.resumed;

  void _syncActive() {
    unawaited(controller.setAppActive(
        appActiveFor(_lastLifecycle, unityOpen: unityExploreOpen.value)));
  }

  @override
  void dispose() {
    unityExploreOpen.removeListener(_syncActive);
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _redirectSignal.dispose();
    controller.dispose();
    widget.eggApi?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '알로',
      theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4FB3A9), useMaterial3: true),
      routerConfig: _router,
      builder: (context, child) =>
          widget.frameBuilder
              ?.call(context, controller, child ?? const SizedBox()) ??
          child ??
          const SizedBox(),
    );
  }
}

/// 라우터가 경로를 다시 계산하게 하는 신호. [GameController] 는 차 신호마다(1초) 알리는데,
/// 그때마다 라우터가 redirect 를 다시 돌리면 화면을 닫는 도중(pop 애니메이션)에 닫던 화면을
/// 현재 주소로 다시 만든다 — 차 안에서 나오자마자 Unity 가 다시 열리고, 도감에서 돌아오면 광장이 사라지던 원인.
/// redirect 가 보는 값(세션 종료·저장, 알 단계, 마음 품기)이 바뀔 때만 알린다.
class _RedirectSignal extends ChangeNotifier {
  _RedirectSignal(this.controller) {
    _last = _key;
    controller.addListener(_check);
  }

  final GameController controller;
  late (bool, bool, Stage, bool) _last;

  (bool, bool, Stage, bool) get _key => (
        controller.sessionEnded,
        controller.sessionSaved,
        controller.game.stage,
        controller.usesAffinity,
      );

  void _check() {
    final k = _key;
    if (k == _last) return;
    _last = k;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_check);
    super.dispose();
  }
}
