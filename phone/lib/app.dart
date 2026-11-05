import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  const AlloApp({super.key, required this.feed});
  final VehicleFeed feed;

  @override
  State<AlloApp> createState() => _AlloAppState();
}

class _AlloAppState extends State<AlloApp> {
  late final GameController controller =
      GameController(feed: widget.feed, dex: DexStore());

  late final _router = GoRouter(
    initialLocation: '/pairing',
    refreshListenable: controller,
    redirect: (_, state) {
      final path = state.uri.path;
      if (!controller.sessionEnded) {
        return path == '/session-end' ? '/pairing' : null;
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
    ],
  );

  @override
  void initState() {
    super.initState();
    unawaited(controller.restorePairing());
  }

  @override
  void dispose() {
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
