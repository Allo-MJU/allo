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
import 'screens/incubating_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_end_screen.dart';
import 'storage/dex_store.dart';

class AlloApp extends StatefulWidget {
  const AlloApp({super.key, required this.feed, this.monotonicMs});
  final VehicleFeed feed;
  final int Function()? monotonicMs;

  @override
  State<AlloApp> createState() => _AlloAppState();
}

class _AlloAppState extends State<AlloApp> with WidgetsBindingObserver {
  late final GameController controller = GameController(
      feed: widget.feed, dex: DexStore(), monotonicMs: widget.monotonicMs);

  late final _router = GoRouter(
    initialLocation: '/pairing',
    refreshListenable: controller,
    redirect: (_, state) {
      final path = state.uri.path;
      if (!controller.sessionEnded) {
        if (path == '/session-end') return '/pairing';
        if (const {'/hatching', '/companion'}.contains(path) &&
            controller.game.stage != Stage.hatched) {
          return '/incubating';
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
              unityView: Platform.isAndroid ? androidUnityView : null)),
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
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '알로',
      theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4FB3A9), useMaterial3: true),
      routerConfig: _router,
    );
  }
}
