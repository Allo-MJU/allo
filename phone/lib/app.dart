import 'dart:async';
import 'package:flutter/foundation.dart';
import 'child_chat/chat_screen.dart';
import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'dart:io' show Platform;

import 'affinity/egg_demo_api.dart';
import 'base_camp/base_camp_controller.dart';
import 'base_camp/base_camp_store.dart';
import 'fishing/fishing_store.dart';
import 'unity_app/unity_app_controller.dart';
import 'unity_app/unity_app_screen.dart';
import 'explore/explore_screen.dart';
import 'explore/unity_channel.dart';
import 'feed/vehicle_feed.dart';
import 'feed/fake_feed.dart';
import 'game/game_controller.dart';
import 'screens/companion_screen.dart';
import 'screens/dex_screen.dart';
import 'screens/base_camp_screen.dart';
import 'screens/hatching_screen.dart';
import 'screens/home_screen.dart';
import 'screens/incubating_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_end_screen.dart';
import 'storage/dex_store.dart';
import 'ui_mode.dart';

const unityAppEnabled = bool.fromEnvironment('UNITY_APP', defaultValue: true);
const unityDemoCreaturesEnabled = bool.fromEnvironment('UNITY_DEMO_CREATURES');

class AlloApp extends StatefulWidget {
  const AlloApp(
      {super.key,
      required this.feed,
      this.monotonicMs,
      this.eggApi,
      this.createController,
      this.frameBuilder,
      this.useUnityApp,
      this.demoCreatures = unityDemoCreaturesEnabled,
      this.unityView,
      this.demoSpeciesId});

  /// App owns and closes this API; debug entrypoints can supply their adapter.
  final EggDemoApi? eggApi;
  final GameController Function()? createController;
  final Widget Function(BuildContext, GameController, Widget)? frameBuilder;
  final VehicleFeed feed;
  final int Function()? monotonicMs;
  final bool? useUnityApp;
  final bool demoCreatures;
  final UnityViewBuilder? unityView;

  /// 체험 주행에서 깨어날 종을 고정 (시연용). [GameController.demoSpeciesId]
  final String? demoSpeciesId;

  @override
  State<AlloApp> createState() => _AlloAppState();
}

class _AlloAppState extends State<AlloApp> with WidgetsBindingObserver {
  bool get _useUnity =>
      widget.useUnityApp ?? (Platform.isAndroid && unityAppEnabled);
  bool get _useDemoCreatures =>
      _useUnity &&
      widget.createController == null &&
      widget.demoCreatures &&
      widget.feed is FakeVehicleFeed;
  late final GameController? _providedController =
      widget.createController?.call();
  late final DexStore dex = _providedController?.dex ??
      DexStore(profile: _useDemoCreatures ? 'unity-demo-examples' : 'default');
  late final BaseCampController camp = _providedController?.baseCamp ??
      BaseCampController(
          dex: dex,
          store: SharedPreferencesBaseCampStore(
              profile: _useDemoCreatures
                  ? 'unity-demo-examples'
                  : widget.feed is FakeVehicleFeed
                      ? 'demo'
                      : 'default'));
  late final EggDemoApi? _eggApi = widget.eggApi ??
      (_useUnity && _providedController == null ? _makeEggApi() : null);
  EggDemoApi? _makeEggApi() {
    try {
      return HttpEggDemoApi.fromEnvironment();
    } on EggDemoApiException {
      return null;
    }
  }

  late final GameController controller = _providedController ??
      GameController(
          feed: widget.feed,
          dex: dex,
          monotonicMs: widget.monotonicMs,
          eggApi: _eggApi,
          fishingStore: _useDemoCreatures
              ? FishingStore(profile: 'unity-demo-examples')
              : null,
          baseCamp: camp,
          demoSpeciesId: widget.demoSpeciesId);
  late final _redirectSignal = _RedirectSignal(controller);
  late final UnityAppController unityApp = UnityAppController(
      game: controller, camp: camp, demoCreatures: _useDemoCreatures);

  late final _router = GoRouter(
    initialLocation: _useUnity ? '/unity' : '/pairing',
    refreshListenable: _redirectSignal,
    redirect: (_, state) {
      final path = state.uri.path;
      if (path == '/unity') return null;
      if (path == '/chat' && !kDebugMode) return '/companion';
      if (!controller.sessionEnded) {
        if (path == '/session-end') return '/pairing';
        // 광장 흐름: 주행 중 Flutter 차 안 화면(알 품기·동행) 대신 광장. 차 안은 Unity 탐험에서만
        final plaza = plazaFlow(usesAffinity: controller.usesAffinity);
        if (const {'/hatching', '/companion', '/chat'}.contains(path) &&
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
          !const {'/session-end', '/pairing', '/dex', '/base-camp'}
              .contains(path)) {
        return path == '/session-end' ? null : '/session-end';
      }
      return null;
    },
    routes: [
      GoRoute(
          path: '/unity',
          builder: (_, __) => UnityAppScreen(
              controller: unityApp,
              unityView: widget.unityView ?? androidUnityView)),
      GoRoute(
          path: '/chat',
          builder: (_, __) => ChildChatScreen(
                key: ValueKey(controller.hatched?.id),
                speciesId: controller.hatched?.id ?? 'road_sprout',
                name: controller.hatched?.nameEn ?? 'Road Sprout',
              )),
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
          path: '/base-camp',
          builder: (_, __) => BaseCampScreen(controller: controller)),
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
    if (_useUnity) unawaited(unityApp.initialize());
    unawaited(controller.restorePairing());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycle = state;
    _syncActive();
  }

  AppLifecycleState _lastLifecycle = AppLifecycleState.resumed;

  void _syncActive() {
    if (_useUnity) {
      unawaited(unityApp.setHostLifecycle(_lastLifecycle));
      return;
    }
    unawaited(controller.setAppActive(
        appActiveFor(_lastLifecycle, unityOpen: unityExploreOpen.value)));
  }

  @override
  void dispose() {
    unityExploreOpen.removeListener(_syncActive);
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _redirectSignal.dispose();
    if (_useUnity) unityApp.dispose();
    controller.dispose();
    if (_providedController == null ||
        (_useUnity && _providedController?.baseCamp == null)) {
      camp.dispose();
    }
    _eggApi?.close();
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
