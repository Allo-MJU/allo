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
import 'storage/pairing_store.dart';
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
      game: controller,
      camp: camp,
      demoCreatures: _useDemoCreatures,
      onStartTestConnection:
          controller.isFake ? null : () => _switchConnection(test: true));
  late final ValueNotifier<UnityAppController> _activeUnity =
      ValueNotifier(unityApp);
  late final Future<void> _restorePairing;
  UnityAppController? _testUnity;
  bool _switching = false, _closed = false;
  int _modeRequest = 0;

  UnityAppController _createTestConnection() {
    const profile = 'test-connection';
    final testDex = DexStore(profile: profile);
    final testCamp = BaseCampController(
        dex: testDex, store: SharedPreferencesBaseCampStore(profile: profile));
    final testGame = GameController(
        feed: FakeVehicleFeed(
            scenario: FakeScenario.sceneTour,
            simulateCornering: true,
            retainTripOdometer: true)
          ..setPaused(true),
        dex: testDex,
        baseCamp: testCamp,
        fishingStore: FishingStore(profile: profile),
        pairingStore: PairingStore(namespace: 'profile.$profile.'),
        eggApi: _eggApi ?? controller.eggApi,
        monotonicMs: widget.monotonicMs);
    return UnityAppController(
        game: testGame,
        camp: testCamp,
        onReturnToVehicle: () => _switchConnection(test: false));
  }

  Future<bool> _modeAction(UnityAppController target, String action,
          {String? view}) =>
      target.prepareConnectionAction(action,
          requestId: 'host-mode-${++_modeRequest}', view: view);

  Future<void> _restoreTestOdometer(UnityAppController test) async {
    final trip = await test.game.dex.tripEggLedger(true);
    final id = trip.demoSessionId;
    if (_closed || id == null) return;
    final drives = test.camp.state.toJson()['drives'] as Map;
    if (drives[id] case {'distanceMm': int mm, 'ts': int ts}) {
      (test.game.feed as FakeVehicleFeed)
          .restoreTripOrigin(id, distanceM: mm / 1000, ts: ts);
    }
  }

  Future<bool> _switchConnection({required bool test}) async {
    if (_closed || _switching) return false;
    final current = _activeUnity.value;
    if (current != (test ? unityApp : _testUnity)) return false;
    if (current.game.fishing.hasPendingWrite) return false;
    final startingView = current.view;
    bool currentRequest() =>
        !_closed &&
        current.view == startingView &&
        !current.game.fishing.hasPendingWrite &&
        _lastLifecycle != AppLifecycleState.detached;
    _switching = true;
    var switched = false;
    var createdTest = false;
    UnityAppController? resuming;
    try {
      if (test) {
        await _restorePairing;
        if (!currentRequest() ||
            controller.paired ||
            controller.busy ||
            controller.endingSession) {
          return false;
        }
      }
      if (!test) (current.game.feed as FakeVehicleFeed).setPaused(true);
      if (!await current.setHostLifecycle(AppLifecycleState.detached) ||
          !currentRequest()) {
        return false;
      }
      createdTest = test && _testUnity == null;
      final next = test ? (_testUnity ??= _createTestConnection()) : unityApp;
      if (createdTest) {
        if (!await next.initialize() || !currentRequest()) return false;
        await _restoreTestOdometer(next);
        if (!currentRequest()) return false;
      }
      await next.reloadSettings();
      if (!currentRequest()) return false;
      resuming = next;
      if (!await next.prepareConnectionLifecycle(_lastLifecycle) ||
          !currentRequest()) {
        return false;
      }
      if (!await _modeAction(next, 'navigate', view: 'pairing') ||
          !currentRequest()) {
        return false;
      }
      if (test &&
          (!await _modeAction(next, 'testPair') ||
              !currentRequest() ||
              controller.paired ||
              controller.busy ||
              controller.endingSession)) {
        return false;
      }
      _activeUnity.value = next;
      if (test) (next.game.feed as FakeVehicleFeed).setPaused(false);
      switched = true;
      return true;
    } finally {
      final lifecycle = _lastLifecycle;
      try {
        if (!_closed && !switched) {
          if (createdTest) {
            _disposeTestConnection();
          } else if (resuming != null) {
            await resuming.setHostLifecycle(AppLifecycleState.detached);
          }
          if (!_closed) {
            await current.setHostLifecycle(lifecycle);
            if (!test && !_closed) {
              (current.game.feed as FakeVehicleFeed).setPaused(false);
            }
          }
        }
      } finally {
        _switching = false;
        if (!_closed && (switched || _lastLifecycle != lifecycle)) {
          _syncActive();
        }
      }
    }
  }

  void _disposeTestConnection() {
    final test = _testUnity;
    _testUnity = null;
    if (test == null) return;
    test.dispose();
    test.game.dispose();
    test.camp.dispose();
  }

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
          builder: (_, __) => ValueListenableBuilder<UnityAppController>(
              valueListenable: _activeUnity,
              builder: (_, active, __) => UnityAppScreen(
                  controller: active,
                  unityView: widget.unityView ?? androidUnityView))),
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
    _restorePairing = controller.restorePairing();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycle = state;
    _syncActive();
  }

  AppLifecycleState _lastLifecycle = AppLifecycleState.resumed;

  void _syncActive() {
    if (_useUnity) {
      if (!_switching) {
        unawaited(_activeUnity.value.setHostLifecycle(_lastLifecycle));
      }
      return;
    }
    unawaited(controller.setAppActive(
        appActiveFor(_lastLifecycle, unityOpen: unityExploreOpen.value)));
  }

  @override
  void dispose() {
    _closed = true;
    unityExploreOpen.removeListener(_syncActive);
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _redirectSignal.dispose();
    if (_useUnity) {
      _activeUnity.dispose();
      _disposeTestConnection();
      unityApp.dispose();
    }
    controller.dispose();
    if (_providedController == null ||
        (_useUnity && _providedController.baseCamp == null)) {
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
