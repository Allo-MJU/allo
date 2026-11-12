import 'dart:async';
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
import 'screens/incubating_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_end_screen.dart';
import 'storage/dex_store.dart';

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
      this.unityView});

  /// App owns and closes this API; debug entrypoints can supply their adapter.
  final EggDemoApi? eggApi;
  final GameController Function()? createController;
  final Widget Function(BuildContext, GameController, Widget)? frameBuilder;
  final VehicleFeed feed;
  final int Function()? monotonicMs;
  final bool? useUnityApp;
  final bool demoCreatures;
  final UnityViewBuilder? unityView;

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
          baseCamp: camp);
  late final UnityAppController unityApp = UnityAppController(
      game: controller, camp: camp, demoCreatures: _useDemoCreatures);

  late final _router = GoRouter(
    initialLocation: _useUnity ? '/unity' : '/pairing',
    refreshListenable: controller,
    redirect: (_, state) {
      final path = state.uri.path;
      if (path == '/unity') return null;
      if (!controller.sessionEnded) {
        if (path == '/session-end') return '/pairing';
        if (const {'/hatching', '/companion'}.contains(path) &&
            controller.game.stage != Stage.hatched) {
          return '/incubating';
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
          path: '/session-end',
          builder: (_, __) => SessionEndScreen(controller: controller)),
      GoRoute(
          path: '/pairing',
          builder: (_, __) => PairingScreen(controller: controller)),
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
